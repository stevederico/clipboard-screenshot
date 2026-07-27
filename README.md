# clipboard-screenshot

<p align="center">
  <img src="assets/banner.jpg" alt="clipboard-screenshot — macOS screenshots to clipboard" width="100%">
</p>

**Every new macOS screenshot is copied to your clipboard automatically.**

`⌘⇧3` / `⌘⇧4` → `⌘V`

macOS won’t save a file **and** put the image on the clipboard at the same time. This fills that gap: your normal screenshot shortcuts still save a file; this tool immediately copies that image so you can paste.

Zero dependencies — `launchd`, `zsh`, and `osascript` only.

## Install

```bash
git clone https://github.com/stevederico/clipboard-screenshot.git
cd clipboard-screenshot
./install.sh
```

If macOS asks to allow **Clipboard Screenshot → System Events**, click **OK** (needed to see new files on the Desktop under TCC).

### Uninstall

```bash
./uninstall.sh
```

## How it works

1. **launchd `WatchPaths`** fires when a new screenshot file appears (FSEvents, not a poll loop).
2. Finds the newest `Screenshot*` / `Screen Shot*` file.
3. Copies the PNG to the system pasteboard.
4. Optional notification: **Screenshot Ready**.

### Floating thumbnail

Install turns off the bottom-right screenshot preview. That UI **delays writing the file to disk**, so the clipboard can’t update until it disappears — and there’s no public API for the preview buffer. Uninstall restores your previous setting.

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

Agent: **Clipboard Screenshot** (`com.stevederico.clipboard-screenshot`)  
Support files: `~/Library/Application Support/com.stevederico.clipboard-screenshot/`

## Requirements

- macOS (tested on Sequoia)
- Automation permission for System Events when prompted
- Default screenshot filenames (`Screenshot …` / `Screen Shot …`)

## Built-in alternative

Clipboard only, no file: `⌘⌃⇧3` / `⌘⌃⇧4`.

## License

[MIT](LICENSE) © Steve Derico
