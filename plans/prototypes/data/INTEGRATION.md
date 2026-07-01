# Phase-1 On-Device Verdict — Integration Guide

> **Verified against merged `main` (94805b3, post-PR #1 / CloudKit+CI merge).**
> The pbxproj anchors (`A5000006` Services group, `B6000001` Sources phase) still
> exist and the new file IDs below (`F1000002`/`F2000002`/`F1000003`/`F2000003`)
> are still unused — the file-add steps apply as written. `CheckTabView`'s scan
> flow (`runScan → buildScan → currentScan → VerdictCardView`) is structurally
> unchanged by the MVP merge, so the wiring insertion points below still hold;
> line numbers may differ slightly after the MVP's UI polish.

This document describes how to wire the new instant, on-device verdict engine
into the SipCheck Xcode project and scan flow.

Two new Swift source files were added (do NOT need network / barcode):

- `SipCheck/Services/TasteScorer.swift` — pure scoring: name → `BeerStyle?`
  inference, candidate scoring against `TasteProfile` + `TastePreferences`,
  verdict mapping (`.tryIt` / `.yourCall` / `.skipIt`), and the deterministic
  tiebreaker.
- `SipCheck/Services/MenuParser.swift` — parses a multi-line OCR menu blob into
  `[BeerCandidate]` (with the junk-line confidence floor) and picks the single
  best winner by reusing `TasteScorer`.

Both are pure / synchronous and unit-test friendly (no UI, no `PreviewProvider`).

---

## (a) Xcode `project.pbxproj` Entries

These files live in the `Services` group (`A5000006`) alongside `TastePreferences.swift`
and must be added to the **SipCheck app target** `Sources` build phase
(`B6000001` — the phase whose `files` list begins with `A1000001 /* SipCheckApp.swift */`).

The existing `F`-prefixed IDs (`F1000001` / `F2000001`) belong to `TastePreferences`.
Continue that block with `F1000002` / `F2000002` and `F1000003` / `F2000003`.
All four IDs below are currently unused in `project.pbxproj`.

### 1. `PBXBuildFile` section

Find the `/* Begin PBXBuildFile section */` block and add, next to the
`F1000001 /* TastePreferences.swift in Sources */` line:

```
		F1000002 /* TasteScorer.swift in Sources */ = {isa = PBXBuildFile; fileRef = F2000002; };
		F1000003 /* MenuParser.swift in Sources */ = {isa = PBXBuildFile; fileRef = F2000003; };
```

### 2. `PBXFileReference` section

Find the `/* Begin PBXFileReference section */` block and add, next to the
`F2000001 /* TastePreferences.swift */` line:

```
		F2000002 /* TasteScorer.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = TasteScorer.swift; sourceTree = "<group>"; };
		F2000003 /* MenuParser.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MenuParser.swift; sourceTree = "<group>"; };
```

### 3. `Services` group (`A5000006`) — `children`

In the `A5000006 /* Services */` `PBXGroup`, add the two file refs after
`F2000001 /* TastePreferences.swift */,`:

```
				F2000002 /* TasteScorer.swift */,
				F2000003 /* MenuParser.swift */,
```

### 4. App target `Sources` build phase (`B6000001`) — `files`

In the app target's `PBXSourcesBuildPhase` `files` list, add after
`F1000001 /* TastePreferences.swift in Sources */,`:

```
				F1000002 /* TasteScorer.swift in Sources */,
				F1000003 /* MenuParser.swift in Sources */,
```

> Note: these go in the **app** Sources phase (`B6000001`), NOT the test target
> phase (`B6000002`). If unit tests reference these types directly, the app
> module is already `@testable import`-ed by the existing tests, so no separate
> test-target membership is required.

### (Optional) Unit test files

If you add `TasteScorerTests.swift` / `MenuParserTests.swift` under the test
group, follow the existing `B`-prefix pattern (`B1000009`/`B2000009`, …): a
`PBXBuildFile`, a `PBXFileReference`, a `children` entry in the tests group
(`A5000004`-style group), and a `files` entry in the **test** Sources phase
(`B6000002`).

---

## (b) Wiring the Instant Verdict into the Scan Flow

Goal: the on-device verdict shows **first** (instant, free, offline); the
network LLM becomes **optional enrichment** that fills in richer copy / brewery
origin afterward, without blocking the user-facing answer.

### Where the taste library comes from

`TasteScorer` needs a `TasteProfile` and `TastePreferences`:

- `TasteProfile.build(from: drinkStore.drinks)` — already available; `CheckTabView`
  has `@EnvironmentObject var drinkStore: DrinkStore`.
- `TastePreferences.current` — reads from `UserDefaults` (no injection needed).

### Option A — Instant verdict for single-beer text/label scan

In `CheckTabView.runScan(text:)` and `runScan(image:)`, compute and show the
on-device verdict **before** awaiting the network, then enrich:

1. Build the profile once at call time:
   ```swift
   let profile = TasteProfile.build(from: drinkStore.drinks)
   let prefs = TastePreferences.current
   ```
2. For a text scan, infer style + ABV locally and assess immediately:
   ```swift
   let abv = MenuParser.extractABV(from: trimmed)
   let assessment = TasteScorer.assess(
       name: trimmed,
       style: nil,                 // let TasteScorer infer from the name
       abv: abv,
       profile: profile,
       preferences: prefs
   )
   let instant = Scan(
       beerName: trimmed,
       style: TasteScorer.inferStyle(from: trimmed)?.rawValue,
       abv: abv,
       verdict: assessment.verdict,
       explanation: assessment.shortReason
   )
   await MainActor.run { finalizeScan(instant) }   // show instantly
   ```
3. THEN kick the existing `ScanningPipeline` call as enrichment. When it
   returns, **update** the already-shown scan in place (keep the on-device
   verdict if the network fails):
   ```swift
   if let result = try? await ScanningPipeline.shared.scan(text: trimmed) {
       var enriched = instant
       enriched.explanation = result.explanation     // richer copy
       enriched.origin = result.beerInfo.origin       // brewery story
       if let style = result.beerInfo.style { enriched.style = style.rawValue }
       if let a = result.beerInfo.abv { enriched.abv = a }
       // Keep the instant verdict; only overwrite if you trust the LLM more.
       await MainActor.run {
           scanStore.updateScan(enriched)
           currentScan = enriched
       }
   }
   ```
   Because `finalizeScan` already added the scan to `scanStore` and set
   `currentScan`, the enrichment just mutates the same record by `id`.

This removes the need for the `scanningView` spinner to block: `isScanning`
can be set to `false` as soon as the instant verdict is shown, and enrichment
happens quietly in the background.

### Option B — Menu mode (the prototype's headline use case)

For a photographed **menu** (many beers at once), add a menu entry point that
calls `MenuParser` directly on the OCR text — no network at all:

1. Run `VisionOCRService.extractText(from: image)` (already used by the pipeline).
2. Feed the OCR text to the parser:
   ```swift
   let verdict = MenuParser.evaluate(
       ocrResult.text,
       profile: TasteProfile.build(from: drinkStore.drinks),
       preferences: TastePreferences.current
   )
   if let winner = verdict.winner {
       let scan = Scan(
           beerName: winner.name,
           style: winner.style?.rawValue,
           abv: winner.abv,
           verdict: winner.assessment.verdict,
           explanation: winner.assessment.shortReason
       )
       finalizeScan(scan)
   }
   ```
3. `verdict.ranked` holds every candidate best-first (already tiebroken) if you
   want to show the full menu ranking, not just the single winner.

### `ScanningPipeline` changes (optional, recommended)

To keep `CheckTabView` thin, add an instant-first method to `ScanningPipeline`:

```swift
/// Instant on-device verdict for a text/name scan. No network.
func instantVerdict(
    forText text: String,
    profile: TasteProfile,
    preferences: TastePreferences
) -> ScanResult {
    let start = CFAbsoluteTimeGetCurrent()
    let style = TasteScorer.inferStyle(from: text)
    let abv = MenuParser.extractABV(from: text)
    let assessment = TasteScorer.assess(
        name: text, style: style, abv: abv,
        profile: profile, preferences: preferences
    )
    let info = BeerInfo(name: text, brand: nil, style: style, abv: abv, origin: nil)
    return ScanResult(
        beerInfo: info,
        verdict: assessment.verdict,
        explanation: assessment.shortReason,
        scanSource: .ocrPlusText,           // or add a new `.onDevice` case
        latencyMs: Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    )
}
```

Consider adding a `case onDevice = "on-device"` to
`ScanResult.ScanSource` so analytics can distinguish the instant path from the
OCR+LLM and vision-fallback paths. (Not required for the verdict to work.)

### Net behavior after wiring

1. User scans / types → instant `TasteScorer` verdict appears (<1ms, offline).
2. Network LLM call (if a key is configured and the device is online) runs in
   the background and silently enriches the same `Scan` record.
3. If the network is unavailable or fails, the user keeps the instant verdict —
   the on-device path is the source of truth, the LLM is additive only.
