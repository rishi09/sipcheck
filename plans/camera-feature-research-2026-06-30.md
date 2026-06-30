# Camera Feature Research — Kickoff

**Date: 2026-06-30 · Author: research kickoff · Status: proposal for review**

> This is a direction-setting research doc, not a record of shipped code. It builds on the
> earlier `vision-api-comparison.md` and `notes-next-steps.md`, re-scoped around the actual
> ask: a *fast, free, point-and-decide* scan that handles **labels, menus, and typed input** —
> not just a single bottle label.

---

## 0. Goal & locked decisions (read this first)

**Goal:** ship a camera scan that is **fast** and **free**, reads a **label, a menu, or a typed
name** (never assuming a clean barcode), and returns an **instant 👍/👎** based on the user's taste
library — and **validate the risky parts with prototypes before committing to a full build.**

Expanded per user direction:
- **Source real data / open libraries.** Use open beer datasets and label-image libraries (real
  beer names, styles, ABVs, barcodes, label photos) to ground the simulation in reality, not toy
  inputs. See §10 / `plans/prototypes/data/` and the image-library manifest.
- **Simulate as much as possible.** This environment has **no Swift/Xcode**, so the iOS code is a
  write-and-review deliverable; the *behavioral validation* runs as a Python simulation over the
  real dataset (style-inference accuracy, verdict quality, single-winner sensibility at scale).
- **Build everything that's buildable here.** Author the real Phase-1 Swift (instant on-device
  verdict + menu parse + single-winner) following `CLAUDE.md`, leaving only the device-only spike
  (Foundation Models + live `DataScanner`) for Xcode.
- **Run it as an agent team.** Orchestrated via a dynamic multi-agent workflow (gather → simulate →
  build → verify); see §11.

Product direction locked with the user:

| Decision | Choice |
|---|---|
| Scan feel | **Live, no shutter** — point and it reads, verdict pops automatically |
| Menu result | **One clear winner** — "Order this" highlighted, tap for runner-up |
| Verdict priority | **Instant & always works offline** — short reliable reason over a slow rich one |
| Cold-start | **Quick taste quiz** at first launch — personalized from scan #1 |
| Barcode | **Bonus only, never assumed.** Primary path is label/menu/typed text. If a barcode happens to be in frame we use it; we never wait for or require one. |
| Stack | **OK to replace** the current `UIImagePickerController` + always-network-verdict stack |

Validation is part of the goal — see **§10** for the prototype already run.

---

## 1. The use case (what "fast" actually means)

Two real moments define the bar:

- **Grocery aisle, wife waiting.** User is holding a 4-pack, comparing two shelves. They want a
  thumbs up / down *now*, ideally before they've even framed a perfect photo.
- **Restaurant, waiter approaching.** User glances at a printed/chalkboard beer menu with 8–20
  names. They need "which of these should I order?" in the seconds before the waiter arrives.

Design implications:
- **Latency budget: a verdict on screen in < 1s, ideally < 300ms for the common case.** A spinner
  that waits on a network round-trip *fails* the waiter test.
- The input is **not always a barcode**, often not even a single beer — a **menu is a list**.
- Must degrade gracefully with **bad signal** (store basement, crowded restaurant wifi) and
  **bad framing** (glare, angle, shelf clutter).
- **Free product** → every network LLM call is a cost and a latency tax. The default path should
  be **$0 and on-device**; the network is enrichment, not the critical path.

---

## 2. What already exists (build on this, don't rebuild)

The repo already has a working hybrid stack. Inventory so we extend rather than duplicate:

| Capability | File | State |
|---|---|---|
| Still-photo capture | `Views/Components/CameraView.swift` | `UIImagePickerController` — tap-shutter only |
| On-device OCR | `Services/VisionOCRService.swift` | `VNRecognizeTextRequest` (`.accurate`), returns text + confidence |
| Scan orchestration | `Services/ScanningPipeline.swift` | OCR → Gemini text fast path; OpenAI vision fallback when OCR weak |
| Text-entry path | `Views/Tabs/CheckTabView.swift` | "Enter beer name" sheet → same pipeline |
| Fuzzy local match | `Services/BeerMatcher.swift` | exact → contains → Levenshtein ≥0.7 against history |
| Taste inputs | `Services/TastePreferences.swift`, `Models/TasteProfile.swift` | onboarding prefs + history-derived profile |
| Verdict | `Services/GeminiService.swift` (`getVerdictAndExplanation`) | **always a network LLM call** |

