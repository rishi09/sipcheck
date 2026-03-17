# SipCheck Development Loop
**The actors, the loop, and the enforcement**

---

## The Actors

| Actor | Role | Tools |
|-------|------|-------|
| **Rishi** | Product owner. Decides what to build, reviews on device, approves visual direction. | iPhone, Xcode, eyes |
| **Claude Code** | Implementer. Writes code, runs tests, takes screenshots, iterates until green. | Edit, Bash, AXe, xcodebuild |
| **Manus** | Visual producer. Generates mockups, icons, marketing assets, illustrations. | Manus 1.6 Max |
| **Test Suite** | Quality gate. Must pass before any change is considered done. | run_tests.sh, e2e_test.sh |
| **Simulator** | Fast feedback. Build + screenshot + verify in seconds. | iPhone 17 Pro sim |
| **Physical Device** | Real feedback. Camera, performance, haptics, real-world feel. | Rishi's iPhone 16 via Xcode |

---

## The Loop

```
    ┌─────────────────────────────────────────────────┐
    │                                                 │
    ▼                                                 │
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌──────────┐
│  PLAN   │───▶│  BUILD  │───▶│  TEST   │───▶│  REVIEW  │
│         │    │         │    │         │    │          │
│ - Flows │    │ - Code  │    │ - Unit  │    │ - Screen │
│ - Design│    │ - Views │    │ - UI    │    │ - Device │
│ - Manus │    │ - Model │    │ - E2E   │    │ - Rishi  │
│   brief │    │ - Tests │    │ - AXe   │    │          │
└─────────┘    └─────────┘    └─────────┘    └──────────┘
                                                  │
                                          ┌───────┴───────┐
                                          │               │
                                        PASS            FAIL
                                          │               │
                                          ▼               │
                                      ┌──────┐            │
                                      │ SHIP │            │
                                      └──────┘            │
                                                          │
                                          ┌───────────────┘
                                          ▼
                                   Back to BUILD
                                   (max 3 auto-fix
                                    attempts, then
                                    ask Rishi)
```

---

## Phase 1: Plan

**Who:** Rishi + Claude Code
**Input:** Design direction, flows doc, Manus mockups
**Output:** Clear spec for what to build next

1. Pick next screen/flow from `user-flows-design-2026-03-16.md`
2. Reference Manus mockups for visual target
3. Identify what code changes are needed (new files, modified files, model changes)
4. Claude proposes approach, Rishi approves

**Artifacts:**
- `plans/user-flows-design-2026-03-16.md` (flows spec)
- `plans/design-direction-2026-03-16.md` (visual spec)
- Manus mockup PNGs (visual targets)

---

## Phase 2: Build

**Who:** Claude Code (autonomous)
**Input:** Approved plan + visual target
**Output:** Working code that compiles

1. Write/modify Swift files
2. Update `project.pbxproj` if adding new files
3. Build for simulator to verify compilation:
   ```bash
   xcodebuild -project SipCheck.xcodeproj -scheme SipCheck \
     -destination 'platform=iOS Simulator,id=48FF0EDE-5280-4C70-AB5C-F06C750443DB' \
     -configuration Debug build 2>&1 | tail -5
   ```
4. Fix any build errors immediately (max 3 attempts)

**Rules:**
- Don't move to Test if build fails
- Don't change unrelated code
- Don't remove existing accessibility identifiers

---

## Phase 3: Test

**Who:** Claude Code (autonomous)
**Input:** Compiling build
**Output:** All tests green + screenshots

### 3a: Automated Tests
```bash
# Unit + Integration tests (fast, ~30s)
./scripts/run_tests.sh --unit-only

# UI tests (slower, ~2min)
./scripts/run_tests.sh --ui-only
```

### 3b: Visual Verification (AXe)
```bash
SIMULATOR_UDID="48FF0EDE-5280-4C70-AB5C-F06C750443DB"
BUNDLE_ID="com.sipcheck.app"

# Install and launch with test data
xcrun simctl install $SIMULATOR_UDID \
  ~/Library/Developer/Xcode/DerivedData/SipCheck-*/Build/Products/Debug-iphonesimulator/SipCheck.app
xcrun simctl launch --terminate-running-process $SIMULATOR_UDID $BUNDLE_ID \
  --seed-data --mock-ai

# Wait for launch, take screenshot
sleep 2
axe screenshot --udid $SIMULATOR_UDID --output /tmp/sipcheck-verify.png
```

