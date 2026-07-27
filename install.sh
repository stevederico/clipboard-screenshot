#!/bin/zsh
# Installer for clipboard-screenshot
# Clipboard only — does not move screenshots or change save location.

set -euo pipefail
setopt NULL_GLOB
unsetopt NOMATCH

SUPPORT_DIR="${CLIPBOARD_SCREENSHOT_HOME:-$HOME/Library/Application Support/com.stevederico.clipboard-screenshot}"
APP_NAME="Clipboard Screenshot"
APP_BUNDLE="${SUPPORT_DIR}/${APP_NAME}.app"
APP_EXEC="${APP_BUNDLE}/Contents/MacOS/clipboard-screenshot"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
LABEL="com.stevederico.clipboard-screenshot"
PLIST_DEST="$LAUNCH_AGENTS/${LABEL}.plist"
OLD_LABEL="com.clipboard-screenshot.watcher"
OLD_PLIST="$LAUNCH_AGENTS/${OLD_LABEL}.plist"
UID_NUM=$(id -u)
DOMAIN="gui/${UID_NUM}"
LEGACY_SS_DIR="$HOME/Screenshots"

echo "==> Installing ${APP_NAME} (clipboard only — files stay put)"

mkdir -p "$SUPPORT_DIR" "$HOME/Desktop"
chmod 755 "$SUPPORT_DIR"

# Restore screenshot location if an older install redirected it
CURRENT_LOC=$(defaults read com.apple.screencapture location 2>/dev/null || echo "$HOME/Desktop")
CURRENT_LOC=${CURRENT_LOC/#\~/$HOME}
CURRENT_LOC=${CURRENT_LOC%/}
PREV_LOC_FILE="$LEGACY_SS_DIR/.previous-screencapture-location"
if [[ -f "$PREV_LOC_FILE" ]]; then
  RESTORE_TO=$(cat "$PREV_LOC_FILE")
  RESTORE_TO=${RESTORE_TO/#\~/$HOME}
  RESTORE_TO=${RESTORE_TO%/}
  if [[ "$CURRENT_LOC" != "$RESTORE_TO" ]]; then
    defaults write com.apple.screencapture location "$RESTORE_TO"
    launchctl kickstart -k "${DOMAIN}/com.apple.SystemUIServer.agent" 2>/dev/null \
      || killall SystemUIServer 2>/dev/null || true
    CURRENT_LOC="$RESTORE_TO"
    echo "==> Restored screenshot location → $CURRENT_LOC"
  fi
  rm -f "$PREV_LOC_FILE"
fi
if [[ "$CURRENT_LOC" == "$LEGACY_SS_DIR/Incoming" || "$CURRENT_LOC" == "$LEGACY_SS_DIR" ]]; then
  defaults write com.apple.screencapture location "$HOME/Desktop"
  launchctl kickstart -k "${DOMAIN}/com.apple.SystemUIServer.agent" 2>/dev/null \
    || killall SystemUIServer 2>/dev/null || true
  CURRENT_LOC="$HOME/Desktop"
  echo "==> Restored screenshot location → Desktop"
fi

# Tear down legacy install bits under ~/Screenshots
if [[ -d "$LEGACY_SS_DIR/Clipboard Screenshot.app" ]]; then
  rm -rf "$LEGACY_SS_DIR/Clipboard Screenshot.app"
  echo "==> Removed legacy app from ~/Screenshots"
fi
rm -f "$LEGACY_SS_DIR/watcher.sh" "$LEGACY_SS_DIR/watcher.log" \
      "$LEGACY_SS_DIR/.last-processed" "$LEGACY_SS_DIR/.last-processed.tmp"
rmdir "$LEGACY_SS_DIR/.watcher.lock" 2>/dev/null || true
rmdir "$LEGACY_SS_DIR/Incoming" 2>/dev/null || true

echo "==> Screenshot location: $CURRENT_LOC (unchanged by this tool)"

mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
cp -f "./watcher.sh" "$APP_EXEC"
chmod +x "$APP_EXEC"

cat > "${APP_BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>clipboard-screenshot</string>
    <key>CFBundleIdentifier</key>
    <string>${LABEL}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.5.1</string>
    <key>CFBundleVersion</key>
    <string>1.5.1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>${APP_NAME} detects new screenshots so they can be copied to the clipboard.</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © Steve Derico</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "${APP_BUNDLE}/Contents/PkgInfo"
xattr -dr com.apple.quarantine "$APP_BUNDLE" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_BUNDLE" 2>/dev/null || true

mkdir -p "$LAUNCH_AGENTS"
launchctl bootout "${DOMAIN}/${OLD_LABEL}" 2>/dev/null || true
rm -f "$OLD_PLIST"

# Event-driven: launchd WatchPaths = FSEvents under the hood (no poll loop)
watch_paths=("$CURRENT_LOC")
if [[ "$CURRENT_LOC" != "$HOME/Desktop" ]]; then
  watch_paths+=("$HOME/Desktop")
fi

WATCH_XML=""
for p in "${watch_paths[@]}"; do
  WATCH_XML+="        <string>${p}</string>
"
done

cat > "$PLIST_DEST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>

    <key>ProgramArguments</key>
    <array>
        <string>${APP_EXEC}</string>
    </array>

    <key>WatchPaths</key>
    <array>
${WATCH_XML}    </array>

    <key>ThrottleInterval</key>
    <integer>0</integer>

    <key>ExitTimeOut</key>
    <integer>15</integer>

    <key>RunAtLoad</key>
    <false/>
    <key>KeepAlive</key>
    <false/>

    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>

    <key>ProcessType</key>
    <string>Interactive</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin</string>
        <key>HOME</key>
        <string>${HOME}</string>
        <key>CLIPBOARD_SCREENSHOT_HOME</key>
        <string>${SUPPORT_DIR}</string>
    </dict>

    <key>StandardOutPath</key>
    <string>${SUPPORT_DIR}/watcher.log</string>
    <key>StandardErrorPath</key>
    <string>${SUPPORT_DIR}/watcher.log</string>
</dict>
</plist>
EOF

chmod 644 "$PLIST_DEST"

if launchctl print "${DOMAIN}/${LABEL}" &>/dev/null; then
  launchctl bootout "${DOMAIN}/${LABEL}" 2>/dev/null || true
fi
launchctl unload "$PLIST_DEST" 2>/dev/null || true

if launchctl bootstrap "$DOMAIN" "$PLIST_DEST" 2>/dev/null; then
  launchctl enable "${DOMAIN}/${LABEL}" 2>/dev/null || true
  echo "==> Bootstrapped WatchPaths agent (${DOMAIN}/${LABEL})"
else
  launchctl load -w "$PLIST_DEST"
fi

echo
echo "App:     $APP_BUNDLE"
echo "Trigger: WatchPaths on ${watch_paths[*]} (FS event — not polling)"
echo "Logs:    $SUPPORT_DIR/watcher.log"
echo
echo "Screenshots stay put. New ones → clipboard."
echo "If asked: allow Automation for “${APP_NAME}” → System Events."
echo
echo "Stop:      launchctl bootout ${DOMAIN}/${LABEL}"
echo "Uninstall: cd $(pwd) && ./uninstall.sh"
