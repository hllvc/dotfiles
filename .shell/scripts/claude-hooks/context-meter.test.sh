#!/usr/bin/env bash
#
# Runs the scenarios in context-meter.cases through the hook the way Claude Code
# does (the PostToolUse payload on stdin, a transcript on disk) and checks when
# it nudges, then checks that it stays silent and exits 0 when things break.
# Everything lives in a temp dir: no real session state is touched. Needs jq.
#
#   context-meter.test.sh

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export XDG_STATE_HOME="$tmp/state"
declare -i pass=0 fail=0 n=0
sid="" transcript="" last="" envs=()

check() { # <ok?> <description>
  if [[ "$1" == 1 ]]; then pass+=1; else fail+=1; printf 'FAIL  %s\n' "$2"; fi
}

entry() { # <sidechain?> <model>
  jq -cn --argjson side "$1" --arg m "$2" \
    '{parentUuid: null, isSidechain: $side, type: "assistant", message: {model: $m, content: []}}' >>"$transcript"
}

call() { # <tool> <bytes> [sub]
  jq -cn --arg s "$sid" --arg t "$transcript" --arg tool "$1" --argjson b "$2" --arg sub "${3:-}" '
    {session_id: $s, transcript_path: $t, cwd: "/tmp", permission_mode: "default"}
    + (if $sub == "sub" then {agent_id: "a0123", agent_type: "general-purpose"} else {} end)
    + {hook_event_name: "PostToolUse", tool_name: $tool, tool_input: {},
       tool_response: ("x" * $b // ""), tool_use_id: "toolu_1"}
    + (if $sub == "sub-late" then {agent_id: "a0123"} else {} end)' |
    env ${envs[@]+"${envs[@]}"} "$BASH" "$here/context-meter.sh"
}

while IFS= read -r line; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  case "$line" in
    session*)
      n+=1 sid="test-$n" transcript="$tmp/t$n.jsonl" last=""
      : >"$transcript"
      read -ra envs <<<"${line#session}"
      ;;
    model\ *) entry false "${line#model }" ;;
    sidechain\ *) entry true "${line#sidechain }" ;;
    has\ ::\ *)
      text="${line#has :: }"
      got="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$last" 2>/dev/null)"
      [[ "$got" == *"$text"* ]] && check 1 || check 0 "session $n: nudge lacks \"$text\": ${got:-<none>}"
      ;;
    *)
      want="${line%% :: *}"
      read -r tool bytes sub <<<"${line#* :: }"
      out="$(call "$tool" "$bytes" "$sub")"
      rc=$?
      if [[ -z "$out" ]]; then
        got=quiet
      elif jq -e '.hookSpecificOutput.hookEventName == "PostToolUse" and (.hookSpecificOutput.additionalContext | startswith("Context meter:"))' <<<"$out" >/dev/null 2>&1; then
        got=nudge last="$out"
      else
        got="unexpected output: $out"
      fi
      [[ "$got" == "$want" && $rc == 0 ]] && check 1 || check 0 "session $n: $line -> $got (exit $rc)"
      ;;
  esac
done <"$here/context-meter.cases"

# Failure modes: always exit 0 with no output.
quiet() { # <description> <command...>
  local out rc
  out="$("${@:2}")"; rc=$?
  [[ -z "$out" && $rc == 0 ]] && check 1 || check 0 "$1: exit $rc, output: $out"
}
n+=1 sid="test-$n" transcript="$tmp/t$n.jsonl" envs=(CONTEXT_METER_KB=0)
: >"$transcript"; entry false claude-fable-1
quiet "garbage input" "$BASH" -c 'echo "not json {" | "$BASH" "$1"' _ "$here/context-meter.sh"
quiet "empty input" "$BASH" -c '"$BASH" "$1" </dev/null' _ "$here/context-meter.sh"
quiet "jq missing" "$BASH" -c 'PATH=/nonexistent; "$2" "$1" </dev/null' _ "$here/context-meter.sh" "$BASH"
quiet "bad session id" "$BASH" -c 'jq -cn "{session_id: \"../x\", tool_name: \"Read\", tool_response: \"x\"}" | "$BASH" "$1"' _ "$here/context-meter.sh"
quiet "bad budget" env CONTEXT_METER_KB=lots "$BASH" -c 'jq -cn --arg t "$2" "{session_id: \"s\", transcript_path: \$t, tool_name: \"Read\", tool_response: \"x\"}" | "$BASH" "$1"' _ "$here/context-meter.sh" "$transcript"
mkdir -p "$tmp/ro" && chmod 555 "$tmp/ro"
quiet "unwritable state" env XDG_STATE_HOME="$tmp/ro" CONTEXT_METER_KB=0 "$BASH" -c 'jq -cn --arg t "$2" "{session_id: \"s\", transcript_path: \$t, tool_name: \"Read\", tool_response: \"x\"}" | "$BASH" "$1"' _ "$here/context-meter.sh" "$transcript"
# A damaged state file starts over instead of going quiet for good.
printf 'garbage\n' >"$XDG_STATE_HOME/claude/context-meter/$sid"
out="$(call Read 10)"
[[ -n "$out" ]] && check 1 || check 0 "damaged state: expected a nudge"
# A tool_response that merely mentions agent_id is still metered.
out="$(jq -cn --arg s "$sid" --arg t "$transcript" '{session_id: $s, transcript_path: $t, hook_event_name: "PostToolUse", tool_name: "Read", tool_input: {}, tool_response: {content: "{\"agent_id\":\"a1\"}"}}' |
  env CONTEXT_METER_KB=0 "$BASH" "$here/context-meter.sh")"
[[ -n "$out" ]] && check 1 || check 0 "agent_id inside tool_response: expected a nudge"
# A big payload without "tool_input" (key order changed) is still metered, and
# fast: the fast path only searches the head (it used to take minutes at 1 MB).
to=()
[[ -x /usr/bin/timeout ]] && to=(/usr/bin/timeout -k 2 10)
out="$(jq -cn --arg s "$sid" --arg t "$transcript" '{session_id: $s, transcript_path: $t, hook_event_name: "PostToolUse", tool_name: "Read", tool_response: ("x" * 1000000)}' |
  env CONTEXT_METER_KB=0 ${to[@]+"${to[@]}"} "$BASH" "$here/context-meter.sh")"
[[ -n "$out" ]] && check 1 || check 0 "1 MB payload without tool_input: expected a nudge within 10 s"
# Old state files are pruned when a new session starts.
touch -t 202001010000 "$XDG_STATE_HOME/claude/context-meter/stale"
n+=1 sid="test-$n"; call Read 10 >/dev/null
[[ ! -e "$XDG_STATE_HOME/claude/context-meter/stale" ]] && check 1 || check 0 "stale state file not pruned"

printf '%d passed, %d failed\n' "$pass" "$fail"
((fail == 0))
