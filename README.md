# SipCheck

SipCheck is an iOS beer journal that helps you scan labels, remember what you've tried, and get AI-assisted recommendations based on your history.

## Current Product State

- SwiftUI app targeting iOS 17+
- JSON persistence via `DrinkStore`
- First-launch onboarding is implemented
- Stats and export screens are implemented
- Hybrid scan pipeline is in progress and wired into the camera flows:
  - Apple Vision OCR on-device
  - Gemini text extraction on the fast path
  - OpenAI vision fallback when OCR is weak
- Unit, integration, and UI test targets exist

## Core Features

- Add beers manually or from the camera
- Save beer photos with entries
- Rate beers as like / neutral / dislike
- Track notes, style, type, and optional ABV
- Check whether you've tried a beer before
- Get AI recommendations based on your history
- Browse recent beers, full history, and stats
- Export your data as JSON or CSV

## What Still Needs Work

| Task | Status |
|------|--------|
| Physical-device camera validation | ⏳ Pending |
| Real-label evaluation for OCR and AI quality | ⏳ Pending |
| App icon asset | ⏳ Pending |
| Launch screen branding/polish | ⏳ Pending |
| Recommendation prompt/provider cleanup | ⏳ Pending |
| README/docs alignment cleanup | ⏳ In progress |

## Architecture

- **UI:** SwiftUI with `ObservableObject`
- **Persistence:** JSON file storage in the app Documents directory
- **Scanning:** Apple Vision OCR + Gemini text parsing + OpenAI vision fallback
- **Recommendations:** OpenAI today, with provider abstraction groundwork in place
- **Testing:** XCTest + XCUITest with deterministic launch arguments

## Test Modes

The app supports launch arguments used by tests:

- `--mock-ai` returns fixed AI responses with no network
- `--seed-data` loads known test beers on launch
- `--isolated-storage` stores data in a temp directory instead of real Documents

See `scripts/run_tests.sh` for the current test entrypoint.

## Setup

1. Copy `SipCheck/Secrets.swift.example` to `SipCheck/Secrets.swift`.
2. Add your `openAIAPIKey` and `geminiAPIKey`.
3. Open `SipCheck.xcodeproj` in Xcode.
4. Build and run on a simulator or device.

## Build

```bash
xcodebuild -project SipCheck.xcodeproj -scheme SipCheck -destination 'platform=iOS Simulator,name=iPhone 16e' -configuration Debug build
```

## Project Notes

- `README.md` and `CLAUDE.md` should reflect current project state.
- Files under `plans/` are planning artifacts and may describe work that has already landed or changed direction.
