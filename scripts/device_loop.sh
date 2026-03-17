#!/bin/bash
# scripts/device_loop.sh — Build, install, launch on physical iPhone
#
# The on-device iteration loop:
#   1. Build for device (arm64, iphoneos)
#   2. Install .app on device via devicectl
#   3. Launch app (terminate any existing instance)
#   4. Stream logs to console
#   5. Take screenshot on demand
#
# Usage:
#   ./scripts/device_loop.sh              # Build + install + launch
#   ./scripts/device_loop.sh --skip-build  # Install + launch (use last build)
#   ./scripts/device_loop.sh --test        # Build + run XCTest on device
#   ./scripts/device_loop.sh --screenshot  # Just take a screenshot
#   ./scripts/device_loop.sh --logs        # Just stream logs
#
# Requires: Xcode, Apple Developer account configured in project signing

set -uo pipefail

# ---- Config ----
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$PROJECT_DIR/SipCheck.xcodeproj"
SCHEME="SipCheck"
BUNDLE_ID="com.sipcheck.app"

# Device identifiers (Rishi's iPhone 16)
DEVICE_UDID="00008140-000D74323E07001C"
DEVICE_NAME="Rishi Shah's iPhone"
# CoreDevice UUID (used by devicectl)
COREDEVICE_ID="9D507846-A478-5220-B11A-B52B061B6E1C"

# Build output
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
BUILD_DIR="" # Set after build
SCREENSHOT_DIR="/tmp/sipcheck-device"

mkdir -p "$SCREENSHOT_DIR"

# ---- Parse args ----
SKIP_BUILD=false
RUN_TESTS=false
SCREENSHOT_ONLY=false
LOGS_ONLY=false
LAUNCH_ARGS=""

for arg in "$@"; do
  case $arg in
    --skip-build) SKIP_BUILD=true ;;
    --test) RUN_TESTS=true ;;
    --screenshot) SCREENSHOT_ONLY=true ;;
    --logs) LOGS_ONLY=true ;;
    --mock-ai) LAUNCH_ARGS="$LAUNCH_ARGS --mock-ai" ;;
    --seed-data) LAUNCH_ARGS="$LAUNCH_ARGS --seed-data" ;;
    --isolated-storage) LAUNCH_ARGS="$LAUNCH_ARGS --isolated-storage" ;;
    *) echo "Unknown arg: $arg"; exit 1 ;;
  esac
done

# ---- Helpers ----

find_app() {
  # Find the most recent device build
  local app_path
  app_path=$(find "$DERIVED_DATA" -path "*/Build/Products/Debug-iphoneos/SipCheck.app" -type d 2>/dev/null | head -1)
  if [ -z "$app_path" ]; then
    echo "ERROR: No device build found. Run without --skip-build first." >&2
    exit 1
  fi
  echo "$app_path"
}

take_screenshot() {
  local name="${1:-screenshot}"
  local output="$SCREENSHOT_DIR/${name}-$(date +%H%M%S).png"
  # Use devicectl to copy a screenshot - fall back to Xcode's method
  if xcrun devicectl device copy screenshot --device "$COREDEVICE_ID" "$output" 2>/dev/null; then
    echo "Screenshot: $output"
  else
    echo "Screenshot failed — device may need to be unlocked"
  fi
}

stream_logs() {
  echo "Streaming app logs (Ctrl+C to stop)..."
  xcrun devicectl device process launch --terminate-existing --console --device "$COREDEVICE_ID" "$BUNDLE_ID" $LAUNCH_ARGS 2>&1
}

# ---- Screenshot only ----
if $SCREENSHOT_ONLY; then
  take_screenshot "manual"
  exit 0
fi

# ---- Logs only ----
if $LOGS_ONLY; then
  stream_logs
  exit 0
fi

# ---- Build ----
if ! $SKIP_BUILD; then
  echo "=== Building for device ==="
  echo "Device: $DEVICE_NAME ($DEVICE_UDID)"
  echo ""

  if xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS,id=$DEVICE_UDID" \
    -configuration Debug \
    build \
    2>&1 | tail -5; then
    echo ""
    echo "BUILD SUCCEEDED"
  else
    echo ""
    echo "BUILD FAILED"
    echo ""
    echo "Common fixes:"
    echo "  1. Set DEVELOPMENT_TEAM in Xcode: Signing & Capabilities -> Team"
    echo "  2. Trust the developer profile on your iPhone:"
    echo "     Settings -> General -> VPN & Device Management -> Developer App"
    echo "  3. Make sure device is unlocked and trusted"
    exit 1
  fi
fi

# ---- Run tests on device ----
if $RUN_TESTS; then
  echo ""
  echo "=== Running tests on device ==="
  xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS,id=$DEVICE_UDID" \
    -only-testing:SipCheckTests \
    2>&1 | grep -E '(Test Suite|Test Case|passed|failed|error:|\*\*)'

  echo ""
  echo "=== Running UI tests on device ==="
  xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS,id=$DEVICE_UDID" \
    -only-testing:SipCheckUITests \
    2>&1 | grep -E '(Test Suite|Test Case|passed|failed|error:|\*\*)'

  exit $?
fi

# ---- Install ----
echo ""
echo "=== Installing on device ==="
APP_PATH=$(find_app)
echo "App: $APP_PATH"

if xcrun devicectl device install app --device "$COREDEVICE_ID" "$APP_PATH" 2>&1; then
  echo "INSTALL SUCCEEDED"
else
  echo "INSTALL FAILED"
  echo ""
  echo "Common fixes:"
  echo "  1. Unlock your iPhone"
  echo "  2. Trust the developer profile:"
  echo "     Settings -> General -> VPN & Device Management"
  echo "  3. Check USB connection"
  exit 1
fi

# ---- Launch ----
echo ""
echo "=== Launching on device ==="
if xcrun devicectl device process launch --terminate-existing --device "$COREDEVICE_ID" "$BUNDLE_ID" $LAUNCH_ARGS 2>&1; then
  echo "LAUNCH SUCCEEDED"
else
  echo "LAUNCH FAILED"
  exit 1
fi

echo ""
echo "=== SipCheck running on $DEVICE_NAME ==="
echo ""
echo "Quick actions:"
echo "  ./scripts/device_loop.sh --screenshot    # Take a screenshot"
echo "  ./scripts/device_loop.sh --logs          # Stream app logs"
echo "  ./scripts/device_loop.sh --skip-build    # Re-install last build"
echo "  ./scripts/device_loop.sh --test          # Run tests on device"
echo ""
