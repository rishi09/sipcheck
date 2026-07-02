# CLAUDE.md

## Project Overview
SipCheck is an iOS beer tracking app with AI-powered recommendations using SwiftUI, JSON persistence, and a hybrid scanning stack.

## Multi-Session Coordination (EVERY session: read before editing anything)
Multiple Claude sessions work on this repo in parallel. The repo is the coordination
channel — don't make the user shuttle context between chats.

**Rules:**
1. Before your first edit (and after any long gap): `git fetch origin main` and start
   from / rebase onto latest `origin/main`. Merge small, merge often.
2. Check the Active Tracks table below. Do NOT edit files reserved by another track.
   When you claim or finish an area, update this table in your own merge.
3. Shared findings live in `plans/reports/` — read `BUG_AUDIT.md` (57 verified
   findings with fix status — check it BEFORE fixing anything), `SPEED_PLAN.md`,
   `DESIGN_INSPIRATION.md`, and `E2E_FINDINGS.md` so you don't re-discover known
   bugs. Findings marked 🔵 in BUG_AUDIT.md are recommended pickups for the
   E2E/tactical track.
4. Any `claude/*` branch push auto-BUILDS (compile/sign gate only, doc/script changes excluded). Only merges to `main` (or a manual dispatch) UPLOAD to TestFlight — Apple caps uploads per app per day, so never trigger uploads for intermediate work.

**Active Tracks** (update when claiming/releasing):
| Track | Branch | Reserved files |
|---|---|---|
| Design modernization (2026-07-03) | `claude/review-project-status-5ihff` | ALL visual/styling work: `SipCheck/Views/DesignSystem.swift` and the visual layer of every file in `SipCheck/Views/**` (layout/colors/typography/components), plus `Assets.xcassets`. Implementing `plans/reports/DESIGN_INSPIRATION.md` top-8 + Liquid Glass adoption. Functional/logic fixes to views are still fair game for other tracks — coordinate if a fix requires layout changes. `ScanningPipeline.swift` released. |
| Simulator E2E tap-and-fix (2026-07-02) | `claude/ios-simulator-e2e-testing-t5mxgm` | Everything else — small fixes, merge to main as found. Merged so far: CloudKit test-mode crash fix, dark scheme, VerdictCardView (previousDrink banner + padding), NotificationService prompt-timing APIs, JournalEntryDetailView + tappable rows, tab-bar clearance, rewritten UI tests, CI simulator E2E workflows. CheckTabView edits were reverted per reservation — absorption list in `plans/reports/E2E_FINDINGS.md`. |

## Camera / Scan Feature — Requirements & Architecture (READ FIRST)
These are locked product constraints. Do not re-litigate them; build to them.

**The moment we serve:** user in a grocery aisle (spouse waiting) or at a restaurant (waiter approaching). They need a **fast, in-the-moment 👍/👎** on a beer. So:
- **Fast + free are hard requirements.** The default path is **on-device and $0**; the network is optional enrichment/fallback, never on the critical path. A verdict must appear even with no signal.
- **Three inputs:** a **menu** (text list), a **label/can** (graphic-heavy), or a **typed** name.
- **Do NOT assume a clean barcode.** Barcode is an opportunistic bonus if it happens to be in frame; the primary path is reading label/menu text or a typed name.
- **Cold-start:** a quick taste quiz seeds the taste library so scan #1 is personalized.
- **Menu result:** surface **one clear winner** ("order this"), tap for runner-up.

**Menu vs. label are different problems (important):**
- A **menu is text** — "Two Hearted — IPA — 7.0%" is printed. OCR reads style/ABV directly.
- A **label/can is a graphic** — stylized logo dominates. OCR reliably gets **brewery + beer name + (often) the style**, but **rarely the ABV**. So the verdict must work **from style alone** (ABV is only a bonus modifier), and a made-up brew name ("Watt Strike") tells you nothing by itself.

**The resolver = fast fusion (mix signals, get an answer in the moment):**
Recognized name/text → resolve to `{style, abv}` by fusing, in order, whatever is fastest and available:
1. **Style/ABV printed on the label/menu** → use directly.
2. **Bundled offline catalog** (`plans/prototypes/data/catalog.json`, 2,410 beers → brewery/style/ABV) via fuzzy name match (`BeerMatcher`). Instant, offline, free — handles the common case.
3. **On-device LLM knowledge** (Apple Foundation Models) — knows popular beers; free/offline.
4. **Online top-up / vision-API fallback** — only for the long tail or when the above miss.
Show the verdict from whatever we have *now*; refine asynchronously. Never block on the network.

