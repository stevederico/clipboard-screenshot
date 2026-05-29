#!/bin/zsh
# Installer for grok-screenshot
# Creates the launch agent with correct paths for the current user.

set -euo pipefail

GROK_DIR="${GROK_HOME:-$HOME/.grok}"
SS_DIR="$GROK_DIR/screenshots"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
LABEL="com.grok.screenshot-watcher"
PLIST_NAME="${LABEL}.plist"
PLIST_DEST="$LAUNCH_AGENTS/$PLIST_NAME"

echo "==> Installing grok-screenshot watcher (zero dependencies)"

mkdir -p "$HOME/Desktop" "$HOME/Pictures/Screenshots"
mkdir -p "$SS_DIR"
chmod 755 "$SS_DIR"

# Copy the watcher script into place
cp -f "./watcher.sh" "$SS_DIR/watcher.sh"
chmod +x "$SS_DIR/watcher.sh"

# Generate the launchd plist with correct absolute paths
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
        <string>${SS_DIR}/watcher.sh</string>
    </array>

    <key>WatchPaths</key>
    <array>
        <string>${HOME}/Desktop</string>
        <string>${HOME}/Pictures/Screenshots</string>
    </array>

    <key>ThrottleInterval</key>
    <integer>1</integer>

    <key>RunAtLoad</key>
    <false/>
    <key>KeepAlive</key>
    <false/>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin</string>
        <key>GROK_HOME</key>
        <string>${GROK_DIR}</string>
    </dict>

    <key>StandardOutPath</key>
    <string>${SS_DIR}/watcher.log</string>
    <key>StandardErrorPath</key>
    <string>${SS_DIR}/watcher.log</string>
</dict>
</plist>
EOF

chmod 644 "$PLIST_DEST"

echo "==> Launch agent created: $PLIST_DEST"

# Reload
launchctl unload "$PLIST_DEST" 2>/dev/null || true
launchctl load -w "$PLIST_DEST"

echo "==> Watcher installed and activated."

echo
echo "Take a screenshot. It will be moved off your Desktop automatically."
echo "Screenshots live in: $SS_DIR"
echo
echo "View logs: tail -f $SS_DIR/watcher.log"
echo "Stop:      launchctl unload $PLIST_DEST"
echo "Uninstall: cd $(pwd) && ./uninstall.sh"
