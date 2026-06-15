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

# Whether a restore is expected shapes how long we wait below.
save_state="none"
_resurrect_save_present && save_state="present"

start_err=$(tmux -L "$socket" start-server 2>&1 >/dev/null)
start_rc=$?

# Liveness probe: `has-session` is FALSE on a server that is up but has no sessions
# yet, so a started-but-not-yet-restored server reads as down. Use `list-sessions`
# (rc 0 even when empty) instead.
#
# Continuum auto-restores asynchronously after start-server, but under a heavy boot
# load a large restore (the work socket is ~40 panes) can produce zero sessions for
# far longer than a short peek — and sometimes never (observed: load avg ~41, work
# stayed empty, the first attach then created a stray session on an un-restored
# server). So don't merely WAIT for continuum: give it a grace window, and if it has
# produced nothing, run the restore ourselves. restore.sh checks has-session/window/
# pane before creating, so it's idempotent and safe even if continuum is just slow.
readonly restore_script="$HOME/.tmux/plugins/tmux-resurrect/scripts/restore.sh"
readonly grace_iters=50    # 50 * 0.5s = 25s for continuum before we take over
readonly cap_iters=240     # 240 * 0.5s = 120s hard cap
server_up=0
session_count=0
fallback_ran=0
for (( i = 1; i <= cap_iters; i++ )); do
  if tmux -L "$socket" list-sessions >/dev/null 2>&1; then
    server_up=1
    session_count=$(tmux -L "$socket" list-sessions -F '#S' 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [[ "$save_state" != "present" ]]; then
    break                              # no save expected → empty clean server is success
  fi
  (( session_count > 0 )) && break     # restore populated → done
  if (( i >= grace_iters && fallback_ran == 0 && server_up == 1 )); then
    fallback_ran=1
    [[ -x "$restore_script" ]] && tmux -L "$socket" run-shell "$restore_script"
    continue                           # re-poll immediately once the restore returns
  fi
  sleep 0.5
done

fb_note=""
(( fallback_ran == 1 )) && fb_note=" · via fallback restore (continuum was empty)"

_block_open "$LOG_FILE"
if ((start_rc == 0 && server_up == 1)); then
  if [[ "$save_state" == "present" ]]; then
    if ((session_count > 0)); then
      _block_line "$LOG_FILE" "$(_color green "socket=${socket} · started OK · save=present · ${session_count} session(s) after restore${fb_note}")"
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
