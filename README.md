# SipCheck

## Overview
SipCheck is an iOS app for tracking beers you've tried and getting AI-powered recommendations. Take a photo of a beer label to automatically extract details, rate your beers, and use the "Check Beer" feature to see if you've tried something before with personalized AI recommendations based on your taste history.

## Tech Stack
- **UI:** SwiftUI (iOS 17+)
- **Persistence:** JSON file storage (ObservableObject pattern)
- **AI:** OpenAI GPT-4o (Vision API for label scanning, Chat API for recommendations)
- **Architecture:** No Swift macros (for build compatibility)

## Features
- ✅ Add beers manually or via camera
- ✅ Rate beers (Like / Neutral / Dislike)
- ✅ Filter by rating or style
- ✅ Check if you've tried a beer before
- ✅ AI-powered personalized recommendations
- ✅ Edit and delete entries
- ✅ Data persistence across app restarts

## Current Status

**Build:** ✅ Passing (0 errors, 0 warnings)
**Git:** Pushed to `main` (commit `e971c5a`)
**Simulator:** Tested on iPhone 16e

## Todo List

| Task | Status |
|------|--------|
| Push to GitHub (secret removed) | ✅ Completed |
| Add app icon | ⏳ Pending |
| Add launch screen branding | ⏳ Pending |
| Polish empty state onboarding | ⏳ Pending |
| Test on physical device (camera) | ⏳ Pending |
| Test OpenAI flows with real images | ⏳ Pending |

## Setup

1. Clone the repo
2. Copy `SipCheck/Secrets.swift.example` to `SipCheck/Secrets.swift`
3. Add your OpenAI API key to `Secrets.swift`
4. Open `SipCheck.xcodeproj` in Xcode
5. Build and run on simulator or device

## File Structure
```
SipCheck/
├── SipCheckApp.swift          # App entry point
├── Config.swift               # Configuration (loads from Secrets)
├── Secrets.swift              # API keys (gitignored)
├── Models/
│   ├── Drink.swift            # Beer model
│   └── DrinkEnums.swift       # Rating, DrinkType, BeerStyle
├── Views/
│   ├── HomeView.swift         # Main screen
│   ├── AddBeerView.swift      # Add beer form
│   ├── BeerListView.swift     # All beers list
│   ├── BeerDetailView.swift   # View/edit beer
│   ├── CheckBeerView.swift    # Check beer + AI
│   └── Components/
│       ├── RatingPicker.swift
│       ├── StylePicker.swift
│       └── CameraView.swift
├── Services/
│   ├── DrinkStore.swift       # Data persistence
│   ├── OpenAIService.swift    # AI integration
│   └── BeerMatcher.swift      # Fuzzy matching
└── Resources/
    └── Assets.xcassets
```
