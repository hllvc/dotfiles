#!/usr/bin/env bash
#
# Restart the Claude session in a pane with MCP servers picked from a list.
#
# Finds the pane's Claude session (claude-pane.sh), opens an fzf multi-picker of
# cmcp names (connector aliases + configured servers, plus "-" for none when the
# session has some), then hands
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

# Servers the session runs with now (cmcp args before the first " -- "; -a
# means every name). They go first in the list and start selected, since a
# reload is usually adding to the set, not replacing it.
names="$("$scripts/cmcp.sh" -n)"
now=()
if [[ $current == cmcp* ]]; then
  read -ra now <<<"${current%% -- *}"
  now=("${now[@]:1}")
  if printf '%s\n' "${now[@]}" | grep -qx -- -a; then
    mapfile -t now <<<"$names"
  fi
fi
ordered=() rest=()
while IFS= read -r name; do
  if printf '%s\n' "${now[@]}" | grep -qxF -- "$name"; then
    ordered+=("$name")
  else
    rest+=("$name")
  fi
done <<<"$names"

# "-" (offered when the session has servers) drops them all. It sits on top,
# where the cursor starts: deselect everything and Enter lands on it. Picked
# along with servers it is ignored, so select-all still means all.
head=()
[[ $current != cmcp* ]] || head=(-)
preselect=
for (( i = ${#head[@]} + 1; i <= ${#head[@]} + ${#ordered[@]}; i++ )); do
  preselect+="pos($i)+select+"
done

picks="$(
  printf '%s\n' ${head[@]+"${head[@]}"} ${ordered[@]+"${ordered[@]}"} ${rest[@]+"${rest[@]}"} \
    | fzf --multi --reverse --prompt='mcp> ' \
        ${preselect:+--bind "load:${preselect}first"} \
        --header="now: $([[ $current == cmcp* ]] && echo "${current%% -- *}" || echo 'no MCP servers')"
)" || exit 0
picks="$(grep -vx -- - <<<"$picks")"

if [[ -z "$picks" ]]; then
  [[ $current == cmcp* ]] || exit 0
  "$scripts/tmux/replace-pane.sh" "$pane" "claude --resume ${current##* --resume }"
  exit 0
fi

# Every name picked: -a, which also covers remote servers cmcp has no alias for.
if [[ $(wc -l <<<"$picks") -eq $(wc -l <<<"$names") ]]; then
  args=(-a)
else
  mapfile -t args <<<"$picks"
fi

"$scripts/tmux/replace-pane.sh" "$pane" "$("$scripts/tmux/claude-pane.sh" "$pane" "${args[@]}")"
