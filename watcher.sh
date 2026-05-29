#!/bin/zsh
# grok-screenshot watcher
# Pure launchd-based macOS screenshot archiver + best-effort clipboard copier.
# Zero dependencies.

set -euo pipefail
unsetopt nomatch 2>/dev/null || true

GROK_DIR="${GROK_HOME:-$HOME/.grok}"
SS_DIR="$GROK_DIR/screenshots"
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

  # Pass path as argument to avoid quoting issues with special characters
  # in macOS screenshot filenames (e.g. narrow no-break space in " PM").
  local result
  result=$(osascript -e '
    on run {thePath}
      try
        set theFile to POSIX file thePath
        set the clipboard to (read theFile as «class PNGf»)
        return "ok"
      on error err
        return "fail: " & err
      end try
    end run' "$file" 2>&1)

  if [[ "$result" == "ok" ]]; then
    return 0
  else
    log "Clipboard error: $result"
    return 1
  fi
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
    show_notification "Screenshot ready for Grok" "Cmd+V in Grok • Moved to ~/.grok/screenshots"
  else
    log "Clipboard failed for $name"
    show_notification "Screenshot moved" "File: ~/.grok/screenshots/$(basename "$dest")"
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
