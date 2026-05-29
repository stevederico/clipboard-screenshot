---
name: screenshots
description: Access automatically moved macOS screenshots. Use when the user mentions recent screenshots, "what did I just capture", "the screenshot I took", or wants to discuss something visible on their screen.
---

# Screenshot Archive Skill

You have access to screenshots that have been automatically moved off the user's Desktop by clipboard-screenshot.

## Location
`~/Screenshots/` (or set SCREENSHOTS_DIR)

Files are named `YYYY-MM-DD_HH-MM-SS_originalname.png`.

## Usage

1. List recent screenshots:
   ```bash
   ls -1t ~/Screenshots/*.png | head -15
   ```

2. Attach one using the normal file syntax:
   ```
   @~/Screenshots/2025-05-29_14-22-03_Screenshot.png
   ```

The watcher already tries to put the latest screenshot on the system clipboard, so the user can often just hit Cmd+V.

## Suggested Commands

- "Show my last few screenshots"
- "What was the last thing I screenshotted?"
- "Describe the screenshot from a minute ago"
