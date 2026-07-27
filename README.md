# clipboard-screenshot

New macOS screenshots → **clipboard only**. Files stay where macOS saved them (Desktop by default).

Does **not** change your screenshot location. Does **not** move or archive files.

## Quick Start

```bash
git clone https://github.com/stevederico/clipboard-screenshot.git
cd clipboard-screenshot
./install.sh
```

`⌘⇧3` / `⌘⇧4` → `⌘V` (usually within ~0.5s).

## Details

- Agent: **Clipboard Screenshot** (always-on poll, not slow WatchPaths cold-start)
- Support files: `~/Library/Application Support/com.stevederico.clipboard-screenshot/`
- May prompt once: Automation for System Events (needed to see Desktop under TCC)

```bash
tail -f ~/Library/Application\ Support/com.stevederico.clipboard-screenshot/watcher.log
launchctl bootout gui/$(id -u)/com.stevederico.clipboard-screenshot
./uninstall.sh
```

## License

MIT
