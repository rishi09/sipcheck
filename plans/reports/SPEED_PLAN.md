# SipCheck Speed Plan

**North star:** the verdict is computed entirely on-device from data already in memory (taste profile + bundled catalog + OCR). The network never sits between a tap and a verdict — it only *improves* a verdict already on screen. Every fix below serves that.

---

## 1. Latency Budgets

| # | Interaction | Current (estimated) | Target | Dominated by |
|---|---|---|---|---|
| 1 | Cold launch → Check tab usable | 300ms–1s+ (grows with scans.json) | **<1.5s** (store loads off first frame; <150ms main-thread work in `App.init`) | 3× sync read+backup-write+decode in store inits; CloudKit fullSync photo re-download |
| 2 | Tap "Scan Label" → live viewfinder | 500–1000ms (cold `UIImagePickerController` per presentation) | **<100ms perceived** (sheet animates instantly, frames within ~250ms via pre-warmed session) | Camera session cold start |
| 3 | Shutter → verdict card (scan #1) | 4–60s (network chain) + 500–1500ms Vision cold load + 30–100ms catalog decode | **<1s offline, <600ms typical** | `runScan` awaiting full `ScanningPipeline`; cold Vision/catalog |
| 4 | Shutter → verdict card (scan #10) | 1.5–30s | **<600ms** (same as scan #1 — that's the point) | Same network chain |
| 5 | Typed name → verdict ("Check This Beer") | 800ms–30s (`scan(text:)` = 2 serial network round trips) | **<200ms** (catalog + TasteScorer only) | Wasted network verdict call |
| 6 | Tap Save (Add Beer sheet) → sheet dismisses | 100–600ms + double-tap dupes | **<100ms** (optimistic dismiss) | Awaited photo compression + 3 main-thread JSON writes |
| 7 | Tap "Save for Later" → visible acknowledgment | ∞ (no UI response at all) | **<50ms** (immediate button state flip + haptic) | Missing optimistic UI |
| 8 | Journal search keystroke / list scroll frame | 5–15ms/keystroke + dropped frames on photo rows | **<8ms/frame** (60fps headroom) | Per-row `DateFormatter` init; sync photo decode in `body` |

---

## 2. The Architecture Move: Verdict-First, Network-Never-Awaited

One structural change buys interactions 3, 4, and 5 simultaneously: **invert `runScan` so the on-device verdict renders first and all network work becomes cancellable post-verdict refinement.** Everything `buildScan` needs (OCR text, `TasteProfile`, `BundledCatalog`, `TasteScorer`) is local and takes ~300ms; today it runs *after* a 4–60s network chain whose verdict output is literally discarded (`CheckTabView.swift:396` overwrites it).

### UI state machine

Replace the implicit `isScanning`/`currentScan`/`scanError` trio with one explicit enum on `CheckTabView` (still plain `@State` — no macros needed):

```swift
enum ScanPhase: Equatable {
    case idle
    case recognizing                    // OCR running, ≤ ~300ms; keep the spinner
    case verdict(Scan, refining: Bool)  // card visible; refining=true shows a small badge
    case failed(String)                 // only if even OCR/local path throws
}
```

Legal transitions: `idle → recognizing → verdict(refining: true) → verdict(refining: false)`. The network can **never** move the machine backward — a refinement failure just flips `refining` to `false` and keeps the card. `.failed` is reachable only from `recognizing` (e.g., no image), never from refinement.

Add to `Scan` (Codable, additive): `var explanationSource: String? // "device" | "network"`.

### Task structure (exact shape)

```swift
// CheckTabView
@State private var scanTask: Task<Void, Never>?
@State private var refineTask: Task<Void, Never>?

private func runScan(image: UIImage) {
    guard case .idle = phase else { return }   // also covers .verdict re-entry via resetScanState
    phase = .recognizing
    refineTask?.cancel()

    scanTask = Task(priority: .userInitiated) {
        // ---- Stage 1: on-device, <1s hard budget ----
        let ocr = await VisionOCRService.extractText(from: image)   // ~100ms warm
        let scan = buildScanOnDevice(fromText: ocr.text, path: "image") // OCR→BeerResolver→TasteScorer, all local
        await MainActor.run {
            finalizeScan(scan)                  // addScan + phase = .verdict(scan, refining: shouldRefine)
        }

        // ---- Stage 2: network refinement, detached from the card ----
        guard NetworkMonitor.shared.isSatisfied else { return }     // NWPathMonitor wrapper, see fix list
        refineTask = Task(priority: .utility) {
            // single merged prompt: extraction + explanation copy, NO verdict field
            guard let enriched = try? await ScanningPipeline.shared.enrich(
                ocrText: ocr.text, deviceScan: scan, budget: .seconds(5)
            ) else { return }
            try? Task.checkCancellation()
            await MainActor.run {
                guard case .verdict(var current, _) = phase, current.id == scan.id else { return }
                // Patch ONLY enrichment fields; verdict stays on-device.
                current.explanation = enriched.explanation ?? current.explanation
                current.style = current.style ?? enriched.style?.rawValue
                current.abv = current.abv ?? enriched.abv
                current.origin = current.origin ?? enriched.origin
                current.explanationSource = "network"
                scanStore.updateScan(current)
                phase = .verdict(current, refining: false)
            }
        }
    }
}
```

Key properties:

- **Priorities:** stage 1 is `.userInitiated` (it gates pixels); refinement is `.utility` (background QoS, doesn't compete with UI or the camera).
- **Cancellation points:** `resetScanState()` and "Scan Another" cancel `refineTask` (a stale enrichment must never patch a new scan — the `current.id == scan.id` guard is the backstop). Sheet dismissal and tab switch cancel both tasks. Every network call inside `enrich` is wrapped in a `withTimeout` race so cancellation actually propagates through `URLSession` (`task.cancel()` on the racing child).
- **`enrich` replaces `scan`:** `ScanningPipeline` gets a new entry point that does *one* merged prompt (beer info + 2-sentence explanation as a single JSON blob — no verdict field, since it's dead code) with Gemini given a 3s slice, then OpenAI, inside a 5s total budget. `scan(text:)` for typed names skips OCR and skips the network entirely on the critical path — catalog + TasteScorer answer in <200ms.
- **`VerdictCardView`** gains a `refining: Bool` prop → small pulsing "refining…" pill top-right; explanation text cross-fades when patched. The verdict emoji/color never changes after render (trust: the answer doesn't flip-flop).
- **Offline is a first-class success path:** with no signal, stage 2 simply never starts and the card is final at ~300ms — which *is* the product spec.

Same pattern reused in `AddBeerView.processImageWithAI` (prefill from OCR+resolver instantly, network refines fields) and `CheckBeerView` (render `drinkStore.findMatch` result instantly, stream the recommendation in after).

---

## 3. Ranked Fix List

### Day 1 — critical path (the aisle moment)

| # | File | Change | Saves |
|---|---|---|---|
| 1 | `CheckTabView.swift:331–376` + `ScanningPipeline.swift:43,77,98` | The architecture move above: verdict-first `runScan`, `ScanPhase` enum, `enrich()` entry point, stop requesting a verdict from the network at all. Covers hotspots #1 and #2. | **3.5–59s → ~0.3–0.6s** on every scan; typed-name path 0.8–30s → <200ms |
| 2 | `ScanningPipeline.swift:107–137` | Merge extract+explanation into one prompt/one JSON response inside `enrich`; Gemini gets a 3s budget then OpenAI starts (race, not serial); gate on `NWPathMonitor` (`NetworkMonitor` singleton, ~20 lines) — offline skips straight to done; add a tiny persisted cache (`[normalizedName: BeerInfo+explanation]`, cap 200, JSON in Caches/) consulted before any call, plus `ScanStore.findMatch` first. | Halves round trips; kills the 30s dead-provider burn offline; re-scan at checkout = 0ms |
| 3 | `OpenAIService.swift:294`, `GeminiService.swift:164` | One shared `URLSession(configuration:)` with `.ephemeral`, `timeoutIntervalForRequest = 4`, `timeoutIntervalForResource = 6`, `waitsForConnectivity = false`; inject into both services; wrap calls in `withTimeout` race. | Caps worst case per hop at 6s (was 15s idle + 7-day resource); whole enrichment chain ≤5s |
| 4 | `VisionOCRService.swift:70` | Warm-up: after first frame, `Task.detached(priority: .utility)` runs `VNRecognizeTextRequest(.accurate)` on a 64×64 solid-color CGImage; repeat cheaply on Check-tab appear. Wrap `handler.perform()` in `DispatchQueue.global(qos: .userInitiated)` via continuation so it stops pinning a cooperative-pool thread. | 500–1500ms off scan #1 (the "scan #1 as fast as scan #10" requirement) |
| 5 | `BeerResolver.swift:139/157/192` | Warm `BundledCatalog.shared` in the same launch warm-up task; in `init`, precompute `normalizedName` per entry so the fuzzy pass does zero per-call allocation. | 30–100ms off scan #1; 2–10ms off every fuzzy lookup |
| 6 | `CameraView.swift:9`, `CheckTabView.swift:66` | Short-term: create the `UIImagePickerController` once, hold it in a coordinator/session controller, reuse across presentations; set a lower `cameraCaptureMode`/resolution. Real fix (spec-mandated): VisionKit `DataScannerViewController` owned by a controller started on Check-tab appear and kept warm across "Scan Another" — text arrives live, no shutter, no 12MP processing. | 500–1000ms viewfinder cold start + 300–600ms shutter-to-callback, on every scan |

**Day 1 exit criteria:** airplane-mode scan → verdict <1s; scan #1 ≈ scan #10; typed name → verdict <200ms.

### Week 1 — feel (every tap responds)

| # | File | Change | Saves |
|---|---|---|---|
| 7 | `AddBeerView.swift:182,218` | Optimistic save: generate `photoFileName = "\(drinkId).jpg"` up front, `dismiss()` synchronously in the button action, run compression + store writes in a detached `Task`; disable Save on first tap; `.success` haptic. | 100–600ms → <100ms perceived; kills double-tap duplicates |
| 8 | `CheckTabView.swift:453`, `VerdictCardView.swift:86` | Optimistic "Save for Later": flip to filled "Saved ✓", disable, `UIImpactFeedbackGenerator(.medium)`, update `currentScan`/`phase` immediately; persistence unchanged underneath. | Perceived ∞ → <50ms; kills re-tap write/notification storms |
| 9 | `NotificationService.swift:59` | Remove `requestAuthorization()` from `scheduleFollowUp`; guard scheduling with `getNotificationSettings` (no-op when undetermined); request permission contextually on first "Save for Later" tap. | Un-blocks the first verdict reveal (multi-second dialog at the payoff moment) |
| 10 | `SipCheckApp.swift:50`, `DrinkStore.swift:133`, `JournalStore.swift:122`, `ScanStore.swift:124` | Init stores with empty arrays; load+decode on a background task in each init, publish to `@Published` on main; move the backup write to the same background queue. | 20–100ms+ off cold launch main thread (grows with data) |
| 11 | `ScanStore.swift` (+ `DrinkStore`, `JournalStore`) | ✅ Implemented 2026-07-15: snapshot arrays at mutation time, encode+atomic-write on one serial background queue per store, coalesce in-flight mutations, and flush on app background. | 5–200ms main stall off verdict presentation, Save-for-Later, and every mutation |
| 12 | `CheckBeerView.swift:278–318` | Render found/notFound from `drinkStore.findMatch` immediately (keep local result on network failure); image path calls the extraction-only pipeline entry (no verdict trip); recommendation via gpt-4o-mini/Gemini Flash streamed into a placeholder in the card. | 4–90s → instant local answer + async enrichment |
| 13 | `AddBeerView.swift:152` | Use the extraction-only entry point; prefill instantly from OCR + `BeerResolver.resolve`, network refines fields async. | 0.5–30s off label autofill |
| 14 | `JournalEntryRow.swift:7` | `static let formatter` or `date.formatted(.dateTime.month(.abbreviated).day())`. | 5–15ms per search keystroke; per-row scroll hitches |
| 15 | `BeerListView.swift:176`, `DrinkStore.swift:165` | Async row images: `.task` per row → background read + `CGImageSourceCreateThumbnailAtIndex(maxPixelSize: 100)` → `@State` image; `NSCache` keyed by `fileName+size`. | 5–20ms/row → 0 on main; ends first-scroll dropped frames |

### Later — scale (keeps year-2 as fast as day-1)

| # | File | Change | Saves |
|---|---|---|---|
| 16 | `ScanStore.swift:37,61,67` | Prune: cap non-`wantToTry`/non-linked scans at 200 (or 90 days); hard-delete tombstones >30 days past `lastModifiedLocal`; purge on load and after `applyRemoteScans`; batch-delete corresponding CKRecords. | Converts every O(lifetime) cost above into O(200): save, launch decode, sync |
| 17 | `CloudKitSyncService.swift:57,182` | `desiredKeys` excluding `photoAsset` on all launch fetches; fetch assets lazily when a view needs a missing local file; `materializePhotoAsset` skips copy when destination exists. Then: custom zone + `CKFetchRecordZoneChangesOperation` with persisted change token (delta sync). | 30–50MB cellular per cold launch → ~0; launch fetch O(deltas) |
| 18 | `CloudKitSyncService.swift:34,115` | Batch uploads via `CKModifyRecordsOperation` (~200–400/op, `.allKeys` for known-missing records — no pre-fetch); cache fetched server records (system-fields archive) so individual saves skip `fetchOrCreate`; 2s debounce on repeated saves of one record; keep `WriteQueue` for single user edits only. | New-device sync minutes → seconds; deleteAllScans no longer jams the queue |
| 19 | `CloudKitSyncService.swift:214,303` | Attach `photoAsset` only when changed: compare `photoFileName` + file mtime (or `photoModifiedAt`) against the fetched server record; nil the field only on `photoFileName → nil` transition. | 100–300KB → ~1KB per rating tweak; unclogs WriteQueue |
| 20 | `ScanStore.swift:84` (+ `DrinkStore.swift:86`, `JournalStore.swift:78`) | Merge/sort remote data off-main (pure function over snapshots); hop to MainActor only to assign `@Published`; route the post-merge save through the background queue from #11; skip save when merge is a no-op. | 15–200ms main stall a few seconds after launch — right when the user taps Scan Label |

---

## 4. Pre-warming Plan

All warm-up rides one detached, low-priority task fired **after** the first frame — launch itself stays skinny (`App.init` does allocations only after fix #10).

```swift
// RootView (SipCheckApp.swift), once:
.task {  // runs after first render
    Task.detached(priority: .utility) {
        // 1. Catalog: decode 350KB + build normalized index off-main (~30–100ms)
        _ = BundledCatalog.shared.lookup(name: "warmup")
        // 2. Vision: page in .accurate text-recognition models (~0.5–1.5s, background)
        await VisionOCRService.warmUp()   // VNRecognizeTextRequest on 64×64 blank CGImage
        // 3. Taste profile: pre-build once drinks have loaded (cheap, but removes it from scan #1)
        //    then cache in DrinkStore, invalidate on addDrink/updateDrink.
        _ = await TasteProfileCache.shared.profile(for: DrinkStore.sharedSnapshot)
    }
}
```

- **Camera:** don't warm at launch (battery + permission prompt risk). Warm on **Check tab appear**: start the persistent capture session / `DataScannerViewController` controller (fix #6) when the tab becomes visible, stop it on disappear with a ~10s grace timer so "Scan Another" and tab-flicker don't cold-start. Result: tapping Scan Label presents an already-running viewfinder.
- **Ordering/QoS:** everything `.utility`, strictly after first frame, each step independently skippable. Warm-up must never take a lock or actor the UI needs; catalog and Vision have no shared state with the render path.
- **CloudKit `fullSync`:** stays post-launch but moves *behind* the warm-up in priority and (after fix #17) transfers deltas only, so it stops competing with scan #1's radio and CPU.
- **Verification that launch stayed fast:** the launch signpost (below) must not regress; warm-up work is visible as background intervals, not pre-first-frame ones.

---

## 5. Measurement

### Signposts (do this first — before fixing anything, to get baselines)

One `OSSignposter` in a small `Perf.swift`:

```swift
enum Perf {
    static let signposter = OSSignposter(subsystem: "com.rishishah.sipcheck", category: "latency")
}
// Usage:
let state = Perf.signposter.beginInterval("scan", id: Perf.signposter.makeSignpostID())
// … Perf.signposter.emitEvent("ocr-done"); emitEvent("verdict-rendered"); emitEvent("enriched")
Perf.signposter.endInterval("scan", state)
```

Instrument exactly these intervals: `launch` (App.init → first `onAppear`), `camera-present` (tap → first frame), `scan` with events `ocr-done` / `resolve-done` / `verdict-rendered` / `enrich-done`, `save-beer` (tap → dismiss), `store-write` (per file, with byte count as metadata). `ScanLog` already records `latencyMs` per scan — split it into `deviceLatencyMs` and `enrichLatencyMs` so field data from both iPhones distinguishes the paths.

### Instruments (3 templates, run on the iPhone 14 Pro — the slower, no-Foundation-Models device)

1. **Time Profiler + os_signpost track** — the workhorse. Watch the `scan` interval shrink release-over-release; check no main-thread work between `ocr-done` and `verdict-rendered`.
2. **App Launch template** — verifies fix #10: store I/O must appear on background threads after the fix; first-frame time <1.5s cold.
3. **SwiftUI + Hangs/Animation Hitches template** — list scrolls and the verdict presentation animation; confirms fixes #11/#14/#15 removed main-thread stalls >8ms.

(Spot-check the CloudKit fixes once with the **Network** template: launch should show no photo-asset downloads.)

### Debug latency HUD

Behind `#if DEBUG` + a `UserDefaults` flag (`perfHUD`), overlay a 2-line monospaced label at top of `RootView` (`.allowsHitTesting(false)`):

- Line 1: last scan — `OCR 94ms · verdict 212ms · enrich 3.1s (net)` — fed by the same signpost events mirrored into a tiny `ObservableObject` (`PerfHUDModel`, `@Published var lastScan: ScanTiming?`).
- Line 2: rolling frame time from a `CADisplayLink` (red when >17ms) + last store-write duration/bytes.

This makes regressions visible on-device in the actual grocery aisle without a Mac attached, and since `ScanLog` already stamps device model/build, HUD-observed numbers can be cross-checked against logged `latencyMs` per device.

### Pass/fail gates (re-run after each phase)

- Airplane mode, cold launch, scan a can: verdict on screen **<1s** from shutter (Day 1 gate).
- Scan #1 vs scan #10 delta **<150ms** (warm-up gate).
- Time Profiler: zero main-thread `JSONEncoder`/`Data(contentsOf:)` samples during scan, save, or scroll (Week 1 gate).
- Seed 1,000 scans in `scans.json`: launch and per-tap timings within 10% of the 50-scan numbers (Later gate).

---

# Appendix: Confirmed Hotspot Ledger

- **[critical]** `SipCheck/Services/ScanningPipeline.swift:77` (tap-to-verdict) — Second serial network round-trip (getVerdictAndExplanation, Gemini then OpenAI fallback, 15s timeout each) whose verdict is ALWAYS discarded: CheckTabView.buildScan (CheckTabView.swift:396-428) overwrites it with the on-device TasteScorer verdict, and its explanation is used only when non-generic (CheckTabView.swift:438-444). The scan awaits this call before buildScan can run, so the instant on-device verdict is gated behind a network call that contributes at most flavor copy.
  - Delays: Tap Scan Label (and typed-name Check This Beer via scan(text:) at ScanningPipeline.swift:43) — verdict card render
  - Cost: 800ms-2.5s typical, up to 30s worst case (two providers x 15s timeout) added to every scan for a verdict value that is thrown away; distinct from the already-known serial-calls issue because this specific call's primary output is dead code on the critical path
  - Fix: Return from scan() as soon as beerInfo exists (or OCR text alone); compute the TasteScorer verdict and show the card immediately. Fire getVerdictAndExplanation as a detached enrichment task that patches currentScan.explanation via MainActor when/if it completes — it must never be awaited before the card renders. Also stop requesting a verdict at all (only explanation copy), since the verdict field is discarded.
- **[critical]** `SipCheck/Views/Tabs/CheckTabView.swift:339` (perceived) — runScan awaits the full ScanningPipeline (OCR + network extraction + network verdict) before buildScan() ever runs; the entirely on-device verdict machinery (TasteProfile.build, BeerResolver.resolve against BundledCatalog, TasteScorer.assess at lines 383-402) is computed only AFTER the pipeline returns, so the spinner stays up the whole time even though everything needed for a verdict is available in ~0.3s (OCR ~100ms + catalog lookup)
  - Delays: tap shutter / tap 'Check This Beer' → verdict appears (the core 1-second aisle moment)
  - Cost: 0.3s of real on-device work stretched to 4-60s perceived: the user sees only scanningView until every network stage completes or times out; on no signal the free verdict that already exists is withheld the full timeout chain
  - Fix: Restructure runScan for progressive disclosure: (1) run VisionOCRService + BeerResolver + TasteScorer immediately and set currentScan with the on-device verdict (isScanning=false) within ~0.3s; (2) kick the network extraction/explanation off as a separate child Task; (3) add a `isRefining: Bool`/`explanationSource` field to the scan state, show a small 'refining…' badge on VerdictCardView, and update explanation/style in place via updateScan when the network returns. Never let currentScan wait on ScanningPipeline.
- **[high]** `SipCheck/Services/ScanStore.swift:37` (io-data) — Unbounded growth: addScan persists every scan forever — including garbage OCR reads and 'Unknown Beer' results — with no cap or pruning anywhere (contrast ScanLog.swift:74 which caps at 200). Tombstones are also immortal: tombstone() (line 67-81) keeps deleted records in the file forever, and deleteAllScans (line 61) converts ALL scans to tombstones, so 'delete everything' makes the file zero bytes smaller and every future save still encodes all of them (saveScans encodes scans + tombstones, line 109).
  - Delays: Compounds every other hotspot: every future save, every app launch decode, and every CloudKit fullSync scales with lifetime scan count, not visible count. This is the first thing that falls over for the target user — a grocery-aisle scanner doing ~10 scans/week hits 500 records in a year
  - Cost: Growth driver, not a one-time cost: at 500 lifetime scans every tap-save is 250KB and launch sync merges 500 records; at 5,000 it's 2.5MB per save + 2.5MB decode at launch + 5,000 CKRecords fetched per launch. UI only ever shows recentScans (prefix(5), line 141) and wantToTryScans, yet 100% of history is encoded/decoded/synced every time.
  - Fix: Prune: cap visible scans (e.g. keep last 200, or 90 days) unless wantToTry/linkedJournalId is set; hard-delete tombstones after a sync horizon (e.g. 30 days past lastModifiedLocal — any device offline longer does a full re-merge anyway). Purge on load and after applyRemoteScans. Delete the corresponding CKRecords with a batch delete when tombstones age out.
- **[high]** `SipCheck/Views/Components/CameraView.swift:9` (tap-to-verdict) — A brand-new UIImagePickerController (full camera capture session) is created inside makeUIViewController every time the sheet is presented — CheckTabView.swift:66 presents it per tap, and resetScanState clears capturedImage so 'Scan Another' repeats the full cold start. There is no session pre-warm, no live DataScanner, and after the shutter the picker returns a full-res processed photo before the delegate fires.
  - Delays: Tap Scan Label — time until a live viewfinder appears (the <100ms perceived-response requirement), plus shutter-to-callback
  - Cost: 500-1000ms camera cold start to first viewfinder frame on iPhone 14 Pro, plus ~300-600ms shutter-to-didFinishPicking for 12MP photo processing; paid on every single scan including 'Scan Another'
  - Fix: Replace UIImagePickerController with the architecture the product spec already mandates: VisionKit DataScannerViewController (live point-and-read, no shutter, text arrives continuously) or a persistent AVCaptureSession owned by a session controller that is started when the Check tab appears and kept warm across scans. If the picker must stay short-term, pre-create it and configure a lower cameraCaptureMode resolution.
- **[high]** `SipCheck/Services/CloudKitSyncService.swift:57` (network-policy) — fullSync (called on every app launch from SipCheckApp.swift:207) runs three CKQuery fetches with no desiredKeys and no change tokens: every field of every record — including the photoAsset CKAsset on all Drink and JournalEntry records — is downloaded on every launch. materializePhotoAsset (line 182-195) then deletes and re-copies every photo file to disk even when unchanged. No CKFetchRecordZoneChangesOperation / delta sync.
  - Delays: app launch (background bandwidth/battery; also delays when remote edits become visible)
  - Cost: N photos x ~200-500KB re-downloaded per launch — 100 journal photos is ~30-50MB of cellular data every cold start, plus N file delete+copy operations; fetch time grows linearly with library size up to the 2000-record cap
  - Fix: Pass desiredKeys excluding photoAsset to records(matching:) and fetch assets lazily (on-demand when a photo view needs one that's missing locally, keyed by photoFileName existence). Better: move to a custom zone + CKFetchRecordZoneChangesOperation with a persisted change token so launch sync transfers only deltas. In materializePhotoAsset, skip the copy when the destination file already exists.
- **[high]** `SipCheck/Views/AddBeerView.swift:182` (perceived) — saveBeer() defers dismiss() until after `await drinkStore.savePhoto` (full-res 12MP camera image redraw to 1024px + JPEG encode in ImageCompressor.compress) and then performs addDrink + addEntry + updateScan — three synchronous full-file JSON encode+atomic-writes on the main actor — before line 229's dismiss()
  - Delays: tap Save in Add Beer sheet → sheet dismisses
  - Cost: 200-600ms photo compression (detached, but awaited) + 3× full-array JSON writes on main (10-50ms each at a few hundred records) before the sheet moves; Save button also has no disabled/in-progress state so it can be double-tapped, creating duplicate drinks/entries
  - Fix: Optimistic save: capture field values, call dismiss() synchronously in the button action, then run photo compression + store writes in the detached Task. Generate photoFileName up front ("\(drinkId).jpg") so the Drink/JournalEntry can be inserted immediately with the name while the JPEG lands in the background. Disable the Save button after first tap and fire a UINotificationFeedbackGenerator .success.
- **[high]** `SipCheck/Services/OpenAIService.swift:294` (network-policy) — request.timeoutInterval = 15 on URLSession.shared (same at GeminiService.swift:164). timeoutInterval is an IDLE timeout only; the shared session's timeoutIntervalForResource default is 7 days, so a trickling response can run far past 15s. No dedicated URLSessionConfiguration: waitsForConnectivity, allowsConstrainedNetworkAccess, multipath, and resource caps are all defaults.
  - Delays: every scan, Check Beer search, and label autofill — worst on the 1-bar grocery-store/basement signal the product is built for
  - Cost: 15s per stalled hop x up to 4 sequential hops = 60s worst-case spinner; unbounded on a slow-drip response; even the p50 on weak LTE is multi-second per hop
  - Fix: Create one shared URLSession with URLSessionConfiguration.ephemeral: timeoutIntervalForRequest = 4, timeoutIntervalForResource = 6, waitsForConnectivity = false; use it in both services. Wrap each call in a withTimeout/Task race so cancellation propagates. For enrichment (post-verdict) a total 5s budget across the whole chain is right — if it misses, the on-device verdict already shipped.
- **[high]** `SipCheck/Views/CheckBeerView.swift:311` (network-policy) — processImage runs THREE sequential network round trips before rendering anything: (1) ScanningPipeline.scan(image:) which internally does extract + a verdict call, then (2) the verdict/explanation from that scan is thrown away entirely (only beerInfo.name is read at line 312), then (3) a separate gpt-4o getRecommendation call (line 318) with a 20-drink history prompt. The verdict round trip inside the pipeline is 100% wasted here. searchBeer (line 281) similarly blocks a locally-known answer (drinkStore.findMatch, line 278) behind the gpt-4o call and shows an error instead of the local result on failure (line 296).
  - Delays: Check Beer sheet: snap photo or tap Search
  - Cost: 3 sequential round trips, gpt-4o being the slowest model in the app: 4-10s typical, ~90s worst with provider fallbacks (extract 2x15 + wasted verdict 2x15 + rec 15); search path hides an instant local 'You've tried this!' behind 1-15s of network
  - Fix: Render found/notFound from drinkStore.findMatch immediately; stream the AI recommendation into the card afterward (placeholder text until it lands, keep the card on network failure). For the image path, call only the extraction stage (add a pipeline entry point that skips getVerdictAndExplanation) and switch getRecommendation to gpt-4o-mini or Gemini Flash — the 2-3 sentence output doesn't need gpt-4o.
- **[medium]** `SipCheck/Services/VisionOCRService.swift:70` (launch) — First VNRecognizeTextRequest (.accurate, language correction) is performed cold — Vision's text-recognition ML models are loaded lazily on scan #1; handler.perform() is also a synchronous blocking call running on a Swift-concurrency cooperative-pool thread.
  - Delays: First tap of Scan Label after launch (photo -> verdict); every subsequent OCR also pins a cooperative thread for the recognition duration
  - Cost: 500-1500ms one-time model load added to scan #1, on top of 300-1000ms .accurate recognition itself — alone this can blow the <1s scan-to-verdict budget on the first, most important scan; nothing in the app ever warms Vision
  - Fix: At launch, after first frame, run a throwaway warmup in a detached background task: VNRecognizeTextRequest with .accurate on a tiny solid-color CGImage (and once when the Check tab appears, again cheaply). This pages the models in so scan #1 pays only recognition. Also wrap handler.perform in Task.detached / DispatchQueue.global(qos: .userInitiated) so the blocking Vision call doesn't occupy a cooperative-pool thread.
- **[medium]** `SipCheck/SipCheckApp.swift:50` (main-thread) — App.init constructs DrinkStore/ScanStore/JournalStore synchronously on the main thread before first frame. Each init does Data(contentsOf:) read, then an extra synchronous atomic backup WRITE (drinks_backup.json etc., DrinkStore.swift:133, JournalStore.swift:122, ScanStore.swift:124), then a full JSONDecoder decode with per-field decodeIfPresent — 3 reads + 3 writes + 3 decodes on main at launch.
  - Delays: App launch (cold start) — exactly the grocery-aisle moment; every ms here delays the first Scan Label tap.
  - Cost: 20-100ms at 200 records per store; scans.json's unbounded growth makes this creep — a 0.5MB scans.json alone adds ~30-60ms of main-thread decode plus a 0.5MB synchronous backup write at every launch.
  - Fix: Init stores with empty arrays, load+decode on a background task in init and publish to @Published on main when done (UI already handles empty state). Write the backup file on the background queue too — it doesn't need to happen before first frame.
- **[medium]** `SipCheck/Views/BeerListView.swift:176` (main-thread) — BeerRowView.body calls drinkStore.loadPhoto(named:) — a synchronous Data(contentsOf:) disk read + full-resolution UIImage(data:) decode of a 1024px JPEG (~100-300KB) on the main thread, inside body, for every row on NSCache miss — then scales it down to a 50x50 thumbnail.
  - Delays: Scrolling the All Beers list (and first render after tapping See All Beers) — each newly-appearing photo row blocks the render frame.
  - Cost: 5-20ms per uncached row (disk I/O + 1MP JPEG decode); flick-scrolling 200 beers with photos = repeated dropped frames (16.7ms budget) until the cache is warm; cache is purged on memory pressure so it recurs.
  - Fix: Load asynchronously per row (`.task` on the row, @State image), and decode a real thumbnail via ImageIO CGImageSourceCreateThumbnailAtIndex(maxPixelSize: 100) instead of full 1024px decode; keep NSCache keyed by fileName+size. Alternatively pre-warm thumbnails off main after store load.
- **[medium]** `SipCheck/Services/CloudKitSyncService.swift:115` (io-data) — fullSync uploads every local record missing from remote via individual save() calls in three for-loops (lines 115, 119, 123). Each save() goes through saveRecord (line 30): a fetch round-trip (fetchOrCreate, line 148) + a save round-trip = 2 sequential network calls per record, and the WriteQueue actor (lines 18-25) serializes ALL of them end-to-end. ScanStore.deleteAllScans → tombstone() (ScanStore.swift:72-79) similarly enqueues one save per record.
  - Delays: First launch on a new device (or after the cursor-truncation bug below, EVERY launch): the CK write queue is jammed for minutes, so a user's real edit made during that window waits behind hundreds of queued saves before reaching iCloud; 'Delete all scans' in Settings enqueues N serialized 2-round-trip saves
  - Cost: ~200-500ms per round trip → 2 trips/record serialized: 50 records ≈ 20-50s of background CK traffic; 500 records ≈ 3-8 minutes; 5,000 ≈ hours. Zero batching despite CKModifyRecordsOperation supporting 400 records per op.
  - Fix: Replace the per-record loops with CKModifyRecordsOperation batches (chunks of ~200-400 records, savePolicy: .allKeys since local is authoritative for new uploads — skipping fetchOrCreate entirely for records known missing from remote). Keep the WriteQueue only for individual user-edit saves, and use .ifServerRecordUnchanged + the existing serverRecordChanged retry there.
- **[medium]** `SipCheck/Views/Tabs/CheckTabView.swift:453` (perceived) — saveForLater() mutates the scan and calls scanStore.updateScan (synchronous whole-file JSON encode+write on main, ScanStore.swift:107-114) plus scheduleFollowUp, but VerdictCardView's 'Save for Later' button (VerdictCardView.swift:86-96) never changes appearance — no saved state, no haptic, no disable
  - Delays: tap 'Save for Later' on the verdict card
  - Cost: Work is ~5-30ms, but perceived response is infinite: zero visible acknowledgment, so users re-tap (each re-tap = another main-thread JSON write + CloudKit save + duplicate notification schedule) and leave unsure it saved
  - Fix: Optimistic UI: pass a `isSaved` state into VerdictCardView (or track locally), flip the button to a filled 'Saved ✓' with a checkmark immediately on tap and disable it; fire UIImpactFeedbackGenerator(.medium). Also update `currentScan` so state survives; persistence continues unchanged underneath.
- **[medium]** `SipCheck/Services/CloudKitSyncService.swift:214` (io-data) — populate(_:from: Drink) calls attachPhotoAsset unconditionally on every save, so ANY field change — rating tweak, note edit, even tombstoning a deleted drink — re-uploads the unchanged 100-300KB photo JPEG as a fresh CKAsset. Same for JournalEntry at line 303.
  - Delays: Every drink edit/save (rating change in BeerDetailView, AddBeerView save) triggers a full photo re-upload in the background; on cellular this competes with the scan pipeline's own network fallbacks
  - Cost: ~100-300KB upload per edit vs ~1KB of actual changed fields — 100-300x upload amplification. A 10-drink rating session re-uploads ~2-3MB of unchanged photos. Not on the tap-latency path (fire-and-forget) but it saturates the serialized WriteQueue, delaying all subsequent CK saves behind photo uploads.
  - Fix: Only set record["photoAsset"] when it actually changed: skip attachment if the fetched server record already has a photoAsset and drink.photoFileName is unchanged (the fetch-before-save at line 34 already gives you the server record to compare). Track a photoModifiedAt or compare file mtime; explicitly nil the field only when photoFileName transitions to nil.
- **[medium]** `SipCheck/Services/NotificationService.swift:59` (perceived) — scheduleFollowUp() calls requestAuthorization() — CheckTabView.finalizeScan (line 448) invokes this at the exact moment the verdict card appears, so on the user's first-ever scan the system notification-permission alert pops over the verdict
  - Delays: first scan's verdict reveal (the payoff moment) gets interrupted by a permission dialog
  - Cost: Verdict is visually blocked until the user answers the dialog (multi-second, attention-destroying at the worst possible moment); also lowers grant rate since there's no context
  - Fix: Remove requestAuthorization() from scheduleFollowUp; request it contextually on the first 'Save for Later' tap ("we'll remind you") or after the verdict card has been on screen a few seconds. Guard with getNotificationSettings so scheduling silently no-ops when undetermined.
- **[medium]** `SipCheck/Services/ScanningPipeline.swift:107` (network-policy) — extractBeerInfoFromText and getVerdictAndExplanation (line 128) each await Gemini to full completion/timeout before even starting the OpenAI fallback — a strictly sequential 2-provider chain, run twice per scan (extract at line 42, verdict at line 43 — two round trips that ask one model two questions that fit in one prompt). No NWPathMonitor gating anywhere: when offline or on degraded signal every hop is still attempted and can burn its full timeout. No caching: scanning the same beer twice (common — aisle, then checkout) repeats every round trip; ScanStore.findMatch and the scan history are never consulted.
  - Delays: every scan and text check (latency compounds under finding #1; remains the enrichment path after the fix)
  - Cost: 2x the necessary round trips per scan (extract + verdict could be one JSON response); +15s per dead provider on bad signal; repeat scans pay full price — a re-scan that could be 0ms costs 1-30s
  - Fix: Merge extract + verdict into a single prompt returning one JSON blob (halves round trips), or drop the network verdict entirely per the fire-and-forget policy and keep only extraction/enrichment. Gate all calls on NWPathMonitor.currentPath.status == .satisfied (skip straight to the stub when unsatisfied). Give Gemini a 3s budget then race/start OpenAI rather than serial 15s waits. Add a small persisted cache keyed by normalized beer name (and consult ScanStore.findMatch first) so a repeat scan is a cache hit.
- **[medium]** `SipCheck/Views/AddBeerView.swift:152` (network-policy) — processImageWithAI awaits the full ScanningPipeline.scan(image:), but only reads result.beerInfo (name/brand/style/abv, lines 154-165) — the pipeline's getVerdictAndExplanation network round trip (ScanningPipeline.swift:98) is completely unused here, yet the form's autofill spinner waits for it.
  - Delays: Add Beer: snap a label to autofill the form
  - Cost: one wasted network round trip per label scan: +0.5-2s typical, +30s worst (Gemini 15s timeout then OpenAI 15s) added to autofill for a result that is discarded
  - Fix: Add an extraction-only entry point on ScanningPipeline (OCR -> extractBeerInfoFromText, no verdict call) and use it here; better still, prefill instantly from OCR + BeerResolver.resolve (style/ABV from the bundled catalog) and let the network extraction refine fields asynchronously.
- **[medium]** `SipCheck/Services/CloudKitSyncService.swift:34` (network-policy) — saveRecord does fetchOrCreate (a full read round trip, line 148-154) before every save — 2 sequential round trips per record write — and all writes funnel through the serialized WriteQueue actor. fullSync's missing-record upload loop (lines 115-125) and bulk operations like deleteAllScans enqueue N such saves, executing 2N strictly sequential round trips; no CKModifyRecordsOperation batching anywhere. Every single addDrink/updateScan/tombstone also triggers an immediate individual save with no debounce.
  - Delays: background sync after Save/delete taps and after launch sync (doesn't block UI, but delays cross-device visibility and burns battery/radio)
  - Cost: 2 RTs x ~200-500ms each per record, serialized: first launch on a second device with 100 local records = ~200 sequential round trips = 1-3 minutes of continuous radio; deleteAllScans of 50 scans similar
  - Fix: Keep the fetched CKRecord (or its system-fields archive) cached per id so saves skip the pre-fetch and rely on the existing serverRecordChanged retry for conflicts; batch bulk uploads with one CKModifyRecordsOperation (savePolicy .changedKeys, ~200 records per op); debounce rapid successive saves of the same record (e.g. 2s coalescing window).
- **[low]** `SipCheck/Services/ScanStore.swift:109` (io-data) — saveScans() JSON-encodes EVERY scan plus every tombstone and writes the whole file atomically, synchronously on the caller's thread. Called from addScan (line 43) which runs inside finalizeScan on MainActor (CheckTabView.swift:447) at the exact moment the verdict card is presented, and from updateScan (line 52) on every 'Save for Later' tap (CheckTabView.swift:456).
  - Delays: Verdict card appearing after a scan; tapping 'Save for Later'; tapping 'Not going to try it' — each does a full-file rewrite on main
  - Cost: Scan records are ~400-500 bytes each (explanation strings dominate). 50 scans ≈ 25KB → <2ms, fine. 500 scans ≈ 250KB → ~5-15ms encode+atomic write on main per tap. 5,000 scans ≈ 2.5MB → ~60-200ms main-thread stall per mutation (Swift JSONEncoder is ~15-40MB/s for structs) — visibly janks the verdict presentation animation. O(n) write amplification: one 500-byte logical change costs a 2.5MB write.
  - Fix: Move persistence off main: debounce/coalesce saves onto a serial background queue (like ScanLog already does — queue.async + writeToDisk), snapshotting `scans + tombstones` on main and encoding/writing on the queue. Longer term, split per-record files or append-log format so a single add is O(1) not O(n). Same fix applies verbatim to DrinkStore.saveDrinks (DrinkStore.swift:115) and JournalStore.saveEntries (JournalStore.swift:105).
- **[low]** `SipCheck/Services/BeerResolver.swift:157` (launch) — BundledCatalog.shared is a lazy static: the 350KB / 2,410-entry catalog.json is read and decoded on first access, which happens inside buildScan (CheckTabView.swift:390) — a MainActor context — right after the pipeline returns, i.e. appended to scan #1's verdict latency on the main thread. The substring-fallback lookup (line 192) also re-normalizes all 2,410 names on every lookup.
  - Delays: First scan's verdict render (main-thread hitch while the spinner is up), plus 2-5ms per subsequent scan for the fuzzy pass
  - Cost: 30-100ms one-time main-thread decode + index build during scan #1; ~2-5ms of repeated string normalization per lookup thereafter
  - Fix: Warm the catalog at launch: in a detached background task after first frame, touch BundledCatalog.shared (Task.detached { _ = BundledCatalog.shared.lookup(name: "warmup") }) so decode happens off-main before the first scan. In init, precompute and store each entry's normalized name so lookup's substring pass does zero per-call normalization.
- **[low]** `SipCheck/Views/AddBeerView.swift:218` (main-thread) — saveBeer(): after awaiting photo compression, one MainActor.run block does drinkStore.addDrink + journalStore.addEntry + scanStore.updateScan — THREE sequential full-file JSON encodes + atomic writes (drinks.json, journal.json, scans.json) synchronously on the main thread, plus dismiss() in the same frame. Additionally line 185 awaits savePhoto (12MP UIGraphicsImageRenderer redraw to 1024px + JPEG encode, 50-200ms) BEFORE any of this, so dismiss is serialized behind the photo pipeline.
  - Delays: Tap Save in Add Beer sheet — sheet dismissal is delayed by photo compression + 3 store writes; the frame that dismisses also pays 3 encodes.
  - Cost: 15-50ms of main-thread JSON work at 200 beers/entries (grows linearly with notes), plus 50-200ms perceived delay from awaiting the photo save first — total 100-300ms before dismiss with a photo attached.
  - Fix: Dismiss immediately: insert the Drink/JournalEntry into the @Published arrays with a placeholder photoFileName strategy (or generate fileName up front — it's just "<uuid>.jpg" — and let the detached photo write race), and move each store's JSON encode+write to a background queue. The three stores should share one 'persist async, UI-array-first' write path.
- **[low]** `SipCheck/Views/Components/JournalEntryRow.swift:7` (main-thread) — formattedDate allocates and configures a new DateFormatter on every row render — DateFormatter init is one of Foundation's most expensive constructors (~0.5-1ms, locale/ICU setup).
  - Delays: Scrolling the Journal tab list and every keystroke in Journal search (each keystroke re-renders all visible rows).
  - Cost: 0.5-1ms per visible row per render; 10-15 visible rows per search keystroke ≈ 5-15ms/keystroke, and per-row hitches while fast-scrolling 200 entries in the LazyVStack.
  - Fix: static let formatter = DateFormatter() configured once (dateFormat "MMM d"), or use entry.dateLogged.formatted(.dateTime.month(.abbreviated).day()) — FormatStyle is cached internally.
- **[low]** `SipCheck/Services/BeerResolver.swift:139` (main-thread) — BundledCatalog.shared is a lazy static: the FIRST scan pays a synchronous 350KB catalog.json decode (2,410 entries) + normalized-index build inside buildScan (CheckTabView.swift:390). It runs on the scan Task (off main) but sits inside the scan-to-verdict critical path. Additionally lookup()'s fuzzy fallback (line 192) re-normalizes all 2,410 entry names (lowercased+trimmed string allocs) on every miss-y lookup instead of using precomputed normalized names.
  - Delays: First Scan Label / Check This Beer after launch — adds directly to the <1s scan-to-verdict target; every subsequent unresolved scan pays the O(n) re-normalization.
  - Cost: 30-80ms one-time decode+index on scan #1; ~2-10ms of redundant string normalization per fuzzy lookup thereafter (2,410 lowercase/trim allocations per miss).
  - Fix: Warm BundledCatalog.shared from a background task at app launch (Task.detached { _ = BundledCatalog.shared }). Store the normalized name alongside each Entry at init so lookup's substring pass does zero per-call normalization.
- **[low]** `SipCheck/Services/ScanStore.swift:84` (io-data) — applyRemoteScans is @MainActor and does the full dictionary merge of all local+remote records, filter, sort of the entire history, and then a synchronous full-file saveScans() — all on the main actor right after launch sync completes. applyRemoteDrinks (DrinkStore.swift:86) and applyRemoteEntries (JournalStore.swift:78) are identical, and RootView.performLaunchSync (SipCheckApp.swift:212-214) runs all three back-to-back.
  - Delays: A main-thread stall a few seconds after launch — exactly when the grocery-aisle user is tapping 'Scan Label'; the tap response and camera sheet presentation jank
  - Cost: Dominated by the 3 full-file encode+writes: 500 records/store ≈ 3×(5-15ms) ≈ 15-45ms main stall; 5,000 scans ≈ 60-200ms for the scans file alone, plus O(n log n) sort and full @Published array replacement (whole-list SwiftUI diff). Merge/sort themselves are cheap (<10ms at 5k); the sync file write on main is the cost.
  - Fix: Do merge + sort off-main (it's pure data: pass in snapshots, compute in a nonisolated/background context), hop to MainActor only to assign the two @Published arrays, and push the file write to the background save queue from hotspot 1. Skip the save entirely when the merge produced no changes (common case: nothing new remotely).
- **[low]** `SipCheck/Services/DrinkStore.swift:165` (io-data) — loadPhoto does synchronous Data(contentsOf:) + UIImage(data:) JPEG decode on the calling thread; it's called directly from SwiftUI view bodies (BeerListView.swift:176 per visible row, BeerDetailView.swift:24), so first-time loads run on main during scroll. NSCache makes repeat hits free, but the cache is cold at every launch.
  - Delays: First scroll through the beer list after launch — each photo row's first appearance blocks main for the read+decode
  - Cost: 100-300KB JPEG (1024px): ~2-6ms read+decode each on A16/A17. 3 photos: invisible. 50-photo list: ~5 rows/frame during a fast scroll ≈ 10-30ms per frame → dropped frames (16.7ms budget) through the whole first scroll. Bounded per-frame, so it never gets worse than jank, but it's guaranteed jank at 50+ photos.
  - Fix: Make row images async: load via a small async wrapper (Task on a background executor doing the read + UIImage(data:) + optional downsample to thumbnail size with ImageIO/UIGraphicsImageRenderer) publishing into the row's @State, keeping NSCache as-is. List rows only need ~60-80pt thumbnails — decode-at-target-size cuts both decode time and cache memory ~10x.
- **[low]** `SipCheck/Services/BeerResolver.swift:192` (tap-to-verdict) — Fuzzy fallback in BundledCatalog.lookup runs entries.first(where:) that calls BundledCatalog.normalize($0.name) — lowercasing, trimming, and allocating a fresh String for up to 2,410 entries on every lookup that misses the exact index (which is most real label-text lookups, since OCR blobs never exactly equal a catalog name). Runs on the MainActor via buildScan.
  - Delays: Every scan's verdict computation (buildScan → BeerResolver.resolve → catalog.lookup)
  - Cost: 2-8ms of main-thread string allocation per scan miss (2,410 lowercased/trimmed copies); small alone but recurring and entirely avoidable
  - Fix: Precompute the normalized name for every entry once in init (store [(normalized: String, index: Int)] alongside exactIndex) and compare against the cached strings in the fuzzy pass; combined with warming the catalog off-main this makes lookup sub-millisecond.
