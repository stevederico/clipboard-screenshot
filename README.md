# clipboard-screenshot

New macOS screenshots → **clipboard only**. Files stay where macOS saved them (Desktop by default).

Does **not** change your screenshot location. Does **not** move or archive files.

## Quick Start

```bash
git clone https://github.com/stevederico/clipboard-screenshot.git
cd clipboard-screenshot
./install.sh
```

`⌘⇧3` / `⌘⇧4` → `⌘V` immediately.

## Why we disable the floating thumbnail

That bottom-right preview **holds the PNG in limbo** until it dismisses — nothing reliable is on disk yet, so nothing can hit the clipboard. macOS exposes **no API** for that in-memory preview.

Install turns **off** `show-thumbnail` so the file writes to Desktop right away; we copy from there. Uninstall restores your prior setting.

(⌘⌃⇧3 / ⌘⌃⇧4 = system “clipboard only”, no file — different feature.)

## Trigger

| Mechanism | Notes |
|---|---|
| **launchd `WatchPaths`** | FSEvents when Desktop gets the new file — **what we use** |
| FSEvents (C/Swift) | Same events, needs a binary |
| “Screenshot taken” API | **Does not exist** publicly |

## Details

- Agent: **Clipboard Screenshot** (`com.stevederico.clipboard-screenshot`)
- Support files: `~/Library/Application Support/com.stevederico.clipboard-screenshot/`
- May prompt once: Automation → System Events (list Desktop under TCC)

```bash
tail -f ~/Library/Application\ Support/com.stevederico.clipboard-screenshot/watcher.log
launchctl bootout gui/$(id -u)/com.stevederico.clipboard-screenshot
./uninstall.sh
```

## License

MIT
