#!/bin/zsh
# clipboard-screenshot — put new screenshots on the clipboard (files stay put).
# Fast path: long-running poll (KeepAlive), newest file only, one clipboard write.
# Zero deps: zsh + osascript + launchd.

set -euo pipefail
setopt NULL_GLOB EXTENDED_GLOB
unsetopt NOMATCH

SUPPORT_DIR="${CLIPBOARD_SCREENSHOT_HOME:-$HOME/Library/Application Support/com.stevederico.clipboard-screenshot}"
mkdir -p "$SUPPORT_DIR"
STATE_FILE="$SUPPORT_DIR/last-processed"
LOG_FILE="$SUPPORT_DIR/watcher.log"
LOCK_DIR="$SUPPORT_DIR/watcher.lock"
POLL_SEC="${CLIPBOARD_SCREENSHOT_POLL:-0.25}"
DAEMON=0
[[ "${1:-}" == "--daemon" ]] && DAEMON=1

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Single instance
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  if [[ -d "$LOCK_DIR" ]]; then
    lock_age=$(( $(date +%s) - $(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0) ))
    if (( lock_age > 60 )); then
      rmdir "$LOCK_DIR" 2>/dev/null || true
      mkdir "$LOCK_DIR" 2>/dev/null || exit 0
    else
      exit 0
    fi
  else
    exit 0
  fi
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT INT TERM

get_ss_location() {
  local loc
  loc=$(defaults read com.apple.screencapture location 2>/dev/null || echo "$HOME/Desktop")
  loc=${loc/#\~/$HOME}
  loc=${loc%/}
  [[ -d "$loc" ]] && echo "$loc" || echo "$HOME/Desktop"
}

# One System Events call: newest Screenshot* path only (by modification date).
newest_screenshot() {
  local dir="$1"
  osascript - "$dir" <<'APPLESCRIPT' 2>/dev/null || true
on run argv
  set dirPath to item 1 of argv
  try
    tell application "System Events"
      set theFolder to folder dirPath
      set shots to every file of theFolder whose name starts with "Screenshot" or name starts with "Screen Shot"
      if (count of shots) is 0 then return ""
      set best to item 1 of shots
      set bestDate to modification date of best
      repeat with f in shots
        set d to modification date of f
        if d > bestDate then
          set bestDate to d
          set best to f
        end if
      end repeat
      return POSIX path of best
    end tell
  on error
    return ""
  end try
end run
APPLESCRIPT
}

# Ready enough: exists and >4KB. One short retry if still tiny (write in progress).
file_ready() {
  local file="$1" size
  [[ -f "$file" ]] || return 1
  size=$(stat -f %z "$file" 2>/dev/null || echo 0)
  if (( size > 4096 )); then
    return 0
  fi
  sleep 0.08
  [[ -f "$file" ]] || return 1
  size=$(stat -f %z "$file" 2>/dev/null || echo 0)
  (( size > 4096 ))
}

# Single fast clipboard write (JXA / AppKit — no System Events, no retries by default)
put_image_on_clipboard() {
  local file="$1"
  [[ -f "$file" ]] || return 1

  local out
  out=$(osascript -l JavaScript - "$file" <<'JXA' 2>&1
function run(argv) {
  ObjC.import("AppKit");
  ObjC.import("Foundation");
  var data = $.NSData.dataWithContentsOfFile(argv[0]);
  if (!data || data.length === 0) return "fail:read";
  var pb = $.NSPasteboard.generalPasteboard;
  pb.clearContents;
  return pb.setDataForType(data, $.NSPasteboardTypePNG) ? "ok" : "fail:set";
}
JXA
)
  if [[ "$out" == "ok" ]]; then
    return 0
  fi

  # Fallback once
  out=$(osascript - "$file" <<'APPLESCRIPT' 2>&1
on run argv
  try
    set the clipboard to (read (POSIX file (item 1 of argv)) as «class PNGf»)
    return "ok"
  on error errMsg
    return "fail:" & errMsg
  end try
end run
APPLESCRIPT
)
  [[ "$out" == "ok" ]]
}

notify() {
  # Don't block the hot path on notification
  osascript -e "display notification \"$2\" with title \"$1\"" &>/dev/null &
}

already_processed() {
  local name="$1"
  [[ -f "$STATE_FILE" ]] || return 1
  grep -Fqx -- "$name" "$STATE_FILE" 2>/dev/null
}

mark_processed() {
  local name="$1"
  {
    echo "$name"
    grep -Fvx -- "$name" "$STATE_FILE" 2>/dev/null | head -20 || true
  } > "${STATE_FILE}.tmp"
  mv -f "${STATE_FILE}.tmp" "$STATE_FILE"
}

is_recent() {
  local file="$1" mtime now
  mtime=$(stat -f %m "$file" 2>/dev/null || echo 0)
  now=$(date +%s)
  # Only brand-new captures (2 min) — avoids re-touching old Desktop shots
  (( now - mtime >= 0 && now - mtime < 120 ))
}

tick() {
  local watch src name

  watch=$(get_ss_location)
  src=$(newest_screenshot "$watch")
  src=${src//$'\r'/}
  src=${src//$'\n'/}

  if [[ -z "$src" || ! -f "$src" ]]; then
    return 0
  fi

  name=$(basename -- "$src")
  already_processed "$name" && return 0
  is_recent "$src" || return 0
  file_ready "$src" || return 0
  already_processed "$name" && return 0

  if put_image_on_clipboard "$src"; then
    mark_processed "$name"
    log "clipboard: $name"
    notify "Screenshot Ready" "Cmd+V to paste"
  else
    log "clipboard failed: $name"
  fi
}

if (( DAEMON )); then
  log "daemon start (poll ${POLL_SEC}s)"
  # Small initial delay so launchd finishes bootstrap
  sleep 0.1
  while true; do
    tick || true
    sleep "$POLL_SEC"
  done
else
  # One-shot (manual / install warm-up)
  tick || true
fi