**On-device stack:** Apple Vision OCR (`VisionOCRService`) + VisionKit `DataScannerViewController` (live "point-and-read", no shutter) + Apple **Foundation Models** (on-device LLM, iOS 26) for the free verdict. See `plans/camera-feature-research-2026-06-30.md` and `plans/prototypes/RESULTS.md`.

**Phase-1 code (built, pure, standalone):** `SipCheck/Services/TasteScorer.swift` (instant verdict from taste library), `SipCheck/Services/MenuParser.swift` (menu → single winner), `SipCheck/Services/BeerResolver.swift` (the fusion above). Device-only spike (live DataScanner + Foundation Models) is the remaining unproven part.

**Test devices & capability (for triangulating field notes):**
- **iPhone 15 Pro** (A17 Pro) — Apple-Intelligence capable → **Foundation Models available** (full on-device AI verdict).
- **iPhone 14 Pro** (A16) — **NOT** Apple-Intelligence capable → **no Foundation Models**; falls back to the heuristic `TasteScorer` verdict. Same beer may get different verdict *wording/quality* here vs the 15 Pro — this is expected, not a bug.
- User drives Claude Code from the Claude iOS app (iPhone 14 Pro) or a MacBook Pro. Data syncs across devices via CloudKit (last-write-wins), so taste history is shared.
- `ScanLog` stamps each event with device model + iOS + build + whether Foundation Models is available, so per-device behavior is legible.

**Deferred (revisit after real-scan testing):** the catalog is text-only by design — no label images. Skip both UI thumbnails and Vivino-style **visual label matching** for now; only build them if real scans show the text-recognition path misses too often. Open image sources are cataloged in `plans/prototypes/data/IMAGE_LIBRARIES.md` if/when we return.

## Build Commands
```bash
# Build for simulator
xcodebuild -project SipCheck.xcodeproj -scheme SipCheck -destination 'platform=iOS Simulator,name=iPhone 16e' -configuration Debug build

# Install on simulator
xcrun simctl install "iPhone 16e" ~/Library/Developer/Xcode/DerivedData/SipCheck-*/Build/Products/Debug-iphonesimulator/SipCheck.app

# Launch on simulator
xcrun simctl launch "iPhone 16e" com.rishishah.sipcheck
```

## Architecture Decisions
- **SwiftUI + ObservableObject** - No @Observable macro (sandbox build issues)
- **JSON file persistence** - No SwiftData (macro sandbox issues)
- **PreviewProvider** - No #Preview macro (sandbox build issues)
- **iOS 17+ target**

## Key Files
- `SipCheck/Config.swift` - Loads API key from Secrets
- `SipCheck/Secrets.swift` - **GITIGNORED** - Contains actual API key
- `SipCheck/Services/DrinkStore.swift` - Data persistence layer
- `SipCheck/Services/ScanningPipeline.swift` - OCR/text/fallback scan orchestration
- `SipCheck/Services/OpenAIService.swift` - Vision fallback + recommendations
- `SipCheck/Services/GeminiService.swift` - Fast text extraction provider

## Conventions
- Use `@EnvironmentObject` for DrinkStore, not `@Environment`
- Use `PreviewProvider` structs, not `#Preview` macro
- Store all drink data in `Documents/drinks.json`
- Keep API keys in `Secrets.swift` (never commit)

## Don't Do
- Don't use Swift macros (@Observable, @Model, #Preview)
- Don't commit Secrets.swift
- Don't hardcode API keys in Config.swift
- Don't use SwiftData

## Testing
- Simulator: iPhone 17 Pro (primary), iPhone 16e (fallback)
- Physical device: Rishi's iPhone 16 (UDID: 00008140-000D74323E07001C, CoreDevice: 9D507846-A478-5220-B11A-B52B061B6E1C)
- **Device builds:** Use Xcode Cmd+R with iPhone selected as destination (CLI xcodebuild has device preparation timing issues)
- Camera features require physical device
- Sample data can be injected via drinks.json in app container
- Development team: YG7C25J24J (rishi09@gmail.com)

