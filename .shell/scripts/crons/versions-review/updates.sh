#!/usr/bin/env bash
# The `updates` tmux session (personal socket) where drafted update plans wait:
# window 1 `status` is a shell in the dotfiles repo, then one window per tool,
# named "<tool> <from>→<to>", resuming the Claude session that drafted the plan.
#
#   updates.sh open <window-name> <session-uuid>   create it detached (no-op if open)
#   updates.sh switch <window-name>                 show it on the attached client
#   updates.sh close <tool>                          kill "<tool> …" windows, except
#                                                    the one this runs inside
#
# Env: VERSIONS_REVIEW_SESSION (default updates), VERSIONS_REVIEW_REPO.

set -u

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO="${VERSIONS_REVIEW_REPO:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)}"
readonly SESSION="${VERSIONS_REVIEW_SESSION:-updates}"
readonly SOCKET=personal
# launchd's PATH has no ~/.local/bin, where claude lives.
readonly CLAUDE="$HOME/.local/bin/claude"
# Same socket dir the tmux-warmup launch agents start the servers with.
export TMUX_TMPDIR="$HOME/.tmux/sockets"

_tmux() {
  tmux -L "$SOCKET" "$@"
}

# Window id for an exact window name in the session, empty when absent.
_window_id() {
  _tmux list-windows -t "=$SESSION" -F '#{window_id}	#{window_name}' 2>/dev/null |
    awk -F '\t' -v n="$1" '$2 == n { print $1; exit }'
}

_ensure_session() {
  _tmux has-session -t "=$SESSION" 2>/dev/null ||
    _tmux new-session -d -s "$SESSION" -n status -c "$REPO"
}

cmd_open() {
  local name="$1" uuid="$2"
  _tmux has-session 2>/dev/null || {
    echo "updates: the ${SOCKET} tmux server isn't running" >&2
    return 1
  }
  _ensure_session || return 1
  [[ -z "$(_window_id "$name")" ]] || return 0
  _tmux new-window -d -t "=$SESSION:" -n "$name" -c "$REPO" \
    "$CLAUDE" --resume "$uuid" --permission-mode plan
}

cmd_switch() {
  local id client
  id="$(_window_id "$1")"
  [[ -n "$id" ]] || {
    echo "updates: no window named '$1' in $SESSION" >&2
    return 1
  }
  client="$(_tmux list-clients -F '#{client_name}' 2>/dev/null | head -n 1)"
  if [[ -n "$client" ]]; then
    _tmux switch-client -c "$client" -t "$id"
  else
    _tmux select-window -t "$id"
  fi
  open -a Ghostty
}

cmd_close() {
  local tool="$1" here="" id name
  _tmux has-session -t "=$SESSION" 2>/dev/null || return 0
  # Accepting from inside the plan's own window (the Claude session there runs
  # `dotctl versions accept`) must not kill that session mid-commit; it closes
  # itself when Claude exits.
  if [[ -n "${TMUX_PANE:-}" && "${TMUX:-}" == "$TMUX_TMPDIR/tmux-$(id -u)/$SOCKET,"* ]]; then
    here="$(_tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null)"
  fi
  while IFS=$'\t' read -r id name; do
    [[ "$name" == "$tool "* && "$id" != "$here" ]] || continue
    _tmux kill-window -t "$id"
  done < <(_tmux list-windows -t "=$SESSION" -F '#{window_id}	#{window_name}')
}

case "${1:-}" in
open) cmd_open "$2" "$3" ;;
switch) cmd_switch "$2" ;;
close) cmd_close "$2" ;;
*)
  echo "usage: updates.sh open <name> <uuid> | switch <name> | close <tool>" >&2
  exit 1
  ;;
esac
