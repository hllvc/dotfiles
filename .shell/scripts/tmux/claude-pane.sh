#!/usr/bin/env bash
#
# claude-pane — the command that brings back the Claude session in a tmux pane.
#
# Usage: claude-pane.sh <pane id> [<cmcp args>...]
#   no args   print the relaunch for the session as it runs now: `claude --resume
#             <id>`, or `cmcp <its picks> -- --resume <id>` if cmcp started it
#   args      print `cmcp <args> -- --resume <id>` (a new set of MCP servers)
# Exits 1, printing nothing, when the pane has no live Claude session.
#
# Sessions are found in ~/.claude/sessions/*.json, which record their pane as
# "<session>:@<window>.%<pane>". The whole key is matched: pane ids are only
# unique per tmux server, and several servers run at once. Resuming by id, not
# --continue, keeps two sessions in one directory apart.
#
# cmcp writes ~/.claude/cmcp/<pid> (`ps` start time, then its server args)
# before exec'ing claude under the same pid; matching the start time again
# guards against a reused pid.
set -uo pipefail

pane="${1:-}"
shift || true
[[ -n "$pane" ]] || exit 1

key="$(tmux display-message -p -t "$pane" '#{session_name}:#{window_id}.#{pane_id}' 2>/dev/null)"
[[ -n "$key" ]] || exit 1

# More than one file can match after a restart: newest with a live pid wins.
# One jq per file, so a single unreadable file cannot hide the rest.
pid= sid=
while IFS=$'\t' read -r p s; do
  if kill -0 "$p" 2>/dev/null; then
    pid="$p" sid="$s"
    break
  fi
done < <(
  for f in "$HOME"/.claude/sessions/*.json; do
    jq -r --arg k "$key" \
      'select(.tmux == $k) | [(.updatedAt // 0), .pid, .sessionId] | @tsv' \
      "$f" 2>/dev/null
  done | sort -rn | cut -f2-
)
[[ -n "$sid" ]] || exit 1

if (( $# )); then
  printf 'cmcp %s -- --resume %s\n' "$*" "$sid"
  exit 0
fi

# Drop records for dead pids while we are here.
for f in "$HOME"/.claude/cmcp/*; do
  [[ -e "$f" ]] || continue
  kill -0 "${f##*/}" 2>/dev/null || rm -f "$f"
done

record="$HOME/.claude/cmcp/$pid"
if [[ -s "$record" ]]; then
  { IFS= read -r rec_start; IFS= read -r rec_args; } <"$record"
  # Same `ps` on both sides (the session file's procStart is UTC, ps is local).
  if [[ -n "$rec_args" && "$(echo $rec_start)" == "$(echo $(ps -o lstart= -p "$pid"))" ]]; then
    printf 'cmcp %s -- --resume %s\n' "$rec_args" "$sid"
    exit 0
  fi
fi
printf 'claude --resume %s\n' "$sid"
