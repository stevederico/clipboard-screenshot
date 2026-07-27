# clipboard-screenshot

macOS screenshots → clipboard + `~/Screenshots/`. Zero dependencies.

## Quick Start

```bash
git clone https://github.com/stevederico/clipboard-screenshot.git
cd clipboard-screenshot
./install.sh
```

Take a screenshot (`⌘⇧3` / `⌘⇧4`):

- Saved to `~/Screenshots/Incoming` (install redirects macOS away from Desktop)
- Moved into `~/Screenshots/` with a timestamp prefix
- Copied to the clipboard
- Native notification: **Screenshot Ready**

`⌘V` to paste.

## Why not watch Desktop?

macOS TCC blocks launchd agents from **listing** `~/Desktop` (`Operation not permitted`). Watching Desktop is a dead end without Full Disk Access on `/bin/zsh`.

Install instead points `com.apple.screencapture location` at `~/Screenshots/Incoming` (allowed for agents). Uninstall restores the previous location.

## How it works

1. `install.sh` sets screenshot location → `~/Screenshots/Incoming`
2. Installs **`Clipboard Screenshot.app`** (so System Settings shows that name, not `zsh`)
3. launchd `WatchPaths` fires on the inbox
4. App waits for a stable file, moves it to `~/Screenshots/YYYY-MM-DD_HH-MM-SS_…`
5. Copies PNG to the pasteboard via `osascript` (no System Events / Automation prompt)
6. Notifies

Agent label: `com.stevederico.clipboard-screenshot`

## Control

```bash
tail -f ~/Screenshots/watcher.log

# Stop
launchctl bootout gui/$(id -u)/com.stevederico.clipboard-screenshot

# Start again
cd clipboard-screenshot && ./install.sh

# Uninstall (restores prior screenshot location)
./uninstall.sh
```

## Requirements

- macOS (tested on Sequoia)
- No Homebrew, no fswatch, no third-party binaries

## License

MIT
