# Phase-0 Device Spike — what we're checking & how

**Goal:** in ~half a day on a real iPhone, prove the two things this Linux env couldn't —
so we know the "fast, free, instant verdict" plan holds before building the full feature.

**Device:** Rishi's iPhone 16 (A18 → Apple-Intelligence capable), on **iOS 26**, built from Xcode
(Cmd+R). Foundation Models + live DataScanner are device-only; the Simulator can't validate them.

---

## The two unknowns (this is what we're checking)

| # | Question | Pass looks like |
|---|---|---|
| **A** | Does the **live camera** reliably read the text off a real **menu** and a real **can/label**? | Off a can we get the **brewery + beer name + printed style** ("Hazy IPA"); off a menu we get clean per-beer lines. |
| **B** | Does the **on-device LLM** (Foundation Models) turn that text into a **good verdict, fast, offline, free**? | A sensible 👍/🤷/👎 + one-line reason in **well under 1s**, airplane-mode ON. |
| **C** | Does it **feel instant end-to-end** and **never block** on anything? | Verdict on screen fast; no spinner waiting on network. |

If A and B pass, the whole approach is de-risked. If either fails, we learn the fallback now (below).

---

## Prerequisite: is the on-device model even available?

Gate everything on this first — it fails cleanly on unsupported devices/regions.

```swift
import FoundationModels

func modelStatus() -> String {
    switch SystemLanguageModel.default.availability {   // API shape — verify in Xcode autocomplete
    case .available:            return "✅ ready"
    case .unavailable(let why): return "❌ unavailable: \(why)"
    }
}
```
- If unavailable → note the reason (device not eligible / Apple Intelligence off / model still downloading).
  The heuristic `TasteScorer` is the fallback verdict engine on any device.

> **Macro note:** Foundation Models' guided generation uses the `@Generable` macro. Our CLAUDE.md
> avoids macros because of *CLI-sandbox* build issues — but this spike builds via **Xcode on-device**,
> where macros are fine. If `@Generable` ever misbehaves, Probe B has a no-macro fallback.

---

## Probe A — live OCR off real beer (VisionKit `DataScannerViewController`)

**Setup:** a throwaway SwiftUI screen that starts a live scanner and just logs what it sees.

```swift
import SwiftUI, VisionKit

struct SpikeScannerView: UIViewControllerRepresentable {
    var onText: (String) -> Void
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let s = DataScannerViewController(
            recognizedDataTypes: [.text()],       // add .barcode(...) later; text is the point here
            qualityLevel: .balanced,
            recognizesMultipleItems: true,        // whole menu at once
            isHighFrameRateTrackingEnabled: true,
            isHighlightingEnabled: true)
        s.delegate = context.coordinator
        try? s.startScanning()
        return s
    }
    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Coord { Coord(onText: onText) }

    final class Coord: NSObject, DataScannerViewControllerDelegate {
        let onText: (String) -> Void
        init(onText: @escaping (String) -> Void) { self.onText = onText }
        func dataScanner(_ s: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) {
            for case let .text(t) in allItems { onText(t.transcript) }
        }
    }
}
```
(Guard `DataScannerViewController.isSupported && .isAvailable` before presenting. Camera usage
string already exists in the app.)

**What to point it at — and what to record:**
1. **Your Smog City "Watt Strike" can** → do we get `Smog City`, `Watt Strike`, **`Hazy IPA`**? (ABV expected missing.)
2. **2–3 other cans** with different label styles (one very graphic/stylized, one plain).
3. **A printed beer menu** (or a photo of one) → do we get one clean line per beer with style/ABV?
4. **A chalkboard / handwritten menu** → how badly does it degrade?

**Record for each:** the raw transcript, and ✅/⚠️/❌ on whether name + style came through.
**Pass bar:** cans give name + (usually) style; printed menus give usable per-beer lines.
**If it fails** (pure-logo can, no readable text): that's the case for later visual matching — note it,
don't solve it now. Typed entry is the fallback.

---

## Probe B — on-device verdict (Foundation Models)

**Setup:** feed the text from Probe A (or the hardcoded samples below) to the model and time it.

```swift
import FoundationModels

@Generable
struct BeerVerdict {
    @Guide(description: "One of: order, maybe, skip")
    var verdict: String
    @Guide(description: "One short, personal sentence referencing the drinker's taste")
    var reason: String
}

func verdict(labelText: String, taste: String) async throws -> (BeerVerdict, Double) {
    let session = LanguageModelSession(instructions: """
        You help a beer drinker decide fast. Given text read off a label or menu and their taste, \
        return order / maybe / skip with one short reason. If unsure of the style, be cautious (maybe).
        """)
    let prompt = "Label text: \"\(labelText)\". Drinker taste: \(taste)."
    let t0 = Date()
    let out = try await session.respond(to: prompt, generating: BeerVerdict.self)  // verify signature
    return (out.content, Date().timeIntervalSince(t0))
}
```

**Test inputs (cover the real cases):**
- `"Smog City Watt Strike Hazy IPA"` + taste `"loves IPAs, hates sour"` → expect **order**.
- `"Two Hearted"` (name only, no style) → does the model *know* it's an IPA? (tests LLM world-knowledge.)
- `"Guinness Draught Stout 4.2%"` + taste `"loves stouts"` → expect **order**.
- `"Lambic Framboise"` + taste `"hates sour"` → expect **skip**.

**Record:** latency (ms) per call, and whether the verdict + reason are sensible.
**Pass bar:** sensible verdicts, **< ~700ms**, and it still works with **airplane mode ON** (proves offline/free).
**No-macro fallback** (if `@Generable` fights the build): ask for plain text and parse —
`session.respond(to: prompt + " Reply as: VERDICT | reason")` then split on `|`.

---

## Probe C — end-to-end feel (30 min, after A & B pass)

Wire it: `DataScanner` text → `BeerResolver.resolve(recognizedText:using: BundledCatalog())`
→ show `TasteScorer` verdict **immediately** → *then* optionally call Probe B to enrich the reason.
- ✅ Verdict appears fast from the on-device path; the LLM refines the wording after, never blocks.
- Confirm the instant heuristic verdict shows even before/without the LLM.

---

## Decision

| Result | Meaning |
|---|---|
| A ✅ + B ✅ | **Green light** — build the feature; on-device fast/free path is real. |
| A ✅ + B ❌ | Keep the heuristic `TasteScorer` as the verdict; LLM is polish only. Still shippable. |
| A ❌ (text unreadable often) | Lean on **typed entry** + menu path; revisit **visual label matching** as its own phase. |
| Model unavailable on device | Ship heuristic-only verdict now; treat LLM as an enhancement for eligible devices. |

**Timebox:** ~half a day. Log results back here (or as a comment) and we pick the build path.

> API signatures above are the expected shapes for iOS 26 — confirm against Xcode autocomplete,
> as Foundation Models / VisionKit details may have shifted since the research was written.
