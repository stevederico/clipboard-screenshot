#!/bin/zsh
# clipboard-screenshot
# Pure launchd-based macOS screenshot archiver + best-effort clipboard copier.
# Zero dependencies.

set -euo pipefail
unsetopt nomatch 2>/dev/null || true

# Default storage location for moved screenshots.
# Can be overridden with SCREENSHOTS_DIR environment variable.
SS_DIR="${SCREENSHOTS_DIR:-$HOME/Screenshots}"
mkdir -p "$SS_DIR"
STATE_FILE="$SS_DIR/.last-processed"
LOG_FILE="$SS_DIR/watcher.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

get_current_ss_dir() {
  local loc
  loc=$(defaults read com.apple.screencapture location 2>/dev/null || echo "$HOME/Desktop")
  loc=${loc/#\~/$HOME}
  loc=${loc%/}
  echo "$loc"
}

put_image_on_clipboard() {
  local file="$1"
  [[ -f "$file" ]] || return 1

  local max_attempts=3
  local delay=0.35

  for attempt in {1..$max_attempts}; do
    # Strategy 1: Use System Events + argument passing (often most reliable)
    local res1
    res1=$(osascript -e '
      on run {thePath}
        try
          tell application "System Events"
            set the clipboard to (read (POSIX file thePath) as «class PNGf»)
          end tell
          return "ok"
        on error err
          return "fail1: " & err
        end try
      end run' "$file" 2>&1)

    if [[ "$res1" == "ok" ]]; then
      return 0
    fi

    # Strategy 2: Alternative phrasing ("PNG picture")
    local res2
    res2=$(osascript -e '
      on run {thePath}
        try
          set the clipboard to (read (POSIX file thePath) as PNG picture)
          return "ok"
        on error err
          return "fail2: " & err
        end try
      end run' "$file" 2>&1)

    if [[ "$res2" == "ok" ]]; then
      return 0
    fi

    if [[ $attempt -lt $max_attempts ]]; then
      sleep $delay
    fi
  done

  log "Clipboard failed after $max_attempts attempts. Last errors: $res1 | $res2"
  return 1
}

show_notification() {
  local title="$1"
  local message="$2"
  osascript -e "
    display notification \"$message\" with title \"$title\" sound name \"Glass\"
  " 2>/dev/null || true
}

process_file() {
  local src="$1"
  [[ -f "$src" ]] || return 0

  local name
  name=$(basename "$src")

  if [[ "$name" != *(S|s)creenshot* && "$name" != *(S|s)creen\ Shot* ]]; then
    return 0
  fi

  local size
  size=$(stat -f %z "$src" 2>/dev/null || echo 0)
  (( size > 4096 )) || return 0

  local dest="$SS_DIR/$(date +%Y-%m-%d_%H-%M-%S)_$name"
  [[ -e "$dest" ]] && return 0

  mv "$src" "$dest" 2>/dev/null || return 0
  log "Moved: $name"

  if put_image_on_clipboard "$dest"; then
    log "On clipboard: $name"
    show_notification "Screenshot ready" "Cmd+V • Moved to ~/Screenshots"
  else
    log "Clipboard failed for $name"
    show_notification "Screenshot moved" "File: ~/Screenshots/$(basename "$dest")"
  fi

  echo "$name" > "$STATE_FILE"
}

# === Main ===

CURRENT_DIR=$(get_current_ss_dir)
last_processed=$(cat "$STATE_FILE" 2>/dev/null || echo "")

newest=$(ls -1t "$CURRENT_DIR"/Screenshot*.png(N) "$CURRENT_DIR"/Screen\ Shot*.png(N) 2>/dev/null | head -1)

if [[ -n "$newest" && -f "$newest" ]]; then
  name=$(basename "$newest")
  if find "$newest" -mmin -5 >/dev/null 2>&1; then
    if [[ "$name" != "$last_processed" ]] && [[ "$name" == *(S|s)creenshot* || "$name" == *(S|s)creen\ Shot* ]]; then
      process_file "$newest"
    fi
  fi
fi
