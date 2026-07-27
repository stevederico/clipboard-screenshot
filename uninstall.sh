#!/bin/zsh
# Uninstall clipboard-screenshot

set -euo pipefail

APP_NAME="Clipboard Screenshot"
SUPPORT_DIR="${CLIPBOARD_SCREENSHOT_HOME:-$HOME/Library/Application Support/com.stevederico.clipboard-screenshot}"
APP_BUNDLE="${SUPPORT_DIR}/${APP_NAME}.app"
LABEL="com.stevederico.clipboard-screenshot"
OLD_LABEL="com.clipboard-screenshot.watcher"
PLIST_DEST="$HOME/Library/LaunchAgents/${LABEL}.plist"
OLD_PLIST="$HOME/Library/LaunchAgents/${OLD_LABEL}.plist"
LEGACY_SS_DIR="$HOME/Screenshots"
UID_NUM=$(id -u)
DOMAIN="gui/${UID_NUM}"

echo "==> Uninstalling ${APP_NAME}"

for lbl in "$LABEL" "$OLD_LABEL"; do
  launchctl bootout "${DOMAIN}/${lbl}" 2>/dev/null || true
done
for p in "$PLIST_DEST" "$OLD_PLIST"; do
  if [[ -f "$p" ]]; then
    launchctl unload -w "$p" 2>/dev/null || true
    rm -f "$p"
    echo "    Removed $(basename "$p")"
  fi
done

rm -rf "$APP_BUNDLE" "$SUPPORT_DIR"
# Legacy paths from earlier versions
rm -rf "$LEGACY_SS_DIR/Clipboard Screenshot.app"
rm -f "$LEGACY_SS_DIR/watcher.sh" "$LEGACY_SS_DIR/watcher.log" \
      "$LEGACY_SS_DIR/.last-processed" "$LEGACY_SS_DIR/.previous-screencapture-location"
rmdir "$LEGACY_SS_DIR/.watcher.lock" 2>/dev/null || true
rmdir "$LEGACY_SS_DIR/Incoming" 2>/dev/null || true
echo "    Removed app + support files"

echo
echo "Uninstalled. Your Desktop screenshots were not deleted."
