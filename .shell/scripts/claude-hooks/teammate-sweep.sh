#!/usr/bin/env bash
#
# Claude Code Stop hook (no matcher): a sweep for idle teammates. When the lead
# ends its turn while named workers sit idle in their tmux panes, it injects a
# one-line "close or keep them" reminder as additionalContext, so the lead takes
# one short extra turn to TaskStop the ones it is done with. Model-agnostic.
# Registered in .claude/settings.json without onFailure, and it always exits 0
# with no output on any error: it never blocks anything.
#
# - Quiet when stop_hook_active is set, or when background_tasks holds a
#   subagent or workflow entry (the lead is waiting on delegated work). Shell
#   tasks don't count, or a long-running dev server would mute it.
# - The lead is the pid whose $root/sessions/<pid>.json carries this session_id
#   (root = CLAUDE_CONFIG_DIR or ~/.claude). Teammates have no such file, so
#   their own Stop is quiet; looking up by pid is what survives /clear.
# - Members: those of every $root/teams/*/config.json whose leadProcess.pid is
#   the lead, with backendType "tmux" and a boolean isActive (the flag is absent
#   on a just-spawned worker). Configs without leadProcess (older format) never
#   match. grep narrows the configs first. Candidates are the idle ones
#   (isActive false).
# - Only members with a live process count: one `ps` capture, matched on the
#   exact token pair `--agent-id <name>@<team>` (so scout never matches scout-2).
#   Must stay fast under macOS's /bin/bash 3.2: nothing that grows with the
#   process table is held or transformed in a shell variable.
# - Seen marker: when any member, busy or idle, matches a live process, the
#   whole chain has just worked on the lead's CLI version. It creates an empty
#   $XDG_STATE_HOME/claude/teammate-sweep-seen/<version>, version read from the
#   lead's sessions/<pid>.json (x.y.z only). Done before raising, whether or not
#   anything is raised; any failure is silent. A sibling of the state directory,
#   so the 7-day prune never removes it. versions-review/verify/claude-code.sh
#   reads it.
# - Each name:joinedAt is raised once per TEAMMATE_SWEEP_REMIND_MIN minutes
#   (default 60, 0 = every Stop); a re-spawned worker with the same name has a
#   new joinedAt and is raised again.
# - State: one line per raised entry, "name:joinedAt raised_at", per session in
#   $XDG_STATE_HOME/claude/teammate-sweep/, pruned after 7 days whenever a new
#   session's file is created. Recorded before printing; if the write fails it
#   prints nothing.
#
# Cases it must keep getting right: teammate-sweep.test.sh.

set -u
exec 2>/dev/null
trap 'exit 0' EXIT

input="$(cat)" || exit 0
command -v jq >/dev/null || exit 0

remind_min="${TEAMMATE_SWEEP_REMIND_MIN:-60}"
[[ "$remind_min" =~ ^[0-9]+$ ]] || exit 0

# The one place the output shape lives; additionalContext on Stop continues
# the lead's turn.
emit() { # <message>
  jq -cn --arg m "$1" '{hookSpecificOutput: {hookEventName: "Stop", additionalContext: $m}}'
}

