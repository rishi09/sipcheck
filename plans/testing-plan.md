# SipCheck Test Plan
**Layered Testing Strategy | Deterministic + Automation-Ready**
**Last updated: March 10, 2026**

> Status note: this document mixes active guidance with planned test coverage from before the current test suite landed. Some items below are already implemented in `SipCheckApp`, `SipCheckTests`, `SipCheckUITests`, and `scripts/run_tests.sh`.

---

## Philosophy

Prevent core journeys from breaking while iterating on UX and scanning. Three principles:

1. **Layered tests** — unit tests catch logic bugs fast, integration tests catch wiring bugs, UI tests catch flow breakage
2. **Deterministic by default** — no network calls in tests, no flakes, no API costs
3. **Design for automation** — parseable output and stable entrypoints from day one, even before building the autonomous fix loop

---

## Core Smoke Suite (Must-Pass Flows)

These are the non-negotiable flows that must pass before any merge to main:

1. Add beer manually
2. Check beer by text (found path)
3. Check beer by text (not-found path + add)
4. Edit beer
5. Delete beer
6. Search/filter list
7. Relaunch app and confirm data persists
8. *(When ready)* Check beer by photo with mocked scan output

---

## Layered Test Stack

### Layer A — Unit Tests (fast, run every change)

**Target files:**

`BeerMatcherTests.swift`
```
testExactMatch()           — "Blue Moon" matches "Blue Moon"
testCaseInsensitive()      — "blue moon" matches "Blue Moon"
testPartialMatch()         — "Blue" matches "Blue Moon Belgian White"
testContainsMatch()        — "Sierra" matches "Sierra Nevada Pale Ale"
testNoMatch()              — "Guinness" doesn't match "Blue Moon"
testEmptyHistory()         — returns nil for any query
testLevenshteinThreshold() — "Siera Nevada" (typo) still matches
```

`DrinkStoreTests.swift` (isolated temp directory, no real Documents/)
```
testAddDrink()             — adds drink, verifies in array + persisted to file
testDeleteDrink()          — deletes, verifies removed from array + file
testUpdateDrink()          — updates fields, verifies persisted
testDeleteDrinksAtOffsets() — swipe-to-delete with filtered list
testFindMatchExact()       — delegates to BeerMatcher correctly
testRecentDrinks()         — returns last 3, ordered by date
testLoadFromCorruptFile()  — gracefully starts with empty array
testExportJSON()           — export matches stored data
testExportCSV()            — CSV format correct, handles commas in notes
```

`ScanningPipelineTests.swift` (mock services, no network)
```
testOCRHighConfidence()        — confidence ≥ 0.5, uses text-only LLM path
testOCRLowConfidence()         — confidence < 0.5, falls back to vision API
testOCRShortText()             — text < 10 chars, falls back to vision API
testGeminiParsingValidJSON()   — valid label text → BeerInfo with all fields
testGeminiParsingPartialJSON() — partial text → BeerInfo with nulls
testFallbackOnGeminiError()    — Gemini fails → falls back to vision API
testEndToEndWithMocks()        — full pipeline with mock OCR + mock LLM
```

### Layer B — Integration Tests (moderate speed)

**Purpose:** Verify real wiring between components, still no live network.

`StoreIntegrationTests.swift` (real file I/O, temp directory)
```
testAddThenFind()          — add drink via store, find via matcher
testPersistAcrossInstances() — create store, add drink, create new store instance, verify loaded
testConcurrentWrites()     — multiple rapid adds don't corrupt file
```

`PipelineIntegrationTests.swift` (real VisionOCR, mock network)
```
testRealOCRWithClearLabel()    — feed test image to real VNRecognizeTextRequest
testRealOCRWithStylizedLabel() — verify text extraction quality
testPipelineWithMockLLM()      — real OCR → mock Gemini → verify result
```

### Layer C — UI Smoke Tests (XCUITest, slow, run before merge)

**Purpose:** End-to-end tap-through of core flows in simulator with deterministic test mode (see below).

```
testAddBeerManually()       — tap Add Beer → fill form → save → verify in list
testCheckBeerFound()        — add beer, then check → verify "You've tried this!"
testCheckBeerNotFound()     — check unknown beer → verify "Haven't tried yet" → add
testEditBeer()              — tap beer → edit → save → verify changes
testDeleteBeer()            — tap beer → edit → delete → confirm → verify removed
testFilterByRating()        — filter list by thumbs up → verify filtered results
testDataPersistsAfterRelaunch() — add beer → terminate → relaunch → verify still there
testScanWithMockResponse()  — (post-pipeline) trigger scan → mock returns data → verify populated
```

