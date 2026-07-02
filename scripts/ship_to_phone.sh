#!/usr/bin/env bash
# One command: latest main → Rishi's iPhone, over Wi-Fi. No Xcode window.
#
#   ./scripts/ship_to_phone.sh
#
# Requirements: phone paired once via cable (done 2026-07-02), same Wi-Fi as
# the Mac, phone unlocked for the install step. Works entirely via CLI —
# xcodebuild for the signed Debug build, devicectl for wireless install+launch.
set -euo pipefail
cd "$(dirname "$0")/.."

# Rishi's iPhone 15 Pro (paired + network-enabled).
UDID="00008130-000869DC2021401C"
COREDEVICE="679B7B14-AE0C-58B3-A5B2-EBE25D2383E8"
BUNDLE_ID="com.rishishah.sipcheck"

echo "==> Pulling latest main"
git checkout main >/dev/null 2>&1 || true
git pull --ff-only

echo "==> Building for device (Debug, automatic signing)"
xcodebuild -project SipCheck.xcodeproj -scheme SipCheck -configuration Debug \
  -destination "platform=iOS,id=${UDID}" \
  -derivedDataPath build/phone \
  -allowProvisioningUpdates \
  build | tail -3

APP=$(find build/phone/Build/Products -maxdepth 2 -name "SipCheck.app" | head -1)
[ -n "$APP" ] || { echo "build product not found"; exit 1; }

echo "==> Installing to iPhone over Wi-Fi"
xcrun devicectl device install app --device "$COREDEVICE" "$APP"

echo "==> Launching"
xcrun devicectl device process launch --terminate-existing \
  --device "$COREDEVICE" "$BUNDLE_ID"

echo "✅ Latest main is running on your iPhone ($(git rev-parse --short HEAD))"
