#!/bin/zsh
# Installer for clipboard-screenshot
# Creates the launch agent + points macOS screenshots at a TCC-safe inbox.

set -euo pipefail
setopt NULL_GLOB
unsetopt NOMATCH

SS_DIR="${SCREENSHOTS_DIR:-$HOME/Screenshots}"
INBOX_DIR="${SCREENSHOTS_INBOX:-$SS_DIR/Incoming}"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
LABEL="com.clipboard-screenshot.watcher"
PLIST_NAME="${LABEL}.plist"
PLIST_DEST="$LAUNCH_AGENTS/$PLIST_NAME"
UID_NUM=$(id -u)
DOMAIN="gui/${UID_NUM}"
PREV_LOC_FILE="$SS_DIR/.previous-screencapture-location"

echo "==> Installing clipboard-screenshot (zero dependencies)"

mkdir -p "$INBOX_DIR" "$SS_DIR" "$HOME/Pictures/Screenshots"
chmod 755 "$SS_DIR" "$INBOX_DIR"

# Remember prior location once (for uninstall restore)
CURRENT_LOC=$(defaults read com.apple.screencapture location 2>/dev/null || echo "$HOME/Desktop")
CURRENT_LOC=${CURRENT_LOC/#\~/$HOME}
if [[ ! -f "$PREV_LOC_FILE" ]]; then
  echo "$CURRENT_LOC" > "$PREV_LOC_FILE"
fi

# Point macOS at the inbox. Desktop is TCC-blocked for launchd agents
# ("Operation not permitted" on directory listing) — watching Desktop cannot work.
if [[ "$CURRENT_LOC" != "$INBOX_DIR" ]]; then
  defaults write com.apple.screencapture location "$INBOX_DIR"
  # Prefer kickstart over killall when available
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

cp -f "./watcher.sh" "$SS_DIR/watcher.sh"
chmod +x "$SS_DIR/watcher.sh"

mkdir -p "$LAUNCH_AGENTS"

cat > "$PLIST_DEST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string>${SS_DIR}/watcher.sh</string>
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

echo "==> Launch agent: $PLIST_DEST"
echo "    Inbox:   $INBOX_DIR"
echo "    Archive: $SS_DIR"

if launchctl print "${DOMAIN}/${LABEL}" &>/dev/null; then
  launchctl bootout "${DOMAIN}/${LABEL}" 2>/dev/null || true
fi
launchctl unload "$PLIST_DEST" 2>/dev/null || true

if launchctl bootstrap "$DOMAIN" "$PLIST_DEST" 2>/dev/null; then
  launchctl enable "${DOMAIN}/${LABEL}" 2>/dev/null || true
  echo "==> Watcher bootstrapped (${DOMAIN}/${LABEL})"
else
  launchctl load -w "$PLIST_DEST"
  echo "==> Watcher loaded (legacy launchctl load)"
fi

# Drain anything already in the inbox
/bin/zsh "$SS_DIR/watcher.sh" || true

echo
echo "Take a screenshot (⌘⇧3 / ⌘⇧4)."
echo "  → lands in $INBOX_DIR"
echo "  → moved to $SS_DIR + clipboard"
echo
echo "Logs:  tail -f $SS_DIR/watcher.log"
echo "Stop:  launchctl bootout ${DOMAIN}/${LABEL}"
echo "Uninstall: cd $(pwd) && ./uninstall.sh"
