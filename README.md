# clipboard-screenshot

New macOS screenshots → `~/Screenshots/` + clipboard. **Does not change your screenshot save location.**

Zero dependencies (launchd + zsh + osascript).

## Quick Start

```bash
git clone https://github.com/stevederico/clipboard-screenshot.git
cd clipboard-screenshot
./install.sh
```

Take a screenshot (`⌘⇧3` / `⌘⇧4`):

- File is **moved** off Desktop (or wherever macOS saves) into `~/Screenshots/`
- Image is copied to the clipboard
- Notification: **Screenshot Ready** → `⌘V` to paste

## Why not just watch Desktop with `find`?

launchd agents get TCC-blocked on `~/Desktop` (`Operation not permitted` for directory listing). Listing goes through **System Events** instead; open/stat/mv of known paths still works.

If macOS prompts **Clipboard Screenshot → System Events** (Automation), allow it once.

## How it works

1. Installs **`Clipboard Screenshot.app`** + launch agent `com.stevederico.clipboard-screenshot`
2. Watches your current `com.apple.screencapture` location (default: Desktop)
3. On new `Screenshot*` file: archive + clipboard

## Control

```bash
tail -f ~/Screenshots/watcher.log

launchctl bootout gui/$(id -u)/com.stevederico.clipboard-screenshot

cd clipboard-screenshot && ./install.sh   # reinstall
./uninstall.sh
```

## License

MIT
