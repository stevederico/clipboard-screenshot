#!/bin/zsh
# clipboard-screenshot
# launchd agent: put new macOS screenshots on the clipboard.
# Leaves files where macOS saved them (usually Desktop). No archive folder.
# Zero dependencies: zsh + osascript + launchd.
#
# Listing Desktop: launchd cannot readdir ~/Desktop (TCC). System Events can.
# open/stat of a known path still works.

set -euo pipefail
setopt NULL_GLOB EXTENDED_GLOB
unsetopt NOMATCH

SUPPORT_DIR="${CLIPBOARD_SCREENSHOT_HOME:-$HOME/Library/Application Support/com.stevederico.clipboard-screenshot}"
mkdir -p "$SUPPORT_DIR"
STATE_FILE="$SUPPORT_DIR/last-processed"
LOG_FILE="$SUPPORT_DIR/watcher.log"
LOCK_DIR="$SUPPORT_DIR/watcher.lock"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  if [[ -d "$LOCK_DIR" ]]; then
    lock_age=$(( $(date +%s) - $(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0) ))
    if (( lock_age > 30 )); then
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

list_screenshots() {
  local dir="$1"

  osascript - "$dir" <<'APPLESCRIPT' 2>/dev/null || true
on run argv
  set dirPath to item 1 of argv
  set out to {}
  try
    tell application "System Events"
      set theFolder to folder dirPath
      set theFiles to every file of theFolder
      repeat with f in theFiles
        set n to name of f as text
        if n starts with "Screenshot" or n starts with "Screen Shot" or n starts with "screenshot" or n starts with "screen shot" then
          set end of out to POSIX path of f
        end if
      end repeat
    end tell
  on error
    return ""
  end try
  set AppleScript's text item delimiters to linefeed
  return out as text
end run
APPLESCRIPT
}

wait_for_stable_file() {
  local file="$1"
  local max_wait=40
  local last_size=-1
  local stable=0
  local i size

  for i in {1..$max_wait}; do
    [[ -f "$file" ]] || { sleep 0.25; continue; }
    size=$(stat -f %z "$file" 2>/dev/null || echo 0)
    if (( size > 4096 )); then
      if (( size == last_size )); then
        (( ++stable ))
        if (( stable >= 2 )); then
          return 0
        fi
      else
        stable=0
        last_size=$size
      fi
    fi
    sleep 0.25
  done
  return 1
}

put_image_on_clipboard() {
  local file="$1"
  [[ -f "$file" ]] || return 1

  local max_attempts=4
  local delay=0.4
  local attempt out

  for attempt in {1..$max_attempts}; do
    out=$(osascript - "$file" <<'APPLESCRIPT' 2>&1
on run argv
  set p to item 1 of argv
  try
    set the clipboard to (read (POSIX file p) as «class PNGf»)
    return "ok"
  on error errMsg number errNum
    return "fail:" & errNum & ":" & errMsg
  end try
end run
APPLESCRIPT
)

    if [[ "$out" == "ok" ]]; then
      return 0
    fi

    out=$(osascript -l JavaScript - "$file" <<'JXA' 2>&1
function run(argv) {
  ObjC.import("AppKit");
  ObjC.import("Foundation");
  var path = argv[0];
  var data = $.NSData.dataWithContentsOfFile(path);
  if (!data || data.length === 0) return "fail:read";
  var pb = $.NSPasteboard.generalPasteboard;
  pb.clearContents;
  var ok = pb.setDataForType(data, $.NSPasteboardTypePNG);
  return ok ? "ok" : "fail:set";
}
JXA
)

    if [[ "$out" == "ok" ]]; then
      return 0
    fi

    log "Clipboard attempt $attempt failed: $out"
    if (( attempt < max_attempts )); then
      sleep $delay
    fi
  done

  return 1
}

show_notification() {
  local title="$1"
  local message="$2"
  title=${title//\\/\\\\}
  title=${title//\"/\\\"}
  message=${message//\\/\\\\}
  message=${message//\"/\\\"}
  osascript -e "display notification \"$message\" with title \"$title\" sound name \"Glass\"" 2>/dev/null || true
}

is_screenshot_name() {
  local name="$1"
  [[ "$name" == (#i)Screenshot*.(png|jpg|jpeg|heic) ]] || \
  [[ "$name" == (#i)Screen\ Shot*.(png|jpg|jpeg|heic) ]]
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
    grep -Fvx -- "$name" "$STATE_FILE" 2>/dev/null | head -50 || true
  } > "${STATE_FILE}.tmp"
  mv -f "${STATE_FILE}.tmp" "$STATE_FILE"
}

is_recent() {
  local file="$1"
  local mtime now age
  mtime=$(stat -f %m "$file" 2>/dev/null || echo 0)
  now=$(date +%s)
  age=$(( now - mtime ))
  (( age >= 0 && age < 600 ))
}

process_file() {
  local src="$1"
  src=${src%$'\r'}
  [[ -f "$src" ]] || return 0

  local name
  name=$(basename -- "$src")

  is_screenshot_name "$name" || return 0
  already_processed "$name" && return 0
  is_recent "$src" || return 0

  if ! wait_for_stable_file "$src"; then
    log "Skip (unstable): $name"
    return 0
  fi

  [[ -f "$src" ]] || return 0
  already_processed "$name" && return 0

  # Leave the file where it is — clipboard only
  if put_image_on_clipboard "$src"; then
    mark_processed "$name"
    log "On clipboard (left in place): $name"
    show_notification "Screenshot Ready" "Cmd+V to paste"
  else
    log "Clipboard failed: $name"
    show_notification "Screenshot" "Clipboard copy failed"
  fi
}

# === Main ===

WATCH_DIR=$(get_ss_location)
log "Run (watch: $WATCH_DIR)"

typeset -a candidates
candidates=()
local_line=
while IFS= read -r local_line; do
  local_line=${local_line%$'\r'}
  [[ -n "$local_line" && -f "$local_line" ]] && candidates+=("$local_line")
done <<EOF
$(list_screenshots "$WATCH_DIR")
EOF

if [[ "$WATCH_DIR" != "$HOME/Desktop" ]]; then
  while IFS= read -r local_line; do
    local_line=${local_line%$'\r'}
    [[ -n "$local_line" && -f "$local_line" ]] && candidates+=("$local_line")
  done <<EOF
$(list_screenshots "$HOME/Desktop")
EOF
fi

log "Candidates: ${#candidates[@]}"

if (( ${#candidates[@]} == 0 )); then
  exit 0
fi

typeset -a sorted
sorted=()
while IFS= read -r local_line; do
  [[ -n "$local_line" ]] && sorted+=("$local_line")
done <<EOF
$(
  for p in "${candidates[@]}"; do
    printf '%s\t%s\n' "$(stat -f %m "$p" 2>/dev/null || echo 0)" "$p"
  done | sort -rn | cut -f2-
)
EOF

for f in "${sorted[@]}"; do
  process_file "$f"
done
