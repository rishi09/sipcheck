# Simulator E2E Findings (verified by driving the app)

**Track:** Simulator E2E tap-and-fix (`claude/ios-simulator-e2e-testing-t5mxgm`), 2026-07-02.
**Method:** app driven remotely on a CI simulator (screenshot → decide → tap loop, see
`.github/workflows/e2e-drive.yml` + `scripts/ci_bridge.py`); every finding below was
observed on-screen, not inferred from code.

## Fixed and merged

| ID | Finding | Fix | Files |
|---|---|---|---|
| F1 | **App crashed instantly at launch** in any build without the iCloud entitlement (incl. all unsigned CI builds): `CKContainer(identifier:)` raises an uncatchable NSException the moment `CloudKitSyncService.shared` is touched by RootView's launch sync. Mock/test mode also fired real CloudKit calls on every store write. | No CKContainer created and all sync entry points no-op under `--isolated-storage`/`--disable-cloudkit`; CI keeps entitlements (dropped `CODE_SIGNING_ALLOWED=NO`). | `CloudKitSyncService.swift`, workflows |
| F4 | System sheets rendered light inside the dark-only design (white flash; see also DESIGN_INSPIRATION §4 for the structural token fix). | Stopgap: `preferredColorScheme(.dark)` app-wide. | `SipCheckApp.swift` |
| F5 | Notification permission dialog fired **on top of the user's first verdict** (= SPEED_PLAN fix #9). | `scheduleFollowUp` no longer requests authorization; new `scheduleFollowUpIfAuthorized` + `requestAuthorizationAndScheduleFollowUp` APIs ready for call sites. **Call-site wiring is handed off — see below.** | `NotificationService.swift` |
| F6 | Verdict card's Save for Later / Scan Another buried under the floating tab bar. | Bottom clearance 40→110. | `VerdictCardView.swift` |
| F8 | Scan verdict ignored the user's own history (BeerMatcher orphaned by the tab redesign) — matches DESIGN_INSPIRATION #6. | `VerdictCardView` gained `previousDrink: Drink?` and renders a "You've had this one — you rated it X" banner. **Call-site wiring handed off — see below.** | `VerdictCardView.swift` |
| F10 | Journal rows weren't tappable: no way to view, edit, or delete a logged beer anywhere in the app. | New `JournalEntryDetailView` sheet (editable stars/notes, delete w/ confirmation) wired to rows. | `JournalEntryDetailView.swift`, `JournalTabView.swift` |
| F11 | Journal list and Profile Recent Scans scrolled under the tab bar ("SKIP IT" clipped to "KIP IT"). | Bottom clearance in both tabs. | `JournalTabView.swift`, `ProfileTabView.swift` |
| F2 | UI test suite targeted the pre-redesign home screen (`addBeer`, `checkBeer`, `rating_like`) — could never pass against the shipping UI. | Suite rewritten against the real 3-tab flows; deliberately avoids asserting scan-phase/Save-for-Later internals pending the §2 refactor. | `SipCheckUITests.swift` |

## Handoff to the CheckTabView/ScanningPipeline refactor track

These were implemented, verified on-simulator, then **reverted from CheckTabView to
respect the reservation**. Please absorb into the §2 rewrite (all support code is
already on main):

