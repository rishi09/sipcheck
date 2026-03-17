# SipCheck Implementation Plan
**Organized by User Journey | Hybrid Apple Vision Architecture**
**Last updated: March 10, 2026**

> Status note: this is a planning snapshot, not the current source of truth. Several items listed below have already landed in the app, including onboarding, stats, test launch arguments, and the initial hybrid scanning pipeline. Use `README.md` for current project state.

## Phases

| Phase | Focus | Goal |
|---|---|---|
| **Phase 1** | Build | Core features working reliably, fast scanning, tests passing |
| **Phase 2** | Polish UX | Onboarding, stats, photo display, App Store-ready UI |
| **Phase 3** | Product Positioning | App Store listing, screenshots, marketing, launch |

---

## Prerequisites (before Phase 1 sprints)

**Test foundation must land first.** See `testing-plan.md` Phase 1:
- `--mock-ai`, `--seed-data`, `--isolated-storage` launch arguments
- `BeerMatcherTests` + `DrinkStoreTests` (Layer A)
- `./scripts/run_tests.sh` passing
- Regression gate: all tests green before starting Sprint 1

---

## Architecture Overview: Hybrid Scanning Pipeline

**Current:** Camera → full image to GPT-4o Vision → 3-6 seconds, ~$0.003/scan
**Target:** Camera → Apple Vision OCR on-device (~100ms) → text to Gemini 2.0 Flash (~300ms) → **sub-1-second, ~$0.0001/scan**

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐     ┌──────────┐
│ Camera       │────▶│ Apple Vision OCR │────▶│ Text-only LLM   │────▶│ Parsed   │
│ Capture      │     │ (on-device)      │     │ (Gemini Flash)  │     │ BeerInfo │
│              │     │ ~100-200ms       │     │ ~300-500ms      │     │          │
└─────────────┘     └──────────────────┘     └─────────────────┘     └──────────┘
                            │                                              │
                            │ confidence < 0.5                             │
                            ▼                                              │
                    ┌──────────────────┐                                   │
                    │ Fallback: Full   │───────────────────────────────────▶│
                    │ Vision API       │                                    │
                    │ (GPT-4o/Gemini)  │                                    │
                    └──────────────────┘
