#!/usr/bin/env bash
#
# Interactive review + prune of stale tmux sessions via an fzf multi-select.
# Marked/selected sessions are killed; the rest are "kept" (re-stamped so they
# won't be flagged again for another week). Bound to prefix+K via display-popup,
# and also runnable directly (e.g. the `tprune` alias) in any terminal.
set -uo pipefail

export TMUX_TMPDIR="${TMUX_TMPDIR:-$HOME/.tmux/sockets}"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../crons/tmux-autosave/stale.sh
. "${SELF}/../crons/tmux-autosave/stale.sh"

# Probe mode for the `prefix+K` if-shell guard: exit 0 if any stale session
# exists, else 1. Lets tmux decide whether to open the popup at all (avoids a
# popup flashing open just to report "nothing stale").
if [[ "${1:-}" == "--has-stale" ]]; then
  [[ -n "$(_list_stale_candidates)" ]]
  exit $?
fi

# Status line: tmux message when inside tmux, else just print to the terminal.
_say() {
  if [[ -n "${TMUX:-}" ]]; then
    tmux display-message "tmux-prune: $1" 2>/dev/null || true
  else
    printf 'tmux-prune: %s\n' "$1"
  fi
}

# --- gather ------------------------------------------------------------------
candidates=()
while IFS= read -r line; do candidates+=("$line"); done < <(_list_stale_candidates)

if (( ${#candidates[@]} == 0 )); then
  _say "no stale sessions 🎉"
  exit 0
fi

labels=(); socks=(); sess=()
for line in "${candidates[@]}"; do
  IFS=$'\t' read -r socket session days wins <<<"$line"
  labels+=("${socket}:${session}  (idle ${days}d, ${wins} win)")
  socks+=("$socket"); sess+=("$session")
done

# --- choose (fzf multi-select) ----------------------------------------------
# Rows are "idx<TAB>label"; only the label is shown, the whole row is returned.
selected_idx=()
picks="$(
  for i in "${!labels[@]}"; do printf '%s\t%s\n' "$i" "${labels[$i]}"; done \
    | fzf --multi --reverse --delimiter='\t' --with-nth=2 \
        --bind 'ctrl-l:select,ctrl-h:deselect' \
        --prompt='prune> ' \
        --marker='✗ ' \
        --header='ctrl-l select · ctrl-h deselect · ENTER prune selected · ESC cancel'
)" || picks=""
[[ -z "$picks" ]] && { _say "cancelled — nothing changed"; exit 0; }
while IFS=$'\t' read -r idx _; do selected_idx+=("$idx"); done <<<"$picks"

(( ${#selected_idx[@]} == 0 )) && { _say "nothing marked — kept everything"; exit 0; }

# --- act ---------------------------------------------------------------------
_is_selected() { local n="$1" x; for x in "${selected_idx[@]}"; do [[ "$x" == "$n" ]] && return 0; done; return 1; }

pruned=0; kept=0
for i in "${!labels[@]}"; do
  if _is_selected "$i"; then
    _stale_kill "${socks[$i]}" "${sess[$i]}" && pruned=$(( pruned + 1 ))
  else
    _stale_keep "${socks[$i]}" "${sess[$i]}"; kept=$(( kept + 1 ))
  fi
done

_say "pruned ${pruned}, kept ${kept}"
