---
name: screenshots
description: macOS screenshots land on the clipboard automatically. Use when the user mentions a recent screenshot, "what I just captured", or wants to paste/discuss the latest capture.
---

# Screenshots (clipboard)

`clipboard-screenshot` copies each new screenshot to the system clipboard. **Files stay on Desktop** (or whatever macOS save location the user set). Nothing is archived.

## Usage

1. User takes `⌘⇧3` / `⌘⇧4`
2. After a moment they can `⌘V` (image is on the clipboard)
3. File remains where macOS saved it — typically `~/Desktop/Screenshot ….png`

## Logs

```bash
tail -f ~/Library/Application\ Support/com.stevederico.clipboard-screenshot/watcher.log
```

## Recent files on Desktop

```bash
ls -1t ~/Desktop/Screenshot* 2>/dev/null | head -10
```
