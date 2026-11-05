#!/usr/bin/env bash
#
# Restart the Claude session in a pane with MCP servers picked from a list.
#
# Finds the pane's Claude session (claude-pane.sh), opens an fzf multi-picker of
# cmcp names (connector aliases + configured servers, plus "all"), then hands
# `cmcp <picks> -- --resume <session id>` to replace-pane.sh, which respawns the
# pane in place and types it into the fresh shell.
#
# Bound to prefix+C-p in a popup. Usage: mcp-resume.sh [<pane id>]
set -uo pipefail

scripts="$HOME/.shell/scripts"
pane="${1:-${TMUX_PANE:-}}"

_say() {
  tmux display-message "mcp-resume: $1" 2>/dev/null || printf 'mcp-resume: %s\n' "$1"
}

if [[ -z "$pane" ]]; then
  _say "not inside a tmux pane"
  exit 1
fi

current="$("$scripts/tmux/claude-pane.sh" "$pane")"
if [[ -z "$current" ]]; then
  _say "no Claude session running in this pane"
  exit 1
fi

# Popups get tmux's environment, not the shell's: load the personal fzf
# mappings from the same place the shell does.
if [[ -z "${FZF_DEFAULT_OPTS:-}" ]]; then
  eval "$(grep -m1 '^export FZF_DEFAULT_OPTS=' "$HOME/.shell/profile")"
fi

picks="$(
  { echo all; "$scripts/cmcp.sh" -n; } \
    | fzf --multi --reverse --prompt='mcp> ' \
        --header="now: $([[ $current == cmcp* ]] && echo "${current% -- --resume *}" || echo 'no MCP servers')"
)" || exit 0
[[ -n "$picks" ]] || exit 0

if grep -qx all <<<"$picks"; then
  args=(-a)
else
  mapfile -t args <<<"$picks"
fi

"$scripts/tmux/replace-pane.sh" "$pane" "$("$scripts/tmux/claude-pane.sh" "$pane" "${args[@]}")"
