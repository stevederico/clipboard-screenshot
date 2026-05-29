# grok-screenshot

Automatically move macOS screenshots off your Desktop into a clean, timestamped archive — and (best-effort) put them on your clipboard.

**Zero dependencies.** No Homebrew, no fswatch, no third-party binaries.

This exists because macOS still defaults to dumping every screenshot on your Desktop, and apparently no one has ever wanted that.

## 🚀 Quick Start

```bash
git clone https://github.com/yourname/grok-screenshot.git
cd grok-screenshot
./install.sh
```

Take any screenshot (Cmd+Shift+4 or Cmd+Shift+5).

- The screenshot is **moved** off your Desktop into `~/.grok/screenshots/`
- It is placed on your clipboard (best effort)
- You get a native macOS notification

Open Grok and hit **Cmd+V**.

That's it. No Homebrew. No extra tools. No configuration.

## Features

### Desktop Cleanup
- Automatically **moves** screenshots off your Desktop (or custom location) the instant they are taken
- No more screenshot clutter

### Organized Archive
- Saves every screenshot into `~/.grok/screenshots/` with a clean, sortable timestamp prefix
- Example filename: `2026-05-29_13-41-22_Screenshot 2026-05-29 at 1.41.15 PM.png`

### Clipboard Integration (Best Effort)
- Tries to put the image on your clipboard automatically so you can Cmd+V right away
- Uses a robust AppleScript method that handles macOS's weird filename characters (like the narrow no-break space in " PM")

### Native Notifications
- Shows a macOS notification when a screenshot is successfully processed
- Shows a different notification (with file location) if the clipboard step fails

### Smart & Reliable Behavior
- Dynamically detects your current screenshot save location (`defaults read com.apple.screencapture location`)
- Only acts on files that match macOS screenshot naming patterns
- Ignores very small files
- Prevents duplicate processing using a state file
- Handles launchd firing multiple times for the same screenshot (debouncing)

### Zero Dependencies
- Pure native macOS tools: `launchd`, `zsh`, and `osascript`
- No Homebrew, no fswatch, no extra binaries

### Grok Integration
- Includes an optional skill (`skill/SKILL.md`) so you can ask Grok about your recent screenshots

Solves the eternal complaint: "Why does macOS still save screenshots to the Desktop?"

## Installation

See the Quick Start above. The `./install.sh` script handles everything.

## How it works

1. A lightweight `launchd` agent (using `WatchPaths`) watches your current screenshot folder(s).
2. When a new screenshot is detected, the watcher script runs.
3. It validates the file, then **moves** it into `~/.grok/screenshots/` with a timestamped name.
4. It attempts to copy the image to your clipboard.
5. You receive a native macOS notification.

Your Desktop stays clean automatically. All your screenshots are neatly organized in one place.

## Known Limitations

**Clipboard is best-effort** (this is the hardest part on modern macOS):

- Reliably setting the clipboard from a launchd-triggered process is flaky due to permissions and sandboxing.
- When clipboard fails, the file is still moved cleanly and you get a notification with the location.

The main value of this tool is **getting screenshots off your Desktop automatically** into an organized folder. The clipboard part is a nice-to-have.

## Configuration

If you change where macOS saves screenshots:

```bash
defaults write com.apple.screencapture location ~/Pictures/Screenshots
killall SystemUIServer
```

Then re-run `./install.sh`.

## Control

```bash
# View logs
tail -f ~/.grok/screenshots/watcher.log

# Stop the watcher
launchctl unload ~/Library/LaunchAgents/com.grok-screenshot.watcher.plist

# Start it again
launchctl load -w ~/Library/LaunchAgents/com.grok-screenshot.watcher.plist
```

## Uninstall

```bash
cd grok-screenshot
./uninstall.sh
```

## Grok Skill (Optional)

There's also a small skill included in `skill/SKILL.md` that lets Grok reference your moved screenshots easily.

## Philosophy

This project exists because macOS still defaults to dumping every screenshot on your Desktop in 2026, and almost nobody wants that.

It deliberately stays dependency-free so it can run via launchd with zero extra tools.

## Contributing

Issues and pull requests are welcome. Please keep changes in the spirit of minimalism and zero dependencies.

## License

MIT