### 3c: E2E Flow Tests
```bash
./scripts/e2e_test.sh
```

### 3d: Compare to Target
- Claude reads the screenshot and compares to Manus mockup
- Flags visual discrepancies
- Iterates on code if layout/styling doesn't match

**Auto-fix rules:**
- If tests fail: read error, fix code, rebuild, retest (max 3 attempts)
- If screenshot doesn't match target: adjust styling, rebuild, re-screenshot
- After 3 failed attempts: stop and ask Rishi

---

## Phase 4: Review

**Who:** Rishi
**Input:** Screenshots + test results from Claude
**Output:** Approve or request changes

### Simulator Review
- Claude shows screenshot(s) of the new/changed screens
- Side-by-side with Manus mockup target
- Test results summary (X/Y passed)

### Device Review
- Rishi does Cmd+R in Xcode to push to iPhone
- Tests camera, haptics, real-world feel
- Provides feedback

### Feedback → Loop
- If approved: merge/commit, move to next screen
- If changes needed: back to Build with specific feedback

---

## Enforcement: The Quality Gates

### Gate 1: Build Compiles
No discussion until `xcodebuild build` succeeds.

### Gate 2: Unit Tests Pass
`./scripts/run_tests.sh --unit-only` must exit 0.

### Gate 3: UI Tests Pass
`./scripts/run_tests.sh --ui-only` must exit 0.

### Gate 4: E2E Flows Pass
`./scripts/e2e_test.sh` must exit 0.
(Update E2E script as flows change — add new flows, retire old ones)

### Gate 5: Visual Match
Screenshot must reasonably match the Manus mockup target.
Claude flags discrepancies. Rishi makes final call.

### Gate 6: Device Smoke
Rishi confirms it works on the physical iPhone.
Camera-dependent features can only be validated here.

**Gates 1-4 are automated and non-negotiable.**
**Gates 5-6 require human judgment.**

---

## What Changes from Before

The previous loop was: build on simulator → AXe screenshot → show user → iterate.

The new loop adds:

| New Element | Why |
|-------------|-----|
| **Manus mockups as visual targets** | We have a design direction now — not just "does it work" but "does it look right" |
| **Physical device testing** | Camera, real OCR, haptics, bar lighting |
| **3 auto-fix attempts** | Claude tries to fix failures before bothering Rishi |
| **Verdict card testing** | New hero component needs specific visual verification |
| **Tab bar navigation** | Major nav restructure — E2E script needs new flow definitions |
| **Star rating tests** | 1-5 stars replaces 3-tier — tests need updating |
| **Scan/Journal separation** | Two data models instead of one — new test coverage needed |

---

## Updating the Test Suite for the Redesign

As we rebuild screens, the test suite needs parallel updates:

### New Unit Tests Needed
- `ScanTests.swift` — Scan model CRUD, verdict enum
- `JournalEntryTests.swift` — JournalEntry model, star rating (1-5), migration from Drink
- `TasteProfileTests.swift` — Profile computation with personas, star-based preferences
- `VerdictTests.swift` — Verdict generation logic (try/skip/your call thresholds)

### Updated UI Tests
- Tab bar navigation (4 tabs)
- Check flow: camera → verdict card
- Journal flow: "+" → find beer → rate → save
- Profile flow: persona change, stats display
- Re-scan flow: scan already-logged beer → shows rating

### Updated E2E Script
- New accessibility IDs for tab bar, verdict cards, star rating, persona cards
- New flow definitions matching the redesigned screens
- Screenshot comparison checkpoints

### New Test Launch Args
- `--persona hop-head` — set persona without onboarding
- `--skip-onboarding` — jump straight to tab bar (already have `hasCompletedOnboarding`)

---

## Sprint Cadence

For each screen/flow in the redesign:

1. **Morning:** Pick the screen, review Manus mockup, Claude proposes code
2. **Build cycle:** Claude implements → builds → tests → screenshots (autonomous, ~15-30 min)
3. **Review:** Rishi looks at screenshots, pushes to device, gives feedback
4. **Iterate:** 1-2 rounds of refinement
5. **Done:** Tests green, visual match, device confirmed

Target: **1-2 screens per session.** The full 10-screen redesign = ~5-7 sessions.