**The three gaps versus this request:**
1. **Capture is tap-shutter, single-frame.** No live "point and it reads," no barcode, no menu.
2. **The verdict always hits the network.** That's the latency/cost wall for the waiter test and
   for "free product."
3. **Nothing handles a menu** (many candidate beers → ranked decision).

This doc focuses on closing those three.

---

## 3. "Apple had a vision model, right?" — yes, three of them, and they matter

The user's instinct is correct. As of iOS 26 there are **three** on-device Apple capabilities that,
combined, let us do the *entire* fast path with **no network and no cost**:

### 3a. VisionKit `DataScannerViewController` — the real "point and read" camera (iOS 16+)
This is the upgrade to our current `UIImagePickerController`. It runs **AVCapture + Vision live**
on the camera feed and surfaces recognized **text and barcodes in real time** — no shutter tap.
- `recognizedDataTypes`: `.text(...)` **and** `.barcode(symbologies:)` simultaneously.
- `recognizesMultipleItems = true` → returns **all** items in frame at once. *This is the menu
  primitive* — point at a beer list and get every line as a `RecognizedItem`.
- `qualityLevel`: `.fast` / `.balanced` / `.accurate`.
- Delegate callbacks (`didAdd` / `didTapOn` / `didRemove`) stream items as they appear; barcodes
  expose `payloadStringValue`, text exposes its transcript.
- Requires a Neural-Engine device (A12+) — fine for our target.

