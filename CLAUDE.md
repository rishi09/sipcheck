# CLAUDE.md

## Project Overview
SipCheck is an iOS beer tracking app with AI-powered recommendations using SwiftUI, JSON persistence, and a hybrid scanning stack.

## Build Commands
```bash
# Build for simulator
xcodebuild -project SipCheck.xcodeproj -scheme SipCheck -destination 'platform=iOS Simulator,name=iPhone 16e' -configuration Debug build

# Install on simulator
xcrun simctl install "iPhone 16e" ~/Library/Developer/Xcode/DerivedData/SipCheck-*/Build/Products/Debug-iphonesimulator/SipCheck.app

# Launch on simulator
xcrun simctl launch "iPhone 16e" com.sipcheck.app
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
xcrun simctl spawn $SIMULATOR_UDID log stream --predicate 'subsystem=="com.sipcheck.app"'

# Build, install, launch (one-liner)
xcodebuild -project SipCheck.xcodeproj -scheme SipCheck -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" build && \
xcrun simctl install $SIMULATOR_UDID ~/Library/Developer/Xcode/DerivedData/SipCheck-*/Build/Products/Debug-iphonesimulator/SipCheck.app && \
xcrun simctl launch --terminate-running-process $SIMULATOR_UDID com.sipcheck.app
```

### Physical Device
```bash
# Device: Rishi's iPhone 16 (UDID: 00008140-000D74323E07001C)
# Preferred method: Xcode Cmd+R with iPhone selected as destination
# CLI alternative (if device is already prepared):
xcrun devicectl device install app --device 9D507846-A478-5220-B11A-B52B061B6E1C path/to/SipCheck.app
xcrun devicectl device process launch --terminate-existing --device 9D507846-A478-5220-B11A-B52B061B6E1C com.sipcheck.app
```

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
