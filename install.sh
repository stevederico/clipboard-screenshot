#!/bin/zsh
# Installer for clipboard-screenshot
# Named .app + launch agent. Does NOT change your screenshot save location.

set -euo pipefail
setopt NULL_GLOB
unsetopt NOMATCH

SS_DIR="${SCREENSHOTS_DIR:-$HOME/Screenshots}"
APP_NAME="Clipboard Screenshot"
APP_BUNDLE="${SS_DIR}/${APP_NAME}.app"
APP_EXEC="${APP_BUNDLE}/Contents/MacOS/clipboard-screenshot"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
LABEL="com.stevederico.clipboard-screenshot"
PLIST_NAME="${LABEL}.plist"
PLIST_DEST="$LAUNCH_AGENTS/$PLIST_NAME"
OLD_LABEL="com.clipboard-screenshot.watcher"
OLD_PLIST="$LAUNCH_AGENTS/${OLD_LABEL}.plist"
UID_NUM=$(id -u)
DOMAIN="gui/${UID_NUM}"
PREV_LOC_FILE="$SS_DIR/.previous-screencapture-location"

echo "==> Installing ${APP_NAME}"

mkdir -p "$SS_DIR" "$HOME/Desktop" "$HOME/Pictures/Screenshots"
chmod 755 "$SS_DIR"

# If a previous install redirected screenshots to Incoming, put them back.
CURRENT_LOC=$(defaults read com.apple.screencapture location 2>/dev/null || echo "$HOME/Desktop")
CURRENT_LOC=${CURRENT_LOC/#\~/$HOME}
CURRENT_LOC=${CURRENT_LOC%/}

if [[ -f "$PREV_LOC_FILE" ]]; then
  RESTORE_TO=$(cat "$PREV_LOC_FILE")
  RESTORE_TO=${RESTORE_TO/#\~/$HOME}
  RESTORE_TO=${RESTORE_TO%/}
elif [[ "$CURRENT_LOC" == "$SS_DIR/Incoming" || "$CURRENT_LOC" == "$SS_DIR" ]]; then
  RESTORE_TO="$HOME/Desktop"
else
  RESTORE_TO=""
fi

if [[ -n "$RESTORE_TO" && "$CURRENT_LOC" != "$RESTORE_TO" ]]; then
  defaults write com.apple.screencapture location "$RESTORE_TO"
  launchctl kickstart -k "${DOMAIN}/com.apple.SystemUIServer.agent" 2>/dev/null \
    || killall SystemUIServer 2>/dev/null \
    || true
  echo "==> Restored screenshot location → $RESTORE_TO"
  CURRENT_LOC="$RESTORE_TO"
fi
rm -f "$PREV_LOC_FILE"

# Drain leftover Incoming/ from the old approach into the archive
if [[ -d "$SS_DIR/Incoming" ]]; then
  drained=0
  for f in "$SS_DIR/Incoming"/Screenshot*(N) "$SS_DIR/Incoming"/Screen\ Shot*(N); do
    [[ -f "$f" ]] || continue
    name=$(basename -- "$f")
    dest="$SS_DIR/$(date +%Y-%m-%d_%H-%M-%S)_$name"
    mv "$f" "$dest" 2>/dev/null && (( drained++ )) || true
  done
  rmdir "$SS_DIR/Incoming" 2>/dev/null || true
  if (( drained > 0 )); then
    echo "==> Drained $drained file(s) from old Incoming/ folder"
  fi
fi

echo "==> macOS screenshot location left as: $CURRENT_LOC"

# Build named .app (so Login Items show "Clipboard Screenshot", not zsh)
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
cp -f "./watcher.sh" "$APP_EXEC"
chmod +x "$APP_EXEC"
cp -f "./watcher.sh" "$SS_DIR/watcher.sh"
chmod +x "$SS_DIR/watcher.sh"

cat > "${APP_BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
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
    <string>1.2.0</string>
    <key>CFBundleVersion</key>
    <string>1.2.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>${APP_NAME} lists your screenshot folder so new captures can be archived and copied to the clipboard.</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © Steve Derico</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "${APP_BUNDLE}/Contents/PkgInfo"
xattr -dr com.apple.quarantine "$APP_BUNDLE" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_BUNDLE" 2>/dev/null || true

mkdir -p "$LAUNCH_AGENTS"

# Remove old agent names
for lbl in "$OLD_LABEL"; do
  launchctl bootout "${DOMAIN}/${lbl}" 2>/dev/null || true
done
rm -f "$OLD_PLIST"

# Watch whatever macOS actually uses + Desktop (common default)
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
    <integer>1</integer>

    <key>ExitTimeOut</key>
    <integer>30</integer>

    <key>RunAtLoad</key>
    <true/>
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
        <key>SCREENSHOTS_DIR</key>
        <string>${SS_DIR}</string>
        <key>HOME</key>
        <string>${HOME}</string>
    </dict>

    <key>StandardOutPath</key>
    <string>${SS_DIR}/watcher.log</string>
    <key>StandardErrorPath</key>
    <string>${SS_DIR}/watcher.log</string>
</dict>
</plist>
EOF

chmod 644 "$PLIST_DEST"

echo "==> App:   $APP_BUNDLE"
echo "==> Agent: $PLIST_DEST"
echo "    Watch: ${watch_paths[*]}"
echo "    Archive: $SS_DIR"

if launchctl print "${DOMAIN}/${LABEL}" &>/dev/null; then
  launchctl bootout "${DOMAIN}/${LABEL}" 2>/dev/null || true
fi
launchctl unload "$PLIST_DEST" 2>/dev/null || true

if launchctl bootstrap "$DOMAIN" "$PLIST_DEST" 2>/dev/null; then
  launchctl enable "${DOMAIN}/${LABEL}" 2>/dev/null || true
  echo "==> Bootstrapped (${DOMAIN}/${LABEL})"
else
  launchctl load -w "$PLIST_DEST"
  echo "==> Loaded (legacy)"
fi

# Warm System Events auth: may prompt once for Automation (System Events)
# Running from the app binary path ties the prompt to "Clipboard Screenshot".
"$APP_EXEC" || true

echo
echo "Screenshot save location is unchanged (currently: $CURRENT_LOC)."
echo "New shots → moved to ~/Screenshots + clipboard."
echo
echo "If macOS asks to allow Automation for “${APP_NAME}” → System Events, click OK."
echo
echo "Logs:  tail -f $SS_DIR/watcher.log"
echo "Stop:  launchctl bootout ${DOMAIN}/${LABEL}"
echo "Uninstall: cd $(pwd) && ./uninstall.sh"