# session_id, stop_hook_active, waiting on delegated work, now: one per line.
fields="$(jq -r '
  (.session_id // ""),
  (.stop_hook_active == true),
  (.background_tasks | if type == "array"
    then any(.[]; type == "object" and (.type == "subagent" or .type == "workflow"))
    else false end),
  (now | floor)
' <<<"$input")" || exit 0
{ read -r sid; read -r active; read -r waiting; read -r now; } <<<"$fields"
[[ "$sid" =~ ^[A-Za-z0-9._-]+$ && "$now" =~ ^[0-9]+$ ]] || exit 0
[[ "$active" == false && "$waiting" == false ]] || exit 0

root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Lead pid: grep narrows the files, jq confirms the exact sessionId.
pid=""
while IFS= read -r f; do
  p="${f##*/}" p="${p%.json}"
  [[ "$p" =~ ^[0-9]+$ ]] || continue
  [[ "$(jq -r '.sessionId? // empty' "$f")" == "$sid" ]] && { pid="$p"; break; }
done < <(grep -lF -- "$sid" "$root"/sessions/*.json)
[[ -n "$pid" ]] || exit 0

# Tmux members of this lead's teams with a boolean isActive: team, name,
# agentType, joinedAt, isActive, separated by \x1f (empty fields survive, unlike with tab). grep narrows the
# configs to those mentioning "pid": <pid> (stale ones pile up), then one jq per
# match confirms leadProcess.pid, so a truncated file drops only itself.
rows=()
while IFS= read -r cfg; do
  [[ -f "$cfg" ]] || continue
  out="$(jq -r --argjson pid "$pid" '
    select(type == "object" and (.leadProcess | type) == "object" and .leadProcess.pid == $pid)
    | (.name // "") as $t
    | (.members // [])[]?
    | select(type == "object" and .backendType == "tmux" and (.isActive | type) == "boolean")
    | [$t, (.name // ""), (.agentType // ""), (.joinedAt // ""), .isActive]
    | map(tostring | explode | map(select(. >= 32)) | implode) | join("\u001f")
  ' "$cfg")" || continue
  while IFS= read -r row; do
    [[ -n "$row" ]] && rows+=("$row")
  done <<<"$out"
done < <(grep -lE "\"pid\"[[:space:]]*:[[:space:]]*$pid([^0-9]|\$)" "$root"/teams/*/config.json)
((${#rows[@]})) || exit 0

# Live teammate ids (<name>@<team>), one per line: awk takes the word after each
# --agent-id, so the process table itself never sits in a shell variable (bash
# 3.2's string operations are quadratic on it).
ids="$(ps -axo args= | awk '{ for (i = 1; i < NF; i++) if ($i == "--agent-id") print $(i + 1) }')"
ids=$'\n'"$ids"$'\n'

dir="${XDG_STATE_HOME:-$HOME/.local/state}/claude/teammate-sweep"
state="$dir/$sid"
old=""
[[ -f "$state" ]] && old="$(<"$state")"

keys=() labels=() seen=""
for row in "${rows[@]}"; do
  IFS=$'\x1f' read -r team name type joined idle <<<"$row"
  [[ "$team" =~ ^[A-Za-z0-9._-]+$ && "$name" =~ ^[A-Za-z0-9._-]+$ && "$joined" =~ ^[0-9]+$ ]] || continue
  [[ "$ids" == *$'\n'"$name@$team"$'\n'* ]] || continue
  seen=1
  [[ "$idle" == false ]] || continue
  key="$name:$joined"
  raised=""
  while read -r k t; do
    [[ "$k" == "$key" && "$t" =~ ^[0-9]+$ ]] && raised="$t"
  done <<<"$old"
  [[ -n "$raised" ]] && ((now - raised < remind_min * 60)) && continue
  keys+=("$key")
  if [[ -n "$type" ]]; then labels+=("$name ($type)"); else labels+=("$name"); fi
done

# Seen marker, a silent side effect: never stops the raise below.
if [[ -n "$seen" ]]; then
  ver="$(jq -r '.version | strings' "$root/sessions/$pid.json")"
  if [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    seen_dir="${XDG_STATE_HOME:-$HOME/.local/state}/claude/teammate-sweep-seen"
    [[ -e "$seen_dir/$ver" ]] || { mkdir -p "$seen_dir" && : >>"$seen_dir/$ver"; }
  fi
fi

((${#keys[@]})) || exit 0

list="${labels[0]}"
for l in "${labels[@]:1}"; do list+=", $l"; done
msg="Idle teammates still running: $list. \`TaskStop <name>\` each one you are done with, keep the rest. Reply in one line, then end your turn as before; anything you are waiting on will still notify you."
out="$(emit "$msg")" || exit 0

# Keep valid lines for entries not raised now, then add the raised ones.
new=""
while read -r k t; do
  [[ -n "$k" && "$t" =~ ^[0-9]+$ ]] || continue
  for key in "${keys[@]}"; do [[ "$k" == "$key" ]] && continue 2; done
  new+="$k $t"$'\n'
done <<<"$old"
for key in "${keys[@]}"; do new+="$key $now"$'\n'; done

if [[ ! -f "$state" ]]; then
  mkdir -p "$dir" || exit 0
  # New session file: drop state left by sessions idle for over 7 days.
  find "$dir" -type f -mtime +7 -delete
fi
printf '%s' "$new" >"$state.$$" && mv -f "$state.$$" "$state" || exit 0

printf '%s\n' "$out"
exit 0
