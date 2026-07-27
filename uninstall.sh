#!/bin/zsh
# Uninstall clipboard-screenshot

set -euo pipefail

APP_NAME="Clipboard Screenshot"
SS_DIR="${SCREENSHOTS_DIR:-$HOME/Screenshots}"
APP_BUNDLE="${SS_DIR}/${APP_NAME}.app"
LABEL="com.stevederico.clipboard-screenshot"
OLD_LABEL="com.clipboard-screenshot.watcher"
PLIST_DEST="$HOME/Library/LaunchAgents/${LABEL}.plist"
OLD_PLIST="$HOME/Library/LaunchAgents/${OLD_LABEL}.plist"
UID_NUM=$(id -u)
DOMAIN="gui/${UID_NUM}"

echo "==> Uninstalling ${APP_NAME}"

for lbl in "$LABEL" "$OLD_LABEL"; do
  if launchctl print "${DOMAIN}/${lbl}" &>/dev/null; then
    launchctl bootout "${DOMAIN}/${lbl}" 2>/dev/null || true
  fi
done
for p in "$PLIST_DEST" "$OLD_PLIST"; do
  if [[ -f "$p" ]]; then
    launchctl unload -w "$p" 2>/dev/null || true
    rm -f "$p"
    echo "    Removed $(basename "$p")"
  fi
done

# Does not touch com.apple.screencapture location (we no longer change it)

rm -rf "$APP_BUNDLE"
rm -f "$SS_DIR/watcher.sh" "$SS_DIR/watcher.log" "$SS_DIR/.last-processed" \
      "$SS_DIR/.last-processed.tmp" "$SS_DIR/.previous-screencapture-location"
rmdir "$SS_DIR/.watcher.lock" 2>/dev/null || true
rmdir "$SS_DIR/Incoming" 2>/dev/null || true
echo "    Removed ${APP_NAME}.app + watcher bits"

if [[ -t 0 ]]; then
  read -q "REPLY?Delete all screenshots in ${SS_DIR}? (y/N) "
  echo
  if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    rm -rf "$SS_DIR"
    echo "    Deleted screenshots"
  else
    echo "    Left screenshots in place"
  fi
else
  echo "    Left screenshots in place (non-interactive)"
fi

echo
echo "Uninstalled."
