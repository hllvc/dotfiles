#!/usr/bin/env bash
#
# resurrect-claude — tmux-resurrect post-save-layout hook: rewrite saved claude
# pane commands into something that survives being typed back into a shell.
#
# Usage: resurrect-claude.sh <resurrect save file>
#
# resurrect saves a pane's command from `ps`, which drops the quoting, and on
# restore send-keys it into zsh. `claude --settings {"allowedMcpServers":[...]}`
# then dies on globbing ("bad pattern"), or reaches claude as broken JSON. So
# every saved `claude ...` is replaced with the relaunch claude-pane.sh builds:
# `cmcp <servers> -- [<extra args>] --resume <id>` or `claude --resume <id>`,
# which rebuild --settings through cmcp / the claude() wrapper. When no live
# session is found, a `--settings` launch falls back to `claude --continue`.
#
# Runs inside the saved server (run-shell), so plain `tmux` targets it.
set -uo pipefail

file="${1:-}"
[[ -n "$file" && -f "$file" ]] || exit 0

tab=$'\t'
tmp="$file.claude.$$"
trap 'rm -f "$tmp"' EXIT

while IFS= read -r line || [[ -n "$line" ]]; do
  cmd="${line##*"$tab"}"
  if [[ "$line" == "pane$tab"* && ( "$cmd" == ":claude" || "$cmd" == ":claude "* ) ]]; then
    session="$(cut -f2 <<<"$line")"
    window="$(cut -f3 <<<"$line")"
    index="$(cut -f6 <<<"$line")"
    pane_id="$(tmux display-message -p -t "$session:$window.$index" '#{pane_id}' 2>/dev/null)"
    new=
    [[ -n "$pane_id" ]] && new="$("$HOME/.shell/scripts/tmux/claude-pane.sh" "$pane_id" 2>/dev/null)"
    if [[ -z "$new" && "$cmd" == *" --settings "* ]]; then
      new="claude --continue"
    fi
    [[ -z "$new" ]] || line="${line%"$tab"*}$tab:$new"
  fi
  printf '%s\n' "$line"
done <"$file" >"$tmp" && mv -f "$tmp" "$file"
