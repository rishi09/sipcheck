# CLAUDE.md

## Project Overview
SipCheck is an iOS beer tracking app with AI-powered recommendations using SwiftUI and OpenAI GPT-4o.

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
- `SipCheck/Services/OpenAIService.swift` - AI integration

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
- Simulator: iPhone 16e works well
- Camera features require physical device
- Sample data can be injected via drinks.json in app container

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
- Core features: ✅ Complete
- Pending: App icon, launch screen, device testing