### Simulator Commands
```bash
# Simulator UDID (iPhone 17 Pro)
SIMULATOR_UDID="C3A2161C-2C4B-47A0-91F4-E4862B313365"

# Screenshot the running app
xcrun simctl io $SIMULATOR_UDID screenshot /tmp/sipcheck-screen.png

# Stream app logs
xcrun simctl spawn $SIMULATOR_UDID log stream --predicate 'subsystem=="com.rishishah.sipcheck"'

# Build, install, launch (one-liner)
xcodebuild -project SipCheck.xcodeproj -scheme SipCheck -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" build && \
xcrun simctl install $SIMULATOR_UDID ~/Library/Developer/Xcode/DerivedData/SipCheck-*/Build/Products/Debug-iphonesimulator/SipCheck.app && \
xcrun simctl launch --terminate-running-process $SIMULATOR_UDID com.rishishah.sipcheck
```

### Physical Device
```bash
# Device: Rishi's iPhone 16 (UDID: 00008140-000D74323E07001C)
# Preferred method: Xcode Cmd+R with iPhone selected as destination
# CLI alternative (if device is already prepared):
xcrun devicectl device install app --device 9D507846-A478-5220-B11A-B52B061B6E1C path/to/SipCheck.app
xcrun devicectl device process launch --terminate-existing --device 9D507846-A478-5220-B11A-B52B061B6E1C com.rishishah.sipcheck
```

### CI Simulator E2E (no Mac needed — works from any session, incl. Linux/cloud)
Two lanes, both on GitHub Actions macOS runners:

**Scripted (regression net):** `.github/workflows/e2e-simulator.yml` runs the
XCUITest flows on every code push and force-pushes step screenshots + results to
the `e2e-artifacts` branch (single commit, latest run only):
```bash
git fetch origin e2e-artifacts
git show origin/e2e-artifacts:SUMMARY.md          # pass/fail + screenshot list
git show origin/e2e-artifacts:screenshots/<name>  # actual sim screenshots
```

**Interactive (drive the app like a user):** `.github/workflows/e2e-drive.yml` +
`scripts/ci_bridge.py` — a git-based remote control. The runner posts
`screen.png` + AXe accessibility dump to `e2e-bridge-state`; you push command
batches to `e2e-bridge-cmd`; ~30s per interaction, sessions up to ~45 min.
- Start a session: edit `.drive/request.json` on a `claude/**` branch and push
  (or dispatch "E2E Drive" from the Actions tab).
- Send a command (must echo the current `seq` from `meta.json`):
  `{"seq": N, "actions": [{"do":"tap","label":"Journal"}, {"do":"type","text":"..."},
  {"do":"swipe","x1":200,"y1":500,"x2":200,"y2":150}, {"do":"launch","args":[...]},
  {"do":"end"}]}` → single-commit force-push `cmd.json` to `e2e-bridge-cmd`.
- Screen is 375×667pt; the floating tab bar occupies y≈584-646 — keep gesture
  start points above y≈560 or you'll hit it.
- Sessions launch with `--mock-ai --seed-data --isolated-storage` by default
  (hermetic: no network, no CloudKit, seeded journal).

### Automated UI Testing (XcodeBuildMCP + AXe)
```bash
# Install XcodeBuildMCP (MCP server for Xcode builds + simulator control)
claude mcp add -s user XcodeBuildMCP npx xcodebuildmcp@latest

# Install AXe (CLI for simulator UI interaction via accessibility)
brew tap cameroncooke/axe && brew install axe

# AXe usage examples:
axe tap --id "Add Beer" --udid $SIMULATOR_UDID      # Tap by accessibility ID
axe type "Hazy Little Thing" --udid $SIMULATOR_UDID  # Type text
axe screenshot --udid $SIMULATOR_UDID                # Take screenshot
```

## Common Tasks

### Add a new view
1. Create Swift file in `SipCheck/Views/`
2. Use `@EnvironmentObject private var drinkStore: DrinkStore`
3. Add `PreviewProvider` struct (not #Preview)
4. Add file to Xcode project (PBXBuildFile, PBXFileReference, Sources build phase)

### Add a new model field
1. Update `Drink.swift` (add property + init)
2. Ensure Codable conformance still works
3. Update relevant views

## Current Status
- Build: ✅ Passing
- Core flows: ✅ Implemented in working tree
- Tests: ✅ Unit, integration, and UI targets present
- Pending: physical-device validation, real-image scan evaluation, app icon, launch screen polish
