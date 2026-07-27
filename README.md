# clipboard-screenshot

New macOS screenshots → **clipboard only**. Files stay where macOS saved them (Desktop by default).

Does **not** change your screenshot location. Does **not** move or archive files.

## Quick Start

```bash
git clone https://github.com/stevederico/clipboard-screenshot.git
cd clipboard-screenshot
./install.sh
```

`⌘⇧3` / `⌘⇧4` → `⌘V`.

## Trigger (not a poll loop)

macOS has no public “screenshot taken” API. What exists:

| Mechanism | What it is |
|---|---|
| **launchd `WatchPaths`** | FSEvents-backed — kernel tells launchd the folder changed. **This is what we use.** |
| FSEvents (C/Swift) | Same events, lower level; needs a compiled binary |
| Folder Actions | Finder-side hooks; flaky on modern macOS |

We run once per Desktop change, copy the newest `Screenshot*`, exit. No 0.25s spin loop.

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
