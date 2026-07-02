#!/usr/bin/env bash
# Auto-ship: watches origin/main and installs every new merge onto Rishi's
# iPhone over Wi-Fi (via ship_to_phone.sh). Run once with --install and forget:
#
#   ./scripts/watch_and_ship.sh --install    # registers a launchd agent
#   ./scripts/watch_and_ship.sh --uninstall  # removes it
#
# Logs: ~/Library/Logs/sipcheck-autoship.log
# Behavior: polls every 3 minutes; skips when nothing new; a failed install
# (phone locked / off Wi-Fi / asleep) just retries on the next new commit.
set -uo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.rishishah.sipcheck.autoship"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOG="$HOME/Library/Logs/sipcheck-autoship.log"
STATE="$HOME/.sipcheck-last-shipped"

if [ "${1:-}" = "--install" ]; then
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
  cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string>
    <string>${REPO_DIR}/scripts/watch_and_ship.sh</string>
  </array>
  <key>StartInterval</key><integer>180</integer>
  <key>StandardOutPath</key><string>${LOG}</string>
  <key>StandardErrorPath</key><string>${LOG}</string>
</dict></plist>
PLIST
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load "$PLIST"
  echo "✅ Auto-ship installed. Every merge to main now lands on your iPhone"
  echo "   within ~3 minutes (phone on same Wi-Fi). Log: $LOG"
  exit 0
fi

if [ "${1:-}" = "--uninstall" ]; then
  launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Auto-ship removed."
  exit 0
fi

# ---- single poll cycle (launchd calls this every StartInterval) ----
cd "$REPO_DIR" || exit 0
git fetch origin main -q 2>>"$LOG" || exit 0
REMOTE=$(git rev-parse origin/main)
LAST=$(cat "$STATE" 2>/dev/null || echo none)
[ "$REMOTE" = "$LAST" ] && exit 0

echo "[$(date '+%F %T')] new main $REMOTE (last shipped: $LAST) — shipping" >>"$LOG"
if "$REPO_DIR/scripts/ship_to_phone.sh" >>"$LOG" 2>&1; then
  echo "$REMOTE" > "$STATE"
  echo "[$(date '+%F %T')] ✅ shipped $REMOTE" >>"$LOG"
else
  echo "[$(date '+%F %T')] ⚠️ ship failed (phone locked/off Wi-Fi?) — will retry next cycle" >>"$LOG"
fi
