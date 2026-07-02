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

## Known, intentionally not fixed by this track

- **F3 (withdrawn):** `HomeView`/`CheckBeerView`/`BeerListView`/`BeerDetailView`/`StatsView`
  are unreachable today and I planned to delete them — **don't**: SPEED_PLAN #12/#15
  schedule work inside them. Left untouched.
- **F9:** the same beer can sit in Want to Try and Tried simultaneously (save flow
  doesn't consult history). Mitigated by the F8 banner; a real dedupe belongs with
  the refactor's save-flow changes.
- Profile "Top Styles" bars are normalized to the max value (33% renders ~90% wide) —
  defensible, but worth a look during the §4 visual reset.
- Beer placeholder icon is a coffee mug (`mug.fill`); DESIGN §4 "kill the gray box"
  covers this.
