#!/bin/zsh
# Uninstall clipboard-screenshot

set -euo pipefail

LABEL="com.clipboard-screenshot.watcher"
PLIST_NAME="${LABEL}.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/$PLIST_NAME"
SS_DIR="${SCREENSHOTS_DIR:-$HOME/Screenshots}"
INBOX_DIR="${SCREENSHOTS_INBOX:-$SS_DIR/Incoming}"
PREV_LOC_FILE="$SS_DIR/.previous-screencapture-location"
UID_NUM=$(id -u)
DOMAIN="gui/${UID_NUM}"

echo "==> Uninstalling clipboard-screenshot"

if launchctl print "${DOMAIN}/${LABEL}" &>/dev/null; then
  launchctl bootout "${DOMAIN}/${LABEL}" 2>/dev/null || true
fi
if [[ -f "$PLIST_DEST" ]]; then
  launchctl unload -w "$PLIST_DEST" 2>/dev/null || true
  rm -f "$PLIST_DEST"
  echo "    Removed launch agent"
fi

# Restore prior screenshot location if we changed it
if [[ -f "$PREV_LOC_FILE" ]]; then
  prev=$(cat "$PREV_LOC_FILE")
  defaults write com.apple.screencapture location "$prev"
  launchctl kickstart -k "${DOMAIN}/com.apple.SystemUIServer.agent" 2>/dev/null \
    || killall SystemUIServer 2>/dev/null \
    || true
  echo "    Restored screenshot location → $prev"
fi

rm -f "$SS_DIR/watcher.sh" "$SS_DIR/watcher.log" "$SS_DIR/.last-processed" \
      "$SS_DIR/.last-processed.tmp" "$SS_DIR/.previous-screencapture-location"
rmdir "$SS_DIR/.watcher.lock" 2>/dev/null || true
# Leave inbox dir if empty
rmdir "$INBOX_DIR" 2>/dev/null || true
echo "    Removed watcher script + logs"

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