---

## Deterministic Test Modes

**This is the most important section.** Without deterministic modes, tests will flake and autonomous tools will fail.

### App-side launch arguments

Add to `SipCheckApp.swift`:

```swift
init() {
    // Check for test mode launch arguments
    if ProcessInfo.processInfo.arguments.contains("--mock-ai") {
        OpenAIService.useMockResponses = true  // Fixed JSON, no network
    }
    if ProcessInfo.processInfo.arguments.contains("--seed-data") {
        DrinkStore.useSeedData = true  // Load known test drinks on launch
    }
    if ProcessInfo.processInfo.arguments.contains("--isolated-storage") {
        DrinkStore.storageDirectory = tempTestDirectory  // Separate JSON file
    }
}
```

### Mock AI mode (`--mock-ai`)

All AI service calls return fixed responses:
- `extractBeerInfo()` → `BeerInfo(name: "Mock IPA", brand: "Mock Brewery", style: .ipa)`
- `getRecommendation()` → `"Based on your preferences, this looks like a great choice!"`
- No network calls, instant response, zero cost

### Seed data mode (`--seed-data`)

Loads 3 known drinks on launch:
- Sierra Nevada Pale Ale (Pale Ale, liked)
- Guinness Draught (Stout, liked)
- Bud Light (Light Lager, disliked)

### Isolated storage mode (`--isolated-storage`)

Tests use a separate JSON file path so they never corrupt real user data. Each test run starts with a clean state.

### XCUITest usage

```swift
class SipCheckUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        app.launchArguments = ["--mock-ai", "--seed-data", "--isolated-storage"]
        app.launch()
    }
}
```

---

## Single Test Command

```bash
#!/bin/bash
# scripts/run_tests.sh — Canonical test entrypoint
# Used by humans, Claude Code, and CI

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIMULATOR="platform=iOS Simulator,name=iPhone 16e"
RESULT_BUNDLE="$PROJECT_DIR/build/test-results.xcresult"

# Clean previous results
rm -rf "$RESULT_BUNDLE"

echo "=== Running all tests ==="
xcodebuild test \
  -project "$PROJECT_DIR/SipCheck.xcodeproj" \
  -scheme SipCheck \
  -destination "$SIMULATOR" \
  -resultBundlePath "$RESULT_BUNDLE" \
  2>&1 | tee "$PROJECT_DIR/build/test-output.log"

EXIT_CODE=${PIPESTATUS[0]}

echo ""
if [ $EXIT_CODE -eq 0 ]; then
  echo "=== ALL TESTS PASSED ==="
else
  echo "=== TESTS FAILED (exit code: $EXIT_CODE) ==="
  echo "Results: $RESULT_BUNDLE"
  echo "Log: $PROJECT_DIR/build/test-output.log"
fi

exit $EXIT_CODE
```

**Key properties:**
- Returns non-zero on failure (required for CI and autonomous tools)
- Writes `.xcresult` bundle to predictable path (parseable later)
- Tees output to log file (greppable now, parseable later)
- Fixed simulator target (deterministic)

---

## Parseable Output (Design for Automation)

Don't build a full `.xcresult` parser now, but structure output so automation is easy to add later.

### Now (grep-level)

```bash
# Quick failure extraction from test log
grep -E "Test Case.*failed|error:" build/test-output.log

# Count pass/fail
grep -c "Test Case.*passed" build/test-output.log
grep -c "Test Case.*failed" build/test-output.log
```

### Later (when you have 50+ tests)

Build a proper parser that extracts from `.xcresult`:
- Failing test names
- Error messages with file/line
- UI screenshot artifacts (XCUITest attaches these automatically)
- Duration per test (for spotting slow tests)

The `.xcresult` bundle is already being written — you're just deferring the parser.

---

## AXe as Development Tool

AXe and screenshots are **not** part of the test suite. They're a rapid iteration tool during development.

### When to use AXe

- Building a new view and want to quickly verify layout
- Debugging a UI bug — take screenshot, have Claude analyze it
- Manual smoke check before pushing a PR
- Prototyping a test flow before writing the XCUITest version

### Simulator config (for AXe/manual testing)

