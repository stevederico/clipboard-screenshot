#!/bin/zsh
# Installer for clipboard-screenshot
# Creates a named .app + launch agent; points screenshots at a TCC-safe inbox.

set -euo pipefail
setopt NULL_GLOB
unsetopt NOMATCH

SS_DIR="${SCREENSHOTS_DIR:-$HOME/Screenshots}"
INBOX_DIR="${SCREENSHOTS_INBOX:-$SS_DIR/Incoming}"
APP_NAME="Clipboard Screenshot"
APP_BUNDLE="${SS_DIR}/${APP_NAME}.app"
APP_EXEC="${APP_BUNDLE}/Contents/MacOS/clipboard-screenshot"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
LABEL="com.stevederico.clipboard-screenshot"
PLIST_NAME="${LABEL}.plist"
PLIST_DEST="$LAUNCH_AGENTS/$PLIST_NAME"
# Migrate off the old zsh-labeled agent if present
OLD_LABEL="com.clipboard-screenshot.watcher"
OLD_PLIST="$LAUNCH_AGENTS/${OLD_LABEL}.plist"
UID_NUM=$(id -u)
DOMAIN="gui/${UID_NUM}"
PREV_LOC_FILE="$SS_DIR/.previous-screencapture-location"

echo "==> Installing ${APP_NAME}"

mkdir -p "$INBOX_DIR" "$SS_DIR" "$HOME/Pictures/Screenshots"
chmod 755 "$SS_DIR" "$INBOX_DIR"

# Remember prior location once (for uninstall restore)
CURRENT_LOC=$(defaults read com.apple.screencapture location 2>/dev/null || echo "$HOME/Desktop")
CURRENT_LOC=${CURRENT_LOC/#\~/$HOME}
if [[ ! -f "$PREV_LOC_FILE" ]]; then
  echo "$CURRENT_LOC" > "$PREV_LOC_FILE"
fi

# Point macOS at the inbox (Desktop is TCC-blocked for launchd listing)
if [[ "$CURRENT_LOC" != "$INBOX_DIR" ]]; then
  defaults write com.apple.screencapture location "$INBOX_DIR"
  launchctl kickstart -k "${DOMAIN}/com.apple.SystemUIServer.agent" 2>/dev/null \
    || killall SystemUIServer 2>/dev/null \
    || true
  echo "==> Screenshot location → $INBOX_DIR"
else
  echo "==> Screenshot location already $INBOX_DIR"
fi

# One-time: sweep existing Desktop screenshots (install shell CAN list Desktop)
migrated=0
for f in "$HOME/Desktop"/Screenshot*(N) "$HOME/Desktop"/Screen\ Shot*(N); do
  [[ -f "$f" ]] || continue
  name=$(basename -- "$f")
  dest="$SS_DIR/$(date +%Y-%m-%d_%H-%M-%S)_migrated_$name"
  if mv "$f" "$dest" 2>/dev/null; then
    (( migrated++ )) || true
  fi
done
if (( migrated > 0 )); then
  echo "==> Migrated $migrated screenshot(s) from Desktop → $SS_DIR"
fi

# --- Named .app so System Settings / notifications / Activity Monitor
#     show "Clipboard Screenshot" instead of "zsh"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
cp -f "./watcher.sh" "$APP_EXEC"
chmod +x "$APP_EXEC"
# Keep a plain copy for manual runs / docs
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
    <string>1.1.0</string>
    <key>CFBundleVersion</key>
    <string>1.1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © Steve Derico</string>
</dict>
</plist>
PLIST

# PkgInfo marks it as an application package
printf 'APPL????' > "${APP_BUNDLE}/Contents/PkgInfo"

# Clear quarantine / force Launch Services to notice the name
xattr -dr com.apple.quarantine "$APP_BUNDLE" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_BUNDLE" 2>/dev/null || true

mkdir -p "$LAUNCH_AGENTS"

# Remove old agent that showed up as "zsh"
if [[ -f "$OLD_PLIST" ]] || launchctl print "${DOMAIN}/${OLD_LABEL}" &>/dev/null; then
  launchctl bootout "${DOMAIN}/${OLD_LABEL}" 2>/dev/null || true
  launchctl unload "$OLD_PLIST" 2>/dev/null || true
  rm -f "$OLD_PLIST" "$SS_DIR/watcher.sh.old"
  echo "==> Removed old zsh-labeled agent (${OLD_LABEL})"
fi

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
        <string>${INBOX_DIR}</string>
    </array>

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
        <key>SCREENSHOTS_INBOX</key>
        <string>${INBOX_DIR}</string>
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

echo "==> App:    $APP_BUNDLE"
echo "==> Agent:  $PLIST_DEST"
echo "    Inbox:  $INBOX_DIR"
echo "    Archive:$SS_DIR"

if launchctl print "${DOMAIN}/${LABEL}" &>/dev/null; then
  launchctl bootout "${DOMAIN}/${LABEL}" 2>/dev/null || true
fi
launchctl unload "$PLIST_DEST" 2>/dev/null || true

if launchctl bootstrap "$DOMAIN" "$PLIST_DEST" 2>/dev/null; then
  launchctl enable "${DOMAIN}/${LABEL}" 2>/dev/null || true
  echo "==> Bootstrapped as ${APP_NAME} (${DOMAIN}/${LABEL})"
else
  launchctl load -w "$PLIST_DEST"
  echo "==> Loaded (legacy launchctl load)"
fi

# Drain inbox
"$APP_EXEC" || true

echo
echo "System Settings → General → Login Items will show “${APP_NAME}” (not zsh)."
echo "Take a screenshot (⌘⇧3 / ⌘⇧4) → archive + clipboard."
echo
echo "Logs:  tail -f $SS_DIR/watcher.log"
echo "Stop:  launchctl bootout ${DOMAIN}/${LABEL}"
echo "Uninstall: cd $(pwd) && ./uninstall.sh"
