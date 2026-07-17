# Founder Feedback Finish - 2026-07-17

## Source feedback

| Clip | Feedback | Resolution |
|---|---|---|
| `7555` | Recent scans do not respond to taps; show the photo that was logged. | Recent-scan rows are full-width buttons with photo thumbnails. Tapping opens Scan Details with the stored photo, verdict, rationale, metadata, and linked Journal context. |
| `7595` | Replaying onboarding should reset follow-up reminders so the trigger can be observed again. | Replay now restores the app reminder trigger to its default-on state, clears pending/delivered follow-ups and pending actions, and preserves the user's system notification authorization. |
| `7650` | The first onboarding screen needs more direct, outcome-oriented copy. | Default copy is now "Pick the right beer, fast." with a short personalization benefit. Existing Onboarding Lab variants remain available. |
| `7687` | The scan and learning story screens feel repetitive and make onboarding too long. | The default and plus flows now use two story pages. The second page combines the immediate verdict and learning story; the control variant remains unchanged for comparison. |
| `7804` | Go-to and walk-past questions should be visual, beer-first, compact, and independent blank slates. | Both pages now lead with horizontally scrollable, code-native can tiles, followed by a compact style strip. Saved choices are not preselected during replay, and choices are never grayed out or cross-locked between the two pages. Blank Next preserves existing taste data; “Nothing's off the table” explicitly clears stay-aways. |

## Verification

- iPhone 17 Pro simulator: focused recent-scan detail UI test passed, including the captured-photo region.
- iPhone 17 Pro simulator: replay/reminder reset and shortened onboarding UI test passed, including blank-slate go-to and stay-away assertions.
- iPhone 17 Pro simulator: a real persisted photo was injected and rendered in both the recent-scan row and Scan Details.
- iPhone 16e simulator: first story, combined second story, and beer-first picker were visually reviewed at the compact viewport with no clipping or overlap.
- Unit/integration suite: 113 tests passed with zero failures.
- Clean CI compact-simulator E2E run 46 (`29620235864`): all 8 flows passed with zero failures, including recent-scan detail and the full reminder/onboarding/IPA-clear path.
- Clean signed Release run `29620235876`: archive and export passed with branch upload correctly disabled.

## Release gate

`fastlane` now waits for App Store Connect processing, assigns the build to existing internal groups that do not already receive every build, and verifies both internal-testing readiness and group availability before printing `UPLOAD_OK`.
