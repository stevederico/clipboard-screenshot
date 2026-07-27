#!/bin/zsh
# clipboard-screenshot
# launchd-based macOS screenshot archiver + clipboard copier.
# Zero dependencies: zsh + osascript + launchd only.
#
# Screenshots must land in a non-TCC-protected folder (not Desktop/Documents).
# install.sh points com.apple.screencapture location at ~/Screenshots/Incoming.

set -euo pipefail
setopt NULL_GLOB EXTENDED_GLOB
unsetopt NOMATCH

SS_DIR="${SCREENSHOTS_DIR:-$HOME/Screenshots}"
INBOX_DIR="${SCREENSHOTS_INBOX:-$SS_DIR/Incoming}"
mkdir -p "$SS_DIR" "$INBOX_DIR"
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

# Wait until file exists, is non-tiny, and size is stable.
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

# Copy image to pasteboard. No System Events (no Automation TCC).
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

process_file() {
  local src="$1"
  [[ -f "$src" ]] || return 0

  local name
  name=$(basename -- "$src")

  is_screenshot_name "$name" || { log "Skip (name): $name"; return 0; }
  already_processed "$name" && { log "Skip (done): $name"; return 0; }

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

log "Run (inbox: $INBOX_DIR)"

# Inbox is intentionally outside Desktop/Documents (TCC blocks launchd there).
typeset -a candidates
candidates=()
local_line=
while IFS= read -r local_line; do
  [[ -n "$local_line" && -f "$local_line" ]] && candidates+=("$local_line")
done <<EOF
$(find "$INBOX_DIR" -maxdepth 1 -type f \( \
    -name 'Screenshot*' -o -name 'screenshot*' -o \
    -name 'Screen Shot*' -o -name 'Screen shot*' \
  \) -print 2>/dev/null || true)
EOF

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
