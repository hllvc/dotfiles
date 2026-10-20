#!/usr/bin/env bash
#
# Runs every case in aws-profile-guard.cases through the hook the way Claude Code
# does (the PreToolUse payload on stdin) and checks that it asks or stays quiet.
# Nothing is executed: the commands are only text. Needs jq.
#
#   aws-profile-guard.test.sh

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
declare -i pass=0 fail=0

while IFS= read -r line; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  want="${line%% :: *}"
  cmd="${line#* :: }"
  out="$(jq -cn --arg c "$cmd" '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $c}}' |
    bash "$here/aws-profile-guard.sh")"
  if [[ -n "$out" ]] && jq -e '.hookSpecificOutput.permissionDecision == "ask"' <<<"$out" >/dev/null 2>&1; then
    got=ask
  elif [[ -z "$out" ]]; then
    got=ok
  else
    got="unexpected output: $out"
  fi
  if [[ "$got" == "$want" ]]; then
    pass+=1
  else
    fail+=1
    printf 'FAIL  want %-3s got %s\n      %s\n' "$want" "$got" "$cmd"
  fi
done <"$here/aws-profile-guard.cases"

printf '%d passed, %d failed\n' "$pass" "$fail"
((fail == 0))