```bash
SIMULATOR_UDID="48FF0EDE-5280-4C70-AB5C-F06C750443DB"  # iPhone 17 Pro
BUNDLE_ID="com.sipcheck.app"
```

### Quick manual smoke check

```bash
# Build + install + launch
xcodebuild -project SipCheck.xcodeproj -scheme SipCheck \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" build && \
xcrun simctl install $SIMULATOR_UDID \
  ~/Library/Developer/Xcode/DerivedData/SipCheck-*/Build/Products/Debug-iphonesimulator/SipCheck.app && \
xcrun simctl launch --terminate-running-process $SIMULATOR_UDID $BUNDLE_ID

# Quick screenshot
sleep 2
axe screenshot --udid $SIMULATOR_UDID --output /tmp/sipcheck-screen.png
```

### Accessibility IDs (needed for both AXe and XCUITest)

```swift
// HomeView.swift
Button("Add Beer") { ... }
    .accessibilityIdentifier("addBeer")

Button("Check Beer") { ... }
    .accessibilityIdentifier("checkBeer")

// AddBeerView.swift
TextField("Beer Name", text: $name)
    .accessibilityIdentifier("beerName")

Button("Save") { saveBeer() }
    .accessibilityIdentifier("saveBeer")

// CheckBeerView.swift
TextField("Search by name...", text: $searchText)
    .accessibilityIdentifier("searchField")

Button("Search") { searchBeer() }
    .accessibilityIdentifier("searchButton")

// RatingPicker.swift
Button { rating = ratingOption } label: { ... }
    .accessibilityIdentifier("rating_\(ratingOption.rawValue)")

// BeerRowView.swift
NavigationLink { ... } label: { BeerRowView(drink: drink) }
    .accessibilityIdentifier("beer_\(drink.id.uuidString)")
```

---

## Safety Guardrails

- Tests only modify source/test files — never secrets, config, or user data
- Max 3 autonomous fix attempts per failure before escalating to human
- All test changes committed to feature branches only
- No auto-merge to main — human review required
- Isolated storage mode prevents test data from leaking into production

---

## Operational Cadence

### Every change batch
- Run `./scripts/run_tests.sh` (Layer A + B, ~30 seconds)
- Quick 5-min manual in-hand check if touching UI

### Before merging to main
- Run full suite including Layer C UI tests
- Verify on simulator

### During big UX push
- Run smoke suite frequently, keep PRs small
- Use AXe screenshots for rapid visual verification between changes

---

## Implementation Sequence

### Phase 1: Foundation (do first)
1. Add `--mock-ai`, `--seed-data`, `--isolated-storage` launch arguments to app
2. Create `SipCheckTests` target in Xcode
3. Write `BeerMatcherTests.swift` (~7 tests)
4. Write `DrinkStoreTests.swift` (~9 tests, using isolated temp directory)
5. Create `scripts/run_tests.sh`
6. Verify: `./scripts/run_tests.sh` passes with non-zero on failure

### Phase 2: UI Tests
1. Create `SipCheckUITests` target in Xcode
2. Add accessibility identifiers to all views
3. Write XCUITests for 8 core smoke flows
4. All tests use `--mock-ai --seed-data --isolated-storage` launch arguments
5. Verify: full suite runs deterministically, no flakes

### Phase 3: Pipeline Tests (after hybrid scanning is built)
1. Write `ScanningPipelineTests.swift` with mock services
2. Write `PipelineIntegrationTests.swift` with real OCR + mock network
3. Add scan flow to UI smoke tests with mock response

### Ongoing: Development Velocity
- Use AXe/screenshots for rapid iteration during development
- Not part of CI — personal dev tool only

---

## Success Criteria

You know this test plan is working when:

- Core smoke suite fails fast on real regressions
- Flake rate is near zero (deterministic modes)
- `./scripts/run_tests.sh` is the single source of truth
- UX iterations stop causing surprise breakage
- Claude Code / Codex can run tests, read failures, and fix a subset of bugs without manual debugging

---

## Test Image Assets

Available at `/tmp/beer-label-photos/` for manual testing and pipeline integration tests:
- 16 Burst photos (CC0) — general beer can/bottle photos
- 22 Beer-Label-Classification images — real-world bottle labels

For the hybrid pipeline, test with:
1. **Clear printed labels** — should work with OCR + text LLM
2. **Stylized/artistic labels** — may need fallback to vision API
3. **Draft pours with no label** — should fallback gracefully
4. **Non-beer items** — should return graceful "not a beer" response