1. **Notification call sites (completes SPEED_PLAN #9):** `finalizeScan` →
   `scheduleFollowUpIfAuthorized(for:)`; Save-for-Later path →
   `requestAuthorizationAndScheduleFollowUp(for:)`.
2. **Already-tried banner (DESIGN #6):** pass
   `previousDrink: drinkStore.findMatch(for: scan.beerName)` to `VerdictCardView`.
3. **Enter-Beer sheet ergonomics:** auto-focus the field (`@FocusState` +
   `.onAppear`), `submitLabel(.search)`, `.onSubmit` runs the check. Verified to
   feel right on-simulator.
4. **Save-for-Later feedback:** interim fix (reset + confirmation banner) was
   reverted in favor of your planned optimistic "Saved ✓" flip (SPEED_PLAN #8) —
   just make sure *something* ships; the silent button is the single worst UX
   moment in the current app.
5. **F12 — container id clobbers child identifiers:** the bare
   `.accessibilityIdentifier("checkTab")` on CheckTabView's root ZStack
   overwrites the identifier of *every* element inside (XCUITest hierarchy dump
   shows Scan Label, Enter beer name, verdict text all reporting `checkTab`),
   which broke id-based UI tests and hurts accessibility tooling. Fix during the
   rewrite: put `.accessibilityElement(children: .contain)` immediately before
   the identifier (done for journalTab/profileTab on main), or drop the
   container id. UI tests currently work around it by querying visible labels.

## Known, intentionally not fixed by this track

- **F3 (withdrawn):** `HomeView`/`CheckBeerView`/`BeerListView`/`BeerDetailView`/`StatsView`
  are unreachable today and I planned to delete them — **don't**: SPEED_PLAN #12/#15
  schedule work inside them. Left untouched.
- Profile "Top Styles" bars are normalized to the max value (33% renders ~90% wide) —
  defensible, but worth a look during the §4 visual reset.
- Beer placeholder icon is a coffee mug (`mug.fill`); DESIGN §4 "kill the gray box"
  covers this.

## Functional finish verification (2026-07-14/15)

**Device:** local iPhone 17 Pro Simulator
`EAAA81D8-9F05-40CC-B2FD-08E0DE18CC8D`.

- Onboarding was completed from the age gate through go-to and stay-away picks.
  The selected named IPA affected the first typed verdict at full weight.
- Real library photos for Orion and Bia Viet resolved fully on-device. Warmed OCR
  took about 2.2-2.5 seconds, selected the visible beer name instead of bottle
  codes/legal copy, and carried the photo from the verdict flow into Add Beer,
  Journal, detail, and app relaunch.
- The deterministic `TestAssets/BeerPhotos/sample-tap-menu.png` fixture produced
  `Two Hearted IPA` as the single winner and `Allagash White Wheat` as the
  tap-to-reveal runner-up. ABV and section-header parser cases are unit tested.
- Save for Later requested notification permission only at that earned moment,
  created a Want to Try entry, and restored the saved photo/metadata into Add Beer.
- Release Settings hides provider/testing controls and sample-data seeding.
- Full automated result: 85 tests passed, 0 failed, 0 skipped.

Detailed walkthrough recordings were captured from the simulator and conformed
to exact constant 30 fps for review:

- `/tmp/sipcheck-motion/onboarding-detailed-30fps.mp4` (67.7s)
- `/tmp/sipcheck-motion/photo-journal-final-30fps.mp4` (43.2s)
- `/tmp/sipcheck-motion/menu-runnerup-final-30fps.mp4` (30.4s)

Contact sheets and frame strips in `/tmp/sipcheck-motion/` were inspected for
overlap, blank frames, transition continuity, and text clipping. The simulator
recorder did not produce 30 unique source frames each second, so the exports are
30 fps CFR rather than evidence of device rendering cadence.

**Still physical-device-only:** live camera ergonomics, DataScanner point-and-read,
Apple Foundation Models availability/wording, and real aisle/menu lighting. These
remain explicit device test items; they were not represented as simulator-verified.

## Physical-device hardening follow-up (2026-07-15)

**Branch:** `claude/codex-device-hardening`

**Simulator:** local iPhone 17 Pro, iOS 26.4.

- Built a shutterless VisionKit DataScanner path with an exact visible ROI,
  stable-text auto-capture, captured-frame handoff, and one-tap re-scan. The
  unsupported-simulator preview was checked at normal and accessibility text sizes;
  actual camera ergonomics remain device-only.
- Added the iOS 26 Foundation Models enrichment tier. It prewarms when available,
  runs only after the deterministic offline verdict is visible, preserves that
  verdict, and falls through to optional online enrichment. Signed generic iOS
  Release builds compile and link the guarded API.
- F9 is fixed: logging a beer atomically clears exact-name Want-to-Try duplicates,
  links the source scan to the journal entry, cancels reminders, and repeated
  notification actions do not add duplicate history.
- Human-paced rehearsal found and fixed two issues missed by screenshots: the typed
  sheet now owns its FocusState inside the presentation scope (keyboard rises without
  another tap), and an exact prior beer rating now outranks aggregate style history
  (`like` → TRY IT, `dislike` → SKIP IT, neutral → YOUR CALL).
- BeerMatcher now normalizes punctuation/diacritics, rejects generic short contains
  matches, ranks the closest match instead of storage order, and uses rolling-row
  Levenshtein memory with a long-OCR guard.
- Full result after the rehearsal fixes: **97 passed, 0 failed, 0 skipped**.

Review artifacts (workspace-local, intentionally not committed):

- `.artifacts/sipcheck-walkthroughs-2026-07-15/device-hardening-detailed-30fps.mp4`
  (36.33s, 904×1966, exact 30/1 CFR; scanner → typed suggestion → verdict → earned
  notification prompt → log → journal)
- `.artifacts/sipcheck-walkthroughs-2026-07-15/device-hardening-detailed-contact.png`
- `.artifacts/sipcheck-walkthroughs-2026-07-15/typed-entry-autofocus.png`
- `.artifacts/sipcheck-walkthroughs-2026-07-15/live-scanner-preview.png`

The video export is exact 30 fps CFR; AXe supplied roughly 15 unique simulator frames
per second, so this is flow/transition evidence rather than a claim about device render
cadence. The contact sheet was inspected for missed taps, blank frames, clipping, and
state continuity.

**Physical-device result:** CoreDevice discovers the paired iPhone 15 Pro, but its
network tunnel repeatedly times out before lock-state/install/launch. DataScanner and
real Foundation Models output therefore remain explicitly unverified on hardware; the
signed build, guards, simulator UI, pure helpers, and integration paths are verified.