```

---

## New Files to Create

| File | Purpose |
|---|---|
| `SipCheck/Services/VisionOCRService.swift` | Apple Vision `VNRecognizeTextRequest` wrapper |
| `SipCheck/Services/GeminiService.swift` | Gemini 2.0 Flash text-only API client |
| `SipCheck/Services/ScanningPipeline.swift` | Orchestrates OCR → LLM → fallback flow |
| `SipCheck/Services/ImageCompressor.swift` | Resize/compress images before API upload |
| `SipCheck/Views/StatsView.swift` | Beer stats/analytics dashboard |
| `SipCheck/Views/OnboardingView.swift` | First-launch onboarding flow |

## Files to Modify

| File | Changes |
|---|---|
| `Config.swift` | Add Gemini API key config |
| `Secrets.swift` | Add `geminiAPIKey` |
| `OpenAIService.swift` | Refactor to use `ScanningPipeline`, keep as fallback |
| `AddBeerView.swift` | Use new pipeline, save photos, show scan speed |
| `CheckBeerView.swift` | Use new pipeline |
| `Drink.swift` | Add `photoPath`, `abv`, `scanSource` fields |
| `DrinkStore.swift` | Photo save/load, export, stats queries |
| `HomeView.swift` | Add stats card, onboarding trigger |
| `BeerDetailView.swift` | Display saved photo |
| `BeerListView.swift` | Show photo thumbnails |
| `SipCheckApp.swift` | Add onboarding state check |
| `project.pbxproj` | Add new files to build |

---

## Journey 1: "I'm holding a beer — what is it?" (Scan & Log)

**Current state:** ~70% complete. Camera → GPT-4o vision → auto-fills name/brand/style. But slow (3-6s), no photo saved, no ABV extraction.

### Step 1.1: Create VisionOCRService.swift
```swift
// Core API: VNRecognizeTextRequest with .accurate recognition level
// Returns: (extractedText: String, confidence: Float)
// Key: Use .accurate for beer labels (stylized fonts)
// Handles: Multiple text observations, sorted by confidence
```
- Import `Vision` framework
- `func extractText(from image: UIImage) async -> (text: String, confidence: Float)`
- Use `VNRecognizeTextRequest` with `.accurate` recognition level
- Aggregate all recognized text observations
- Return combined text + average confidence score
- No network required — fully on-device

### Step 1.2: Create LLMProvider protocol + GeminiService.swift
```swift
// Protocol so we can swap providers based on real benchmarks
protocol LLMProvider {
    func extractBeerInfo(fromText labelText: String) async throws -> BeerInfo
    func getRecommendation(prompt: String) async throws -> String
}
// First implementation: Gemini 2.0 Flash (fastest/cheapest in research)
// Can swap to GPT-4.1-mini or GPT-4o-mini if Gemini underperforms in practice
```
- Create `LLMProvider` protocol
- Create `GeminiService: LLMProvider` as first implementation
- Add `geminiAPIKey` to `Config.swift` and `Secrets.swift`
- Conform existing `OpenAIService` to `LLMProvider` for fallback
- Timeout: 5 seconds (should complete in <1s)

### Step 1.3: Create ScanningPipeline.swift
```swift
// Orchestrator: OCR → text LLM → fallback to vision API
// Returns: BeerInfo + scanMetadata (latency, source, confidence)
```
- `func scan(image: UIImage) async throws -> ScanResult`
- Step 1: Run `VisionOCRService.extractText()` (~100ms)
- Step 2: If confidence ≥ 0.5 and text length > 10 chars:
  - Send text to `GeminiService.extractBeerInfo()` (~300ms)
- Step 3: If confidence < 0.5 or text too short:
  - Fall back to `OpenAIService.extractBeerInfo(from: image)` (full vision, 3-6s)
- Track scan latency and source in `ScanResult` metadata

### Step 1.4: Update AddBeerView.swift
- Replace `OpenAIService.shared.extractBeerInfo(from:)` with `ScanningPipeline.shared.scan()`
- Show scan speed indicator ("Scanned in 0.8s" vs current spinner)
- Add `@State private var scanLatency: TimeInterval?`
- Save captured photo (see Step 1.5)

### Step 1.5: Save photos with beer entries
- Add `photoFileName: String?` to `Drink` model
- In `DrinkStore`, add `func savePhoto(_ image: UIImage, for drinkId: UUID) -> String`
  - Save to `Documents/photos/{drinkId}.jpg` (compressed to ~200KB)
  - Return filename
- In `AddBeerView.saveBeer()`, save photo before creating Drink
- In `BeerDetailView`, display saved photo at top of form
- In `BeerListView.BeerRowView`, show photo thumbnail instead of placeholder icon

### Step 1.6: Add ABV extraction
- Add `abv: Double?` to `Drink` model
- Include ABV in both the text-only LLM prompt and GPT-4o vision prompt
- Display ABV in `BeerDetailView` and `BeerRowView`

### Step 1.7: Image compression utility
- Create `ImageCompressor.swift`
- `func compress(_ image: UIImage, maxDimension: CGFloat = 512, quality: CGFloat = 0.7) -> Data`
- Used for both photo storage and fallback vision API calls

---

## Journey 2: "Have I tried this before?" (Check Beer)

**Current state:** ~80% complete. Camera scan → match against history → AI recommendation. Works well.

### Step 2.1: Use ScanningPipeline in CheckBeerView
- Replace `OpenAIService.shared.extractBeerInfo(from:)` with `ScanningPipeline.shared.scan()`
- Show speed indicator

### Step 2.2: Improve matching confidence
- `BeerMatcher.findMatch()` currently uses basic string matching
- Add fuzzy matching: Levenshtein distance or `localizedStandardContains`
- Consider: if OCR extracts "Blue Moon Belgian White" but user logged "Blue Moon", still match

### Step 2.3: Show photo comparison
- When a match is found, show side-by-side: saved photo from history vs. current camera capture
- Helps user visually confirm it's the same beer

---

## Journey 3: "What should I try next?" (Recommendations)

**Current state:** ~60% complete. AI recommendations exist but use generic GPT-4o prompts, not deeply personalized.

### Step 3.1: Improve recommendation prompt
- Current: sends beer name + full drink history to GPT-4o
- Better: pre-compute taste profile summary (favorite styles, rating patterns, brands liked/disliked)
- Send compact taste profile instead of raw history (saves tokens + better results)

### Step 3.2: Add taste profile computation
- In `DrinkStore`, add computed property:
  ```swift
  var tasteProfile: TasteProfile {
      // Compute: top 3 styles (by thumbs-up count), disliked styles, brand preferences
  }
  ```
- Use this in recommendation prompts

### Step 3.3: Switch recommendation API to Gemini Flash
- Recommendations are text-only (no image) — perfect for cheap/fast Gemini Flash
- Move from GPT-4o ($2.50/MTok) to Gemini Flash ($0.10/MTok) for recommendations
- Keep same prompt structure, just change the API endpoint

---

## Journey 4: "Show me my beer history" (Journal/List)

**Current state:** ~85% complete. List view with search, filter by rating/style, detail view with edit/delete.

### Step 4.1: Stats dashboard
Create `StatsView.swift`:
- Total beers tried (count)
- Rating distribution (thumbs up/neutral/down bar chart)
- Top styles tried (sorted by frequency)
- Beers per month (simple bar chart, last 6 months)
- "Your profile": most-liked style, most-tried brand
- Use SwiftUI Charts framework (`import Charts`)

### Step 4.2: Add stats card to HomeView
- Show compact stats on home screen: "42 beers tried | 28 liked"
- Tap to navigate to full `StatsView`

### Step 4.3: Export data
- In `DrinkStore`, add `func exportJSON() -> Data` and `func exportCSV() -> String`
- Add "Export" button in settings/stats view
- Use `ShareLink` for iOS share sheet

### Step 4.4: Sort options in BeerListView
- Add sort by: date added (default), name, rating, style
- Add section grouping: by style, by rating, by month

---

## Journey 5: "First time opening the app" (Onboarding)

**Current state:** 0% complete. App launches straight to HomeView.

### Step 5.1: Create OnboardingView.swift
- 3-4 swipeable pages:
  1. "Scan any beer label" — show camera icon + animation
  2. "Track what you've tried" — show journal icon
  3. "Get AI recommendations" — show sparkles icon
  4. "Get started" — CTA button
- Store `hasCompletedOnboarding` in UserDefaults

### Step 5.2: Update SipCheckApp.swift
- Check `hasCompletedOnboarding` on launch
- Show `OnboardingView` if false, `HomeView` if true
- Pass `DrinkStore` as environment object to both

---

## Journey 6: "I want to find a specific beer in my list" (Search & Filter)

**Current state:** ~90% complete. Search by name/brand, filter by rating and style.

### Step 6.1: Add type filter
- `BeerListView` already has rating and style filters
- Add filter by `DrinkType` (regular, non-alcoholic, etc.)

### Step 6.2: Improve search
- Search across notes field too (currently only name + brand)
- Add recent searches (persist last 5 in UserDefaults)

---

## Journey 7: "I don't want to lose my data" (Backup & Sync)

**Current state:** 0% complete. Data is local JSON only.

### Step 7.1: iCloud backup (P1 — near-term)
- Use `NSUbiquitousKeyValueStore` for simple key-value sync
- Or: store `drinks.json` in iCloud Documents container
- Sync photos to iCloud (opt-in, warn about storage)
- Handle merge conflicts (last-write-wins for simplicity)

---

## Implementation Order (Sprint Plan)

### Phase 1: Build

**Regression gate:** All tests from testing-plan.md Phase 1 must pass before starting.

#### Sprint 1: Hybrid Scanning Pipeline (highest impact — speed)
1. `VisionOCRService.swift` — Apple Vision OCR
2. `LLMProvider` protocol + `GeminiService.swift` — provider-abstracted text LLM
3. `ScanningPipeline.swift` — orchestrator with fallback
4. `ImageCompressor.swift` — resize before API calls
5. Update `AddBeerView` + `CheckBeerView` to use pipeline
6. Add `geminiAPIKey` to Config/Secrets
7. **No model/schema changes yet** — same `Drink` struct

**Latency SLO:** 80% of scans complete in <1.5 seconds on WiFi.
**Measurement:** Log `scanLatency` and `scanSource` (ocr+text / vision-fallback) to console.

**Fallback UX spec:**
- OCR confidence ≥ 0.5 → text-only LLM path (fast, sub-1s)
- OCR confidence < 0.5 → show "Getting a closer look..." → full vision API (3-6s)
- Vision API fails → show "Couldn't read this label. Enter details manually." → manual form
- No network → OCR-only result with warning "Offline — details may be incomplete"

**Regression gate:** Run full test suite. Core smoke flows still pass.

#### Sprint 2: Model + Photo Enhancements
1. Add `photoFileName: String?` to `Drink` model
2. Add `abv: Double?` to `Drink` model
3. Photo save/load in `DrinkStore`
4. Update `AddBeerView` to save photos on scan
5. Update `BeerDetailView` + `BeerRowView` to show photos
6. Include ABV in extraction prompts

**Regression gate:** Existing tests pass. Add tests for new model fields.

#### Sprint 3: Recommendations + Taste Profile
1. Taste profile computation in `DrinkStore`
2. Improved recommendation prompts (compact profile, not raw history)
3. Switch recommendations to `LLMProvider` (Gemini Flash)

### Phase 2: Polish UX

#### Sprint 4: Stats + Onboarding
1. `StatsView.swift` with Charts (rating distribution, styles tried, beers/month)
2. Stats card on `HomeView`
3. `OnboardingView.swift` (3-4 swipeable pages)
4. Export JSON/CSV with `ShareLink`
5. Sort options + search improvements in `BeerListView`

#### Sprint 5: App Store Readiness
1. App icon + launch screen
2. Accessibility audit (VoiceOver, Dynamic Type)
3. Error states polish (empty states, network errors, graceful degradation)
4. Performance profiling (memory, battery impact of OCR)

### Phase 3: Product Positioning

#### Sprint 6: App Store Launch
1. App Store screenshots (use simulator + real device)
2. App Store description, keywords, category
3. Privacy policy (required for App Store)
4. TestFlight beta distribution
5. iCloud sync (if needed before launch)

#### Sprint 7: Growth
1. Landing page / website
2. Demo video for social (TikTok-style "scan moment")
3. Competitive positioning (from `research_output/` analysis)

---

## Xcode Project Integration Notes

Every new `.swift` file needs 3 additions to `project.pbxproj`:
1. `PBXBuildFile` entry (in Sources build phase)
2. `PBXFileReference` entry
3. `PBXGroup` entry (in appropriate folder group)

New framework imports needed:
- `Vision` (for VisionOCRService) — already available in iOS 17+
- `Charts` (for StatsView) — already available in iOS 16+
- No new CocoaPods/SPM dependencies needed

---

## API Keys Required

| Service | Key Name | Cost | Purpose |
|---|---|---|---|
| OpenAI (existing) | `openAIAPIKey` | ~$0.003/scan | Fallback vision API |
| Google AI Studio (new) | `geminiAPIKey` | ~$0.0001/scan | Primary text-only LLM |

Get Gemini key at: https://aistudio.google.com/apikey (free tier: 15 RPM, 1M tokens/day)

---

## Risk Mitigation

| Risk | Mitigation |
|---|---|
| OCR fails on stylized/artistic labels | Fallback to full vision API automatically |
| Gemini 2.0 Flash deprecated June 2026 | Plan migration to Gemini 2.5 Flash (nearly identical API) |
| Poor connectivity in stores/bars | OCR step works fully offline; show "offline mode" with OCR-only results |
| Photo storage fills device | Compress to ~200KB each; 1000 beers = ~200MB |
| iCloud sync conflicts | Last-write-wins; show conflict UI only if timestamps are within 1 minute |
