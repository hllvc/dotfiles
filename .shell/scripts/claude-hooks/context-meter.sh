#!/usr/bin/env bash
#
# Claude Code PostToolUse hook (no matcher, so every tool and MCP tool): a
# nudge for orchestrator sessions. When the main thread runs on a model matching
# CONTEXT_METER_MODELS (default fable|mythos, case-insensitive), it adds up the
# tool output the main thread pulls straight into its own context, and once
# CONTEXT_METER_KB (default 64) or CONTEXT_METER_CALLS (default 20) is reached
# since the last reminder it injects a short "delegate this" reminder as
# additionalContext. Registered in .claude/settings.json without onFailure, and
# it always exits 0 with no output on any error: it never blocks anything.
#
# - Subagent calls carry agent_id in the hook input (main-thread calls don't);
#   they're skipped before jq runs.
# - The hook input has no model field, so the model is the newest main-thread
#   assistant entry in the tail of transcript_path, cached for 20s
#   (/model can switch it mid-session; CONTEXT_METER_MODEL_TTL overrides).
# - Delegation and meta tools (Agent, SendMessage, Skill, ...) aren't metered;
#   Edit/Write/NotebookEdit add bytes but don't count as calls.
# - State: one line per session in $XDG_STATE_HOME/claude/context-meter/,
#   pruned after 7 days whenever a new session starts.
#
# Cases it must keep getting right: context-meter.test.sh.

set -u
exec 2>/dev/null
trap 'exit 0' EXIT

input="$(cat)" || exit 0

# Fast path, no jq: subagent payloads put "agent_id" ahead of "tool_input", so
# only that header is checked (tool output can't fake it).
head="${input%%\"tool_input\":*}"
[[ "$head" == *'"agent_id":"'[!\"]* ]] && exit 0

command -v jq >/dev/null || exit 0

MODEL_TTL="${CONTEXT_METER_MODEL_TTL:-20}"
kb_limit="${CONTEXT_METER_KB:-64}"
calls_limit="${CONTEXT_METER_CALLS:-20}"
models="${CONTEXT_METER_MODELS:-fable|mythos}"
[[ "$kb_limit" =~ ^[0-9]+$ && "$calls_limit" =~ ^[0-9]+$ && "$MODEL_TTL" =~ ^[0-9]+$ ]] || exit 0

# session_id, transcript_path, tool_name, response bytes, now, agent_id: one
# per line. agent_id again in case the key order ever changes.
fields="$(jq -r '
  (.tool_response // "" | if type == "string" then . else tojson end | utf8bytelength) as $b
  | (.session_id // ""), (.transcript_path // ""), (.tool_name // ""), $b, (now | floor),
    (.agent_id // "")
' <<<"$input")" || exit 0
{ read -r sid; read -r transcript; read -r tool; read -r bytes; read -r now; read -r agent; } <<<"$fields"
[[ -z "$agent" ]] || exit 0
[[ "$sid" =~ ^[A-Za-z0-9._-]+$ && "$bytes" =~ ^[0-9]+$ && "$now" =~ ^[0-9]+$ ]] || exit 0

case "$tool" in
  # Delegation and its bookkeeping: intended inflow, not reading.
  Agent | Task | SendMessage | Workflow | TaskStop | Skill | ToolSearch | AskUserQuestion) exit 0 ;;
  TaskCreate | TaskUpdate | TaskList | TaskGet | TodoWrite | ListAgents | ReadNotifications) exit 0 ;;
  Edit | Write | MultiEdit | NotebookEdit) count=0 ;;
  *) count=1 ;;
esac

dir="${XDG_STATE_HOME:-$HOME/.local/state}/claude/context-meter"
state="$dir/$sid"

# win_bytes win_calls total_bytes total_calls model_checked_at model
win_bytes=0 win_calls=0 total_bytes=0 total_calls=0 checked=0 model=-
if [[ -f "$state" ]]; then
  read -r win_bytes win_calls total_bytes total_calls checked model <"$state"
  # A damaged state line starts the session over rather than stalling it.
  for n in "$win_bytes" "$win_calls" "$total_bytes" "$total_calls" "$checked"; do
    [[ "$n" =~ ^[0-9]+$ ]] || { win_bytes=0 win_calls=0 total_bytes=0 total_calls=0 checked=0 model=-; break; }
  done
else
  mkdir -p "$dir" || exit 0
  # New session: drop state left by sessions idle for over 7 days.
  find "$dir" -type f -mtime +7 -delete
fi

refreshed=0
if ((now - checked >= MODEL_TTL)) || [[ -z "$model" ]]; then
  refreshed=1 model=-
  if [[ -f "$transcript" ]]; then
    # Only the tail; the newest main-thread assistant entry wins. Subagent turns
    # live in separate files, isSidechain is excluded anyway.
    found="$(tail -c 2097152 "$transcript" | grep -F '"type":"assistant"' | tail -n 50 |
      jq -Rr 'fromjson? | select(.type == "assistant" and (.isSidechain | not))
        | .message.model // empty | select(. != "<synthetic>")' | tail -n 1)"
    [[ -n "$found" ]] && model="$found"
  fi
  checked="$now"
fi

save() {
  printf '%s %s %s %s %s %s\n' "$win_bytes" "$win_calls" "$total_bytes" "$total_calls" "$checked" "$model" \
    >"$state.$$" && mv -f "$state.$$" "$state"
}

shopt -s nocasematch
if [[ "$model" == - || ! "$model" =~ $models ]]; then
  # Not an orchestrator model: no metering, only a fresh model lookup is kept.
  ((refreshed)) && save
  exit 0
fi
shopt -u nocasematch

win_bytes=$((win_bytes + bytes)) win_calls=$((win_calls + count))
total_bytes=$((total_bytes + bytes)) total_calls=$((total_calls + count))

out=""
if ((win_bytes >= kb_limit * 1024 || win_calls >= calls_limit)); then
  kb=$(((win_bytes + 512) / 1024)) total_kb=$(((total_bytes + 512) / 1024))
  noun=calls
  ((win_calls == 1)) && noun=call
  msg="Context meter: ~$kb KB of tool output across $win_calls direct $noun has gone straight into your context since the last reminder ($total_kb KB this session). You are the orchestrator: hand further reading, searching and test runs to scout, researcher or runner, and implementation to builder. Small targeted reads and reviewing a worker's git diff are fine."
  out="$(jq -cn --arg m "$msg" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}')" || exit 0
  win_bytes=0 win_calls=0
fi

save || exit 0
[[ -n "$out" ]] && printf '%s\n' "$out"
exit 0
