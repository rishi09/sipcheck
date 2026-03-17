# SipCheck Notes

> Status note: this is a working note for testing assets and manual validation. Some guidance below predates the current camera flows and should not be treated as the app's current feature inventory.

## Beer Label Photo Resources

### What to skip for now

| Resource | Skip? | Why |
|---|---|---|
| Roboflow | Skip | For training custom ML models, not for your GPT-4o approach |
| Kaggle dataset | Skip | Same — ML training data |
| Pexels 8K photos | Skip | Overkill, you have enough test images |
| Burst photos | **Use** | Great for testing + App Store screenshots |
| Beer-Label-Classification | **Use** | Real-world bottle photos, perfect for testing |

### Where the files are
- Burst photos: `/tmp/beer-label-photos/` (16 photos, CC0)
- Beer-Label-Classification: `/tmp/beer-label-photos/query/` and `/tmp/beer-label-photos/database/` (22 downloaded, clone https://github.com/Sid2697/Beer-Label-Classification for 200+)

## How to Test on Your iPhone

### Option 1: Simulator (no real camera)
```bash
# Build, install, launch on simulator
SIMULATOR_UDID="48FF0EDE-5280-4C70-AB5C-F06C750443DB"
xcodebuild -project SipCheck.xcodeproj -scheme SipCheck -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" build && \
xcrun simctl install $SIMULATOR_UDID ~/Library/Developer/Xcode/DerivedData/SipCheck-*/Build/Products/Debug-iphonesimulator/SipCheck.app && \
xcrun simctl launch --terminate-running-process $SIMULATOR_UDID com.sipcheck.app
```
Note: Camera still won't work on simulator. The app has camera-based scan flows now, but device testing is still the primary way to validate real scanning behavior.

### Option 2: Run on Your Real iPhone (recommended)
1. Plug your iPhone in via USB
2. Open `SipCheck.xcodeproj` in Xcode
3. Select your iPhone from the device dropdown (top bar)
4. You may need to: go to **Settings > General > VPN & Device Management** on your phone and trust your developer certificate
5. Hit the Play button (or Cmd+R) to build and run
6. The app installs on your phone — camera works, you can scan real beer labels

### Option 3: Push test photos to simulator
```bash
# Push a beer label photo to the simulator's photo library
xcrun simctl addmedia $SIMULATOR_UDID /tmp/beer-label-photos/burst-beer-can-1.jpg
```
(Only useful if you add or use a simulator-accessible image ingestion path; the current app is centered on live camera capture.)