**Why it beats the current flow:** zero shutter latency, live highlighting of detected beers, and
free multi-item detection for menus. ([WWDC22 "Capture machine-readable codes and text"](https://developer.apple.com/videos/play/wwdc2022/10025/), [DataScannerViewController docs](https://developer.apple.com/documentation/visionkit/datascannerviewcontroller))

### 3b. Vision framework barcode + OCR (already partly used)
For still images / when we want our own controller, `VNDetectBarcodesRequest` gives UPC/EAN, and
`VNRecognizeTextRequest` (what `VisionOCRService` already uses) gives label text. Keep
`VisionOCRService` as the still-image path; `DataScanner` becomes the live path.

### 3c. **Foundation Models framework — on-device LLM (iOS 26+).** This is the big unlock.
Apple now ships an on-device LLM (the ~3B model behind Apple Intelligence) with a Swift API:
- `LanguageModelSession` for prompting; **Guided Generation** via the `@Generable` macro returns
  **type-safe Swift structs directly** — no JSON parsing, no flaky string handling.
- **Free, offline, private, low-latency.** No API key, no per-call cost, works in a signal-dead
  store basement.
- Availability gated to Apple-Intelligence devices (iPhone 15 Pro+ / A17 Pro+ / M-series) on
  iOS 26+. Older devices need a fallback (see §6).

**This is what makes "free product + fast verdict + offline" actually achievable.** Instead of
`GeminiService.getVerdictAndExplanation` always hitting the network, the verdict + one-line
"why" can run on-device in a few hundred ms at $0.

([Foundation Models docs](https://developer.apple.com/documentation/FoundationModels), [Meet the Foundation Models framework — WWDC25](https://developer.apple.com/videos/play/wwdc2025/286/), [Deep dive — WWDC25](https://developer.apple.com/videos/play/wwdc2025/301/))

> Note: `FastVLM` (from the old comparison doc) stays **out of scope** — it's an experimental
> CoreML conversion with no first-party framework. Foundation Models supersedes it as the
> "on-device intelligence" answer.

---

## 4. Proposed architecture — tiered, on-device-first

The principle: **always show *something* instantly from on-device, then optionally enrich.** The
user should never stare at a spinner waiting on a network call to get a thumbs up/down.

```
                 ┌─────────────────────────────────────────────┐
                 │  Live camera (DataScannerViewController)      │
                 │  recognizes: barcodes + text, multi-item ON   │
                 └───────────────┬───────────────────────────────┘
                                 │  (or: still photo → VisionOCR, or: typed text)
                 ┌───────────────▼───────────────┐
   Input router  │ barcode?   label?   menu(list)? │
                 └───┬────────────┬────────────┬───┘
                     │            │            │
     ┌───────────────▼──┐  ┌──────▼───────┐  ┌─▼─────────────────────────┐
     │ UPC → Open Food  │  │ OCR text →   │  │ Split lines → N candidate  │
     │ Facts (free,     │  │ beer name    │  │ beer names (rank top 3-5)  │
     │ keyless lookup)  │  │ guess        │  │                            │
     └───────────────┬──┘  └──────┬───────┘  └─┬─────────────────────────┘
                     │            │            │
                     └────────────┼────────────┘
                                  ▼
              ┌───────────────────────────────────────────┐
        TIER 1│  ON-DEVICE VERDICT (instant, $0, offline)  │  ← shows immediately
              │  match against taste library + heuristics  │
              │  OR Foundation Models @Generable verdict   │
              └───────────────────┬───────────────────────┘
                                  ▼  (optional, only if uncertain / user taps "why")
              ┌───────────────────────────────────────────┐
        TIER 2│  NETWORK ENRICHMENT (Gemini/OpenAI)        │  ← refines, never blocks
              │  better beer ID, richer explanation        │
              └───────────────────────────────────────────┘
```

### Tier 1 — the instant on-device verdict (the heart of this feature)
Two interchangeable engines, pick per device capability:

**(a) Heuristic matcher (works on *every* device, truly instant):**
Score a candidate beer's style/ABV against the taste library:
- Liked styles (`TasteProfile.favoriteStyles`) + onboarding `vibe` → **+points**
- `TasteProfile.dislikedStyles` + onboarding `dislikes` → **−points**
- ABV proximity to `averageABV` → small modifier
- Map score → `.tryIt` / `.yourCall` / `.skipIt` (reuse existing `Verdict`)

This is a few lines of arithmetic — sub-millisecond, no model, no network. It alone satisfies the
waiter test for the common case where we recognize the style.

**(b) Foundation Models verdict (richer, on iOS 26 Apple-Intelligence devices):**
Feed the candidate + `TasteProfile.promptSummary` + `TastePreferences.promptSummary` into a
`LanguageModelSession` with a `@Generable` result type, e.g.:

```swift
@Generable
struct OnDeviceVerdict {
    @Guide(description: "tryIt, yourCall, or skipIt")
    let verdict: String
    @Guide(description: "one short sentence, personal, references their taste")
    let reason: String
}
```

Returns a typed struct in a few hundred ms, offline, $0. Use this for the one-line "why" so it
feels personal, not just a heuristic score.

### Tier 2 — network enrichment (optional, never on the critical path)
Keep the existing Gemini/OpenAI path for: (1) beers the on-device tier can't identify from text
alone (stylized labels, obscure brands), and (2) a "Tell me more" expansion the user explicitly
taps. The screen already shows a Tier-1 verdict by the time this returns.

---

## 5. The three input modes, concretely

### 5a. Label (bottle/can) — text first, barcode is a bonus
**Primary:** `DataScanner` reads the **label text** live → best-guess beer name/style → Tier-1
verdict. This is the path we design and tune for, because users won't reliably present a barcode
(label facing out, 4-pack, shelf angle, glare).
**Bonus, opportunistic:** if a barcode *happens* to land in frame, do a keyless Open Food Facts
lookup (`GET world.openfoodfacts.org/api/v2/product/{barcode}.json`, descriptive `User-Agent`) for
an exact product hit. We **never wait for or require** one — it's a free upgrade when it appears.
([Open Food Facts API](https://openfoodfacts.github.io/openfoodfacts-server/api/), [data/SDKs](https://world.openfoodfacts.org/data))

> Per the user: **do not assume a clean barcode, and keep it fast.** Text/OCR is the contract; the
> barcode is icing. The §10 prototype runs entirely on the no-barcode text path.

### 5b. Menu — the genuinely new capability
A menu is **N beers, decide across them**. Flow:
1. `DataScanner` with `recognizesMultipleItems = true` (or still-photo OCR over the menu).
2. **Segment lines into candidate beer entries.** Beer menus are messy (name + brewery + ABV +
   price on one line, or wrapped). Start with heuristics (line grouping, strip price/ABV tokens);
   escalate to a Foundation Models `@Generable [BeerCandidate]` extraction for robustness.
3. **Score every candidate against the taste library (Tier 1)** — all on-device, all instant.
4. **Rank and surface the top 1–3 as "order this," dim the skips.** This is the killer UX for the
   waiter moment: glance at the menu, see the winner highlighted.
5. Optional: tap a candidate → Tier-2 enrichment for detail.

> This is the biggest single departure from today's pipeline, which assumes one beer per scan.
> Suggest prototyping the menu ranker against a few real photographed beer menus early.

### 5c. Typed input — already works, keep it
`CheckTabView`'s "Enter beer name" sheet already routes text through the pipeline. Only change:
route its verdict through **Tier 1 first** so typed entries also get the instant on-device verdict
before any network call. Good fallback when OCR fails (chalkboard menu, weird lighting).

---

## 6. Defaults & cold-start (so a brand-new user still gets a verdict)

The taste library may be empty on first run. The verdict must still work:
- **Seed a default `TasteProfile`** from onboarding (`TastePreferences` already captures
  `vibe` / `adventure` / `dislikes`). If even that's empty, fall back to a neutral popular-style
  prior (e.g. lean approachable: lager/pale ale/IPA positive, extreme sour/very high ABV cautious)
  so the first scan returns `.yourCall`/`.tryIt` rather than nothing.
- Every thumbs up/down the user gives feeds back into `TasteProfile.build(from:)`, so Tier-1
  accuracy improves with use — no model training, just the existing history aggregation.

**Device capability fallback ladder** (so we don't strand older phones):
1. iOS 26 + Apple Intelligence device → Foundation Models verdict (richest, free, offline).
2. Any device → heuristic matcher verdict (instant, free, offline).
3. Network available + low confidence → Gemini/OpenAI enrichment (existing code).

---

## 7. Cost & "free product" analysis

| Path | Per-scan cost | Latency | Offline? |
|---|---|---|---|
| Barcode → Open Food Facts | **$0** (keyless) | ~100–400ms (1 GET) | No (needs net) |
| On-device OCR (`VisionOCR`/DataScanner) | **$0** | ~100–300ms | **Yes** |
| Tier-1 heuristic verdict | **$0** | <1ms | **Yes** |
| Tier-1 Foundation Models verdict | **$0** | ~200–600ms | **Yes** |
| Tier-2 Gemini text enrich (only when needed) | ~$0.0001 | ~0.5–1.2s | No |
| Tier-2 OpenAI vision fallback (rare) | ~$0.003 | 2–6s | No |

**Target outcome:** ~80–90% of scans resolve fully on-device at **$0** and sub-second. The paid
network path becomes a rare fallback, not the default — which is exactly what a free product needs.
At 10k scans/month this is **~$0–1** versus ~$30–50 for the old vision-only approach.

---

## 8. Suggested phasing

- **Phase 0 — spike (½ day):** Confirm `FoundationModels` availability check + a trivial
  `@Generable` verdict on a target device; confirm `DataScanner` multi-item text on a real beer
  menu photo. De-risks the two unknowns before committing.
- **Phase 1 — instant verdict:** Add the Tier-1 heuristic matcher; route the *existing* label /
  text flows through it so verdicts show instantly, with the current Gemini call demoted to
  Tier-2 enrichment. Highest value, lowest risk, no new camera code.
- **Phase 2 — live + barcode capture:** Replace/augment `CameraView` with a
  `DataScannerViewController` wrapper; add barcode → Open Food Facts lookup.
- **Phase 3 — menu mode:** Multi-item detection + candidate segmentation + ranked "order this" UI.
- **Phase 4 — Foundation Models verdict:** Swap the Tier-1 engine to Foundation Models on capable
  devices for personalized one-line reasons; keep heuristic as universal fallback.

---

## 9. Open questions for product

1. **Min iOS / device floor.** Foundation Models needs iOS 26 + Apple-Intelligence hardware. Are we
   OK gating the *richest* path to those devices (with heuristic fallback elsewhere), or do we hold
   it until adoption is higher?
2. **Menu ranking UX.** Highlight a single "order this" winner, or show a ranked top-3 with reasons?
3. **Open Food Facts beer coverage.** Needs a quick eval — how many real grocery beers actually
   resolve by barcode? (Determines how much we lean on barcode vs OCR.) Build a small eval set from
   real store captures, as `notes-next-steps.md` already suggested.
4. **Privacy copy.** On-device-first is a genuine privacy selling point ("your scans never leave
   your phone" for the default path) — worth surfacing in onboarding/marketing.

---

## 10. Validation prototype (run, not hypothetical)

To de-risk the single biggest unknown — *can we turn a messy photographed menu into one good pick,
on-device, with no barcode and no network?* — `plans/prototypes/menu_verdict_prototype.py`
implements the **exact logic the Swift app would run** (menu-text parsing → style inference from
name keywords → taste-library scoring → single-winner selection). No barcode, no network, no LLM —
just string parsing + arithmetic, i.e. the sub-millisecond on-device path. Run it with
`python3 plans/prototypes/menu_verdict_prototype.py`.

**Results across three realistic OCR-style inputs (restaurant menu, chalkboard, grocery cooler):**
- ✅ Parsed noisy lines (brewery + ABV + `$price` + dashes/bullets) into clean candidate beers.
- ✅ Inferred style from the **name alone** — no database, no network (`Pliny… Double IPA` → ipa,
  `Old Rasputin Imperial Stout` → stout, `Sumpin Sour Ale` → sour).
- ✅ Picked **one clear winner** every time, with a one-line reason — the locked "one clear winner"
  + "instant reason" UX.
- ✅ **Personalizes from the same menu:** hop-forward profile → *Pliny the Elder*; malty/safe
  profile → *Guinness*. Proves the verdict reflects the taste library, not a hard-coded favorite.
- ✅ Degrades on a sparse grocery shelf (names only, no ABV/price) and still ranks correctly.

**Two honest flaws the prototype surfaced (now backlog items, cheap to fix in Swift):**
1. **Junk-line leakage.** A non-beer line slipped through as a candidate. → Need a parse-confidence
   floor: drop lines with no inferable style *and* no ABV/price signal, or that look like headers.
2. **Top-score ties.** Two IPAs tied at the top and list order broke the tie. → Add a deterministic
   tiebreaker (closer-to-ideal ABV, then higher liked-style weight) so "the winner" is stable.

**Takeaway:** the fast/free/no-barcode/instant-verdict path is **viable** — the core algorithm works
on realistic input today. Remaining risk is iOS-device-only and belongs in a Phase 0 device spike
(Foundation Models availability + `DataScanner` live multi-item on a real menu), not in the logic.

---

## Sources
- [Foundation Models — Apple Developer Documentation](https://developer.apple.com/documentation/FoundationModels)
- [Meet the Foundation Models framework — WWDC25](https://developer.apple.com/videos/play/wwdc2025/286/)
- [Deep dive into the Foundation Models framework — WWDC25](https://developer.apple.com/videos/play/wwdc2025/301/)
- [DataScannerViewController — Apple Developer Documentation](https://developer.apple.com/documentation/visionkit/datascannerviewcontroller)
- [Capture machine-readable codes and text with VisionKit — WWDC22](https://developer.apple.com/videos/play/wwdc2022/10025/)
- [Open Food Facts API tutorial](https://openfoodfacts.github.io/openfoodfacts-server/api/tutorial-off-api/)
- [Open Food Facts — Data, API and SDKs](https://world.openfoodfacts.org/data)
- Prior internal research: `plans/vision-api-comparison.md`, `plans/notes-next-steps.md`
