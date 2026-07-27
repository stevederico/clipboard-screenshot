#!/bin/zsh
# clipboard-screenshot — copy new screenshots to the clipboard (files stay put).
# Triggered by launchd WatchPaths (FS event).
# Zero deps: zsh + osascript + launchd.
#
# Race we fix: WatchPaths often fires BEFORE the new PNG is visible to
# System Events. Naively copying "newest" then re-pastes the *previous*
# shot (or leaves it on the clipboard). We wait for mtime > last success.

set -euo pipefail
setopt NULL_GLOB EXTENDED_GLOB
unsetopt NOMATCH

SUPPORT_DIR="${CLIPBOARD_SCREENSHOT_HOME:-$HOME/Library/Application Support/com.stevederico.clipboard-screenshot}"
mkdir -p "$SUPPORT_DIR"
STATE_FILE="$SUPPORT_DIR/last-processed"
MTIME_FILE="$SUPPORT_DIR/last-mtime"
LOG_FILE="$SUPPORT_DIR/watcher.log"
LOCK_DIR="$SUPPORT_DIR/watcher.lock"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Overlapping fires: wait for the in-flight run (it may still be waiting for the new PNG)
got_lock=0
for _ in {1..60}; do
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    got_lock=1
    break
  fi
  # Stale lock (>20s) — steal
  if [[ -d "$LOCK_DIR" ]]; then
    lock_age=$(( $(date +%s) - $(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0) ))
    if (( lock_age > 20 )); then
      rmdir "$LOCK_DIR" 2>/dev/null || true
      continue
    fi
  fi
  sleep 0.05
done
(( got_lock )) || exit 0
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT INT TERM

get_ss_location() {
  local loc
  loc=$(defaults read com.apple.screencapture location 2>/dev/null || echo "$HOME/Desktop")
  loc=${loc/#\~/$HOME}
  loc=${loc%/}
  [[ -d "$loc" ]] && echo "$loc" || echo "$HOME/Desktop"
}

# Newest Screenshot* path via System Events (TCC-safe Desktop listing)
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

# Size > 4KB and stable across two samples (avoid mid-write)
file_ready() {
  local file="$1" a b
  [[ -f "$file" ]] || return 1
  a=$(stat -f %z "$file" 2>/dev/null || echo 0)
  (( a > 4096 )) || return 1
  sleep 0.04
  [[ -f "$file" ]] || return 1
  b=$(stat -f %z "$file" 2>/dev/null || echo 0)
  (( b > 4096 && b == a ))
}

put_image_on_clipboard() {
  local file="$1" out
  [[ -f "$file" ]] || return 1

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
  osascript -e "display notification \"$2\" with title \"$1\"" &>/dev/null &
}

mark_done() {
  local name="$1" mtime="$2"
  echo "$mtime" > "$MTIME_FILE"
  {
    echo "$name"
    grep -Fvx -- "$name" "$STATE_FILE" 2>/dev/null | head -20 || true
  } > "${STATE_FILE}.tmp"
  mv -f "${STATE_FILE}.tmp" "$STATE_FILE"
}

# Core: wait for a screenshot NEWER than last success, then copy that only.
try_copy_new() {
  local watch src name mtime last attempt
  local max_attempts=40   # * ~0.08s ≈ 3.2s for file to appear after event
  local delay=0.08

  last=$(cat "$MTIME_FILE" 2>/dev/null || echo 0)
  # guard non-numeric
  [[ "$last" == <-> ]] || last=0

  watch=$(get_ss_location)
  log "event (watch=$watch last_mtime=$last)"

  for attempt in {1..$max_attempts}; do
    src=$(newest_screenshot "$watch")
    src=${src//$'\r'/}
    src=${src//$'\n'/}

    if [[ -n "$src" && -f "$src" ]]; then
      mtime=$(stat -f %m "$src" 2>/dev/null || echo 0)
      name=$(basename -- "$src")

      # Key: only touch clipboard when this file is newer than last copy
      if (( mtime > last )) && file_ready "$src"; then
        # Re-stat after ready (thumbnail may rewrite)
        mtime=$(stat -f %m "$src" 2>/dev/null || echo 0)
        if put_image_on_clipboard "$src"; then
          mark_done "$name" "$mtime"
          log "clipboard: $name (mtime=$mtime attempt=$attempt)"
          notify "Screenshot Ready" "Cmd+V to paste"
          return 0
        fi
        log "clipboard failed: $name"
        return 1
      fi
    fi
    sleep $delay
  done

  log "no newer screenshot within timeout (last_mtime=$last)"
  return 0
}

try_copy_new || true
