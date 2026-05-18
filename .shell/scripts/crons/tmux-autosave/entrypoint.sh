#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../_lib/log.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../_lib/log.sh"

readonly LOG_DIR="${HOME}/Library/Logs/com.hllvc.tmux-autosave"
readonly LOG_FILE="${LOG_DIR}/main.log"
readonly CACHE_DIR="${HOME}/Library/Caches/com.hllvc.tmux-autosave"
readonly LAST_SAVE_FILE="${CACHE_DIR}/last_save_ts"
readonly RESURRECT_SAVE="${HOME}/.tmux/plugins/tmux-resurrect/scripts/save.sh"
readonly SOCKET_DIR="${TMUX_TMPDIR:-${HOME}/.tmux/sockets}/tmux-$(id -u)"

# Seconds of HID inactivity needed to trigger an idle-gated save.
readonly IDLE_THRESHOLD=30
# Unconditional save floor — fires even if user is active (seconds since last save).
readonly FORCE_INTERVAL=5400   # 90 min

mkdir -p "$LOG_DIR" "$CACHE_DIR"

_hid_idle_secs() {
  local t
  t=$(ioreg -c IOHIDSystem 2>/dev/null \
    | awk '/HIDIdleTime/ {print int($NF / 1000000000); exit}')
  echo "${t:-0}"
}

_last_save_age() {
  local now ts=0
  now=$(date +%s)
  [[ -f "$LAST_SAVE_FILE" ]] && ts=$(<"$LAST_SAVE_FILE")
  echo $(( now - ts ))
}

force=0
[[ "${1:-}" == "--force" ]] && force=1

idle=$(_hid_idle_secs)
age=$(_last_save_age)

_block_open "$LOG_FILE"

if (( force )); then
  reason="forced (sleep/shutdown)"
elif (( idle >= IDLE_THRESHOLD )); then
  reason="idle=${idle}s"
elif (( age >= FORCE_INTERVAL )); then
  reason="force (${age}s since last save)"
else
  _block_line "$LOG_FILE" "$(_color dim "skip · idle=${idle}s · last_save ${age}s ago")"
  _block_close "$LOG_FILE"
  exit 0
fi

_block_line "$LOG_FILE" "$(_color dim "saving · ${reason}")"

found=0
while IFS= read -r -d '' sock_path; do
  socket="$(basename "$sock_path")"
  if tmux -L "$socket" has-session 2>/dev/null; then
    tmux -L "$socket" run-shell -b "$RESURRECT_SAVE"
    _block_line "$LOG_FILE" "$(_color green "socket=${socket} · save fired")"
    found=$(( found + 1 ))
  else
    _block_line "$LOG_FILE" "$(_color dim "socket=${socket} · no server, skipped")"
  fi
done < <(/usr/bin/find "$SOCKET_DIR" -maxdepth 1 -type s -print0 2>/dev/null)

if (( found == 0 )); then
  _block_line "$LOG_FILE" "$(_color yellow "no live sockets found under ${SOCKET_DIR}")"
fi

printf '%s\n' "$(date +%s)" > "$LAST_SAVE_FILE"
_block_close "$LOG_FILE"
