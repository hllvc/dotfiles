#!/usr/bin/env bash
#
# Warms a tmux server (`tmux -L <socket> start-server`) at login so that
# tmux-continuum's auto-restore runs *before* the user attaches. Verifies the
# server came up, reports restored session count, and pings via `alerter`.
#
# Run by:  com.hllvc.work.tmux  →  entrypoint.sh work
#          com.hllvc.personal.tmux  →  entrypoint.sh personal
#
# TMUX_TMPDIR is set in the plist so the warm socket lands at the same path
# the interactive `tt.sh` flow uses (~/.tmux/sockets/tmux-501/<socket>).

set -u

# shellcheck source=../_lib/log.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../_lib/log.sh"
# shellcheck source=../_lib/notify.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../_lib/notify.sh"

readonly LOG_DIR="${HOME}/Library/Logs/com.hllvc.tmux-warmup"
readonly LOG_FILE="${LOG_DIR}/main.log"
mkdir -p "$LOG_DIR"

socket="${1:-}"
if [[ -z "$socket" ]]; then
  _block_open "$LOG_FILE"
  _block_line "$LOG_FILE" "$(_color red "FAILED: socket name not provided as \$1")"
  _block_close "$LOG_FILE"
  _notify_sticky "tmux warmup FAILED" "entrypoint.sh called without a socket name"
  exit 2
fi
readonly socket

# tmux-resurrect save dir for this socket (because @continuum-multiple-sockets 'on').
# Default lives under XDG_DATA_HOME or ~/.local/share. We just probe both.
_resurrect_save_present() {
  local base
  for base in "${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect" "$HOME/.tmux/resurrect"; do
    [[ -e "$base/$socket/last" ]] && return 0
  done
  return 1
}

mkdir -p "${TMUX_TMPDIR:-/tmp}"

start_err=$(tmux -L "$socket" start-server 2>&1 >/dev/null)
start_rc=$?

# Continuum's restore runs synchronously inside start-server, but give tmux a
# beat to settle (plugin scripts shell out, file I/O, etc.) before counting.
sleep 1

session_count=0
if tmux -L "$socket" has-session 2>/dev/null; then
  server_up=1
  session_count=$(tmux -L "$socket" list-sessions -F '#S' 2>/dev/null | wc -l | tr -d ' ')
else
  server_up=0
fi

save_state="none"
_resurrect_save_present && save_state="present"

_block_open "$LOG_FILE"
if ((start_rc == 0 && server_up == 1)); then
  if [[ "$save_state" == "present" ]]; then
    if ((session_count > 0)); then
      _block_line "$LOG_FILE" "$(_color green "socket=${socket} · started OK · save=present · ${session_count} session(s) after restore")"
      _notify_quiet "tmux:${socket} warm" "restore: yes · ${session_count} session(s)" 5
    else
      _block_line "$LOG_FILE" "$(_color yellow "socket=${socket} · started OK · save=present · 0 session(s) (restore did not populate)")"
      _notify_quiet "tmux:${socket} warm" "restore: yes · 0 session(s)?" 5
    fi
  else
    _block_line "$LOG_FILE" "$(_color green "socket=${socket} · started OK · save=none · ${session_count} session(s) (clean server)")"
    _notify_quiet "tmux:${socket} warm" "restore: n/a · clean server" 5
  fi
  _block_line "$LOG_FILE" "$(_color dim "TMUX_TMPDIR=${TMUX_TMPDIR:-<unset>}")"
  _block_close "$LOG_FILE"
else
  _block_line "$LOG_FILE" "$(_color red "socket=${socket} · FAILED · rc=${start_rc} · server_up=${server_up}")"
  _block_line "$LOG_FILE" "$(_color dim "TMUX_TMPDIR=${TMUX_TMPDIR:-<unset>}")"
  [[ -n "$start_err" ]] && _block_line "$LOG_FILE" "$(_color dim "stderr: ${start_err}")"
  _block_close "$LOG_FILE"
  _notify_sticky "tmux:${socket} warmup FAILED" "${start_err:-tmux did not start (rc=${start_rc})}"
  exit 1
fi
