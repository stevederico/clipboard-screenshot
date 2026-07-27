#!/bin/zsh
# clipboard-screenshot
# launchd agent: move new screenshots to ~/Screenshots + put on clipboard.
# Zero dependencies: zsh + osascript + launchd.
#
# Why System Events for listing: launchd cannot readdir ~/Desktop (TCC
# "Operation not permitted"). System Events can list it. Direct open/stat/mv
# of a known path still works.

set -euo pipefail
setopt NULL_GLOB EXTENDED_GLOB
unsetopt NOMATCH

SS_DIR="${SCREENSHOTS_DIR:-$HOME/Screenshots}"
mkdir -p "$SS_DIR"
STATE_FILE="$SS_DIR/.last-processed"
LOG_FILE="$SS_DIR/watcher.log"
LOCK_DIR="$SS_DIR/.watcher.lock"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Serialize concurrent launchd fires
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

# List screenshot files in dir. Prefer System Events (Desktop-safe under TCC).
# Falls back to find for non-protected folders.
list_screenshots() {
  local dir="$1"
  local se_out find_out

  se_out=$(osascript - "$dir" <<'APPLESCRIPT' 2>/dev/null || true
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
)

  if [[ -n "${se_out//[$'\n']/}" ]]; then
    print -r -- "$se_out"
    return 0
  fi

  # find works for ~/Screenshots etc.; fails on Desktop under launchd TCC
  find "$dir" -maxdepth 1 -type f \( \
      -name 'Screenshot*' -o -name 'screenshot*' -o \
      -name 'Screen Shot*' -o -name 'Screen shot*' \
    \) -print 2>/dev/null || true
}

wait_for_stable_file() {
  local file="$1"
  local max_wait=40
  local last_size=-1
  local stable=0
  local i size

  for i in {1..$max_wait}; do
    # known absolute paths are readable even when readdir is blocked
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

# Only process files modified in the last N minutes (avoid re-eating old Desktop junk)
is_recent() {
  local file="$1"
  local mtime now age
  mtime=$(stat -f %m "$file" 2>/dev/null || echo 0)
  now=$(date +%s)
  age=$(( now - mtime ))
  (( age >= 0 && age < 600 ))  # 10 minutes
}

process_file() {
  local src="$1"
  # strip trailing CR if any from AppleScript
  src=${src%$'\r'}
  [[ -f "$src" ]] || return 0

  local name
  name=$(basename -- "$src")

  is_screenshot_name "$name" || { log "Skip (name): $name"; return 0; }
  already_processed "$name" && return 0
  is_recent "$src" || { log "Skip (old): $name"; return 0; }

  if ! wait_for_stable_file "$src"; then
    log "Skip (unstable/missing): $name"
    return 0
  fi

  [[ -f "$src" ]] || return 0
  already_processed "$name" && return 0

  local dest="$SS_DIR/$(date +%Y-%m-%d_%H-%M-%S)_$name"
  if [[ -e "$dest" ]]; then
    dest="$SS_DIR/$(date +%Y-%m-%d_%H-%M-%S)_$$_$name"
  fi

  if ! mv "$src" "$dest" 2>/dev/null; then
    log "mv failed (will retry): $name"
    return 0
  fi
  log "Moved: $name → $(basename -- "$dest")"
  mark_processed "$name"

  if put_image_on_clipboard "$dest"; then
    log "On clipboard: $(basename -- "$dest")"
    show_notification "Screenshot Ready" "Cmd+V · Saved to ~/Screenshots"
  else
    log "Clipboard failed for $(basename -- "$dest")"
    show_notification "Screenshot Moved" "Clipboard failed · ~/Screenshots"
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

# If macOS location isn't Desktop but user still has strays / dual paths, also check Desktop
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
