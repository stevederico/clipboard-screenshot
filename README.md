# clipboard-screenshot

<p align="center">
  <img src="assets/banner.jpg" alt="clipboard-screenshot — macOS screenshots to clipboard" width="100%">
</p>

**Every new macOS screenshot is copied to your clipboard automatically.**

`⌘⇧3` / `⌘⇧4` → `⌘V`

macOS won’t save a file **and** put the image on the clipboard with the same shortcut. This fills that gap: your usual shortcuts still save a file; this tool copies that image to the pasteboard as soon as the file appears so you can paste.

Does **not** move, rename, or delete screenshots. Zero dependencies — `launchd`, `zsh`, `osascript`.

## Install

```bash
git clone https://github.com/stevederico/clipboard-screenshot.git
cd clipboard-screenshot
./install.sh
```

No Full Disk Access. The agent finds new shots via Spotlight (`mdfind`) so it can watch Desktop under TCC without listing the folder.

### Uninstall

```bash
./uninstall.sh
```

Stops the agent, removes support files, and restores your previous floating-thumbnail setting.

## How it works

1. **launchd `WatchPaths`** — runs when your screenshot folder changes (FSEvents; not a poll loop).
2. Watches `defaults read com.apple.screencapture location` (Desktop by default).
3. Resolves the newest `Screenshot*` / `Screen Shot*` via **`mdfind`** (launchd cannot `readdir` Desktop under TCC; no FDA).
4. Copies it to the pasteboard as **PNG** (via JXA / `osascript`) when mtime is newer than the last successful copy.
5. Notification: **Screenshot Ready** · Cmd+V to paste.

### Floating thumbnail

Install turns **off** the bottom-right screenshot preview. That UI delays writing the file to disk, so nothing can hit the clipboard until it goes away — and there’s no public API for the preview buffer. That setting is what makes paste feel instant. Uninstall restores your prior preference.

```bash
# turn the preview back on yourself
defaults write com.apple.screencapture show-thumbnail -bool true
killall SystemUIServer
```

## Control

```bash
# Logs
tail -f ~/Library/Application\ Support/com.stevederico.clipboard-screenshot/watcher.log

# Stop
launchctl bootout gui/$(id -u)/com.stevederico.clipboard-screenshot

# Start again
./install.sh
```

| | |
|---|---|
| Agent | **Clipboard Screenshot** (`com.stevederico.clipboard-screenshot`) |
| App / state | `~/Library/Application Support/com.stevederico.clipboard-screenshot/` |

## Requirements

- macOS (tested on Sequoia)
- Spotlight indexing on (default) — used to resolve Desktop paths under TCC
- Default screenshot **names** (`Screenshot …` / `Screen Shot …`)
- Screenshot **type** PNG (macOS default) — clipboard copy uses PNG pasteboard data

## Built-in alternative

Clipboard only, no file: `⌘⌃⇧3` / `⌘⌃⇧4`.

## License

[MIT](LICENSE) © Steve Derico
