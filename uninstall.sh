#!/bin/zsh
# Uninstall grok-screenshot

set -euo pipefail

LABEL="com.grok.screenshot-watcher"
PLIST_NAME="${LABEL}.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/$PLIST_NAME"
SS_DIR="${GROK_HOME:-$HOME/.grok}/screenshots"

echo "==> Uninstalling grok-screenshot watcher"

if [[ -f "$PLIST_DEST" ]]; then
  launchctl unload -w "$PLIST_DEST" 2>/dev/null || true
  rm -f "$PLIST_DEST"
  echo "    Removed launch agent"
fi

read -q "REPLY?Delete all moved screenshots in ${SS_DIR}? (y/N) "
echo
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
  rm -rf "$SS_DIR"
  echo "    Deleted screenshots"
else
  echo "    Left screenshots in place"
fi

echo
echo "✅ Uninstalled."
