#!/usr/bin/env bash
#
# Runs the scenarios in teammate-sweep.cases through the hook the way Claude
# Code does (the Stop payload on stdin, sessions and team configs on disk, live
# teammates in the process table) and checks when it nudges, then checks that it
# stays silent and exits 0 when things break. Everything lives in a temp dir:
# CLAUDE_CONFIG_DIR, XDG_STATE_HOME and a fake `ps` first in PATH, so no real
# session, team, process or state is read or touched. Needs jq.
#
#   teammate-sweep.test.sh

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
hook="$here/teammate-sweep.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export XDG_STATE_HOME="$tmp/state"
state_dir="$XDG_STATE_HOME/claude/teammate-sweep"
seen_dir="$XDG_STATE_HOME/claude/teammate-sweep-seen"
mkdir -p "$tmp/bin"
printf '#!/bin/sh\ncat "%s/procs"\n' "$tmp" >"$tmp/bin/ps"
chmod +x "$tmp/bin/ps"
fake_path="$tmp/bin:$PATH"
base="$(date +%s)"
declare -i pass=0 fail=0 n=0 c=0
sid="" root="" lead="" cur="" bg="[]" last="" ver="" envs=()

check() { # <ok?> <description>
  if [[ "$1" == 1 ]]; then pass+=1; else fail+=1; printf 'FAIL  %s\n' "$2"; fi
}

new_sid() { c+=1; sid="sid-$n-$c"; }

lead_file() { # <pid> <session id>; version from $ver, left out when "-"
  jq -cn --argjson p "$1" --arg s "$2" --arg v "$ver" '
    {pid: $p, sessionId: $s, cwd: "/tmp", startedAt: 0} + (if $v == "-" then {} else {version: $v} end)
  ' >"$root/sessions/$1.json"
}

edit_team() { # <jq filter> [jq args ...]
  local cfg="$root/teams/$cur/config.json"
  jq "${@:2}" "$1" "$cfg" >"$cfg.tmp" && mv -f "$cfg.tmp" "$cfg"
}

proc_on() { printf 'claude --agent-name %s --team-name %s --agent-type x --agent-id %s@%s\n' "$1" "$cur" "$1" "$cur" >>"$tmp/procs"; }
proc_off() { # drop the line ending in this exact token
  grep -vxF -e "claude --agent-name $1 --team-name $cur --agent-type x --agent-id $1@$cur" "$tmp/procs" >"$tmp/procs.tmp"
  mv -f "$tmp/procs.tmp" "$tmp/procs"
}

stop() { # [active]
  local a=false
  [[ "${1:-}" == active ]] && a=true
  jq -cn --arg s "$sid" --argjson a "$a" --argjson bg "$bg" '
    {session_id: $s, transcript_path: "/tmp/none.jsonl", cwd: "/tmp", permission_mode: "default",
     hook_event_name: "Stop", stop_hook_active: $a, background_tasks: $bg}' |
    env CLAUDE_CONFIG_DIR="$root" PATH="$fake_path" ${envs[@]+"${envs[@]}"} "$BASH" "$hook"
}

# The nudge text, if the output is a Stop additionalContext nudge.
msg_of() { # <output>
  jq -er '
    select(.hookSpecificOutput.hookEventName? == "Stop") | .hookSpecificOutput.additionalContext
    | strings | select(startswith("Idle teammates still running: "))' <<<"$1" 2>/dev/null
}

step() { # <line>
  local line="$1" want out rc got text args
  case "$line" in
    session*)
      n+=1 c=0 root="$tmp/s$n" lead="" cur="" bg="[]" last="" ver=9.8.7
      rm -rf "$seen_dir"
      mkdir -p "$root/sessions" "$root/teams"
      printf '/sbin/launchd\n-zsh\nclaude --resume\nclaude --agent-id scout-2@alpha-x --agent-type scout\n' >"$tmp/procs"
      read -ra envs <<<"${line#session}"
      new_sid
      ;;
    lead\ *)
      local who="$sid" a
      read -r _ lead args <<<"$line"
      for a in $args; do
        case "$a" in
          other) who=someone-else ;;
          version=*) ver="${a#version=}" ;;
        esac
      done
      lead_file "$lead" "$who"
      ;;
    team\ *)
      read -r _ cur args <<<"$line"
      args="${args:-$lead}"
      mkdir -p "$root/teams/$cur"
      jq -n --arg t "$cur" --arg p "$args" '
        {name: $t, description: "", createdAt: 0, leadAgentId: ("team-lead@" + $t)}
        + (if $p == "-" then {} else {leadProcess: {pid: ($p | tonumber)}} end)
        + {members: [{agentId: ("team-lead@" + $t), name: "team-lead", agentType: "team-lead",
                      backendType: "in-process", joinedAt: 0, isActive: null}]}' >"$root/teams/$cur/config.json"
      ;;
    member\ *)
      local name type st age
      read -r _ name type st age <<<"$line"
      edit_team '.members = [.members[] | select(.name != $n)] + [
          {agentId: ($n + "@" + .name), name: $n, agentType: $ty, backendType: "tmux", joinedAt: $j}
          + (if $st == "idle" then {isActive: false} elif $st == "busy" then {isActive: true} else {} end)]' \
        --arg n "$name" --arg ty "$type" --arg st "$st" --argjson j "$(((base - age * 60) * 1000))"
      proc_off "$name"; proc_on "$name"
      ;;
    proc\ *) proc_off "${line#proc }"; proc_on "${line#proc }" ;;
    noproc\ *) proc_off "${line#noproc }" ;;
    gone\ *)
      edit_team '.members = [.members[] | select(.name != $n)]' --arg n "${line#gone }"
      proc_off "${line#gone }"
      ;;
    clear) new_sid; lead_file "$lead" "$sid" ;;
    compact) edit_team . -c ;;
    filler\ *)
      awk -v n="${line#filler }" 'BEGIN { for (i = 0; i < n; i++) printf "/usr/libexec/filler-%d --agent-name scout --team-name alpha --opt %0150d\n", i, i }' >>"$tmp/procs"
      ;;
    rewind\ *)
      local f="$state_dir/$sid" secs=$((${line#rewind } * 60))
      [[ -f "$f" ]] && awk -v s="$secs" '{ print $1, $2 - s }' "$f" >"$f.tmp" && mv -f "$f.tmp" "$f"
      ;;
    bg\ *)
      read -ra args <<<"${line#bg }"
      bg="$(printf '%s\n' "${args[@]}" | jq -cR '{id: "b1", type: ., status: "running", description: "background work", agent_type: "scout"}' | jq -cs .)"
      ;;
    seen\ ::\ * | unseen\ ::\ *)
      text="${line#* :: }"
      if [[ "$line" == seen* ]]; then
        [[ -f "$seen_dir/$text" ]] && check 1 || check 0 "session $n: no seen marker $text: $(ls "$seen_dir" 2>/dev/null | tr '\n' ' ')"
      else
        [[ ! -e "$seen_dir/$text" ]] && check 1 || check 0 "session $n: unexpected seen marker $text"
      fi
      ;;
    has\ ::\ * | lacks\ ::\ *)
      text="${line#* :: }"
      got="$(msg_of "$last")"
      if [[ "$line" == has* ]]; then
        [[ "$got" == *"$text"* ]] && check 1 || check 0 "session $n: nudge lacks \"$text\": ${got:-<none>}"
      else
        [[ -n "$got" && "$got" != *"$text"* ]] && check 1 || check 0 "session $n: nudge has \"$text\": ${got:-<none>}"
      fi
      ;;
    *)
      want="${line%% :: *}"
      read -r _ args <<<"${line#* :: }"
      out="$(stop "$args")"
      rc=$?
      bg="[]"
      if [[ -z "$out" ]]; then
        got=quiet
      elif msg_of "$out" >/dev/null; then
        got=nudge last="$out"
      else
        got="unexpected output: $out"
      fi
      [[ "$got" == "$want" && $rc == 0 ]] && check 1 || check 0 "session $n: $line -> $got (exit $rc)"
      ;;
  esac
}

while IFS= read -r line; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  step "$line"
done <"$here/teammate-sweep.cases"

# Failure modes: always exit 0 with no output, and the next call still works.
quiet() { # <description> <command...>
  local out rc
  out="$("${@:2}")"; rc=$?
  [[ -z "$out" && $rc == 0 ]] && check 1 || check 0 "$1: exit $rc, output: $out"
}
fixture() { for l in session "lead 4242" "team alpha" "member scout scout idle 5"; do step "$l"; done; }
fixture
quiet "garbage input" "$BASH" -c 'echo "not json {" | "$BASH" "$1"' _ "$hook"
quiet "empty input" "$BASH" -c '"$BASH" "$1" </dev/null' _ "$hook"
quiet "non-object input" "$BASH" -c 'echo "[1]" | "$BASH" "$1"' _ "$hook"
quiet "jq missing" "$BASH" -c 'PATH=/nonexistent; "$2" "$1" <<<"{\"session_id\":\"$3\"}"' _ "$hook" "$BASH" "$sid"
quiet "bad session id" "$BASH" -c 'echo "{\"session_id\":\"../x\",\"stop_hook_active\":false}" | CLAUDE_CONFIG_DIR="$2" PATH="$3" "$BASH" "$1"' _ "$hook" "$root" "$fake_path"
mkdir -p "$tmp/ro" && chmod 555 "$tmp/ro"
envs=(XDG_STATE_HOME="$tmp/ro")
quiet "unwritable state" stop
envs=()
step "nudge :: stop"
# background_tasks missing or not an array means no tasks
fixture
out="$(jq -cn --arg s "$sid" '{session_id: $s, stop_hook_active: false}' |
  env CLAUDE_CONFIG_DIR="$root" PATH="$fake_path" "$BASH" "$hook")"
msg_of "$out" >/dev/null && check 1 || check 0 "no background_tasks: expected a nudge, got: ${out:-<none>}"
fixture
out="$(jq -cn --arg s "$sid" '{session_id: $s, stop_hook_active: false, background_tasks: "subagent"}' |
  env CLAUDE_CONFIG_DIR="$root" PATH="$fake_path" "$BASH" "$hook")"
msg_of "$out" >/dev/null && check 1 || check 0 "string background_tasks: expected a nudge, got: ${out:-<none>}"
# A truncated team config is skipped; a good one beside it still counts.
fixture
head -c 40 "$root/teams/alpha/config.json" >"$root/teams/alpha/config.tmp"
mv -f "$root/teams/alpha/config.tmp" "$root/teams/alpha/config.json"
quiet "truncated config.json" stop
printf '{"sessionId":"%s",' "$sid" >"$root/sessions/77.json"
step "team beta"
step "member b scout idle 5"
step "nudge :: stop"
step "has :: running: b (scout)."
# A truncated or wrong sessions file for this id doesn't hide the real one.
fixture
printf '{"sessionId":"%s",' "$sid" >"$root/sessions/1.json"
printf '{"sessionId":"%s-not"}' "$sid" >"$root/sessions/2.json"
step "nudge :: stop"
# Damaged state lines are dropped, not fatal.
fixture
mkdir -p "$state_dir" && printf 'garbage\n\nscout:1 nope\n' >"$state_dir/$sid"
step "nudge :: stop"
step "quiet :: stop"
[[ "$(<"$state_dir/$sid")" =~ ^scout:[0-9]+\ [0-9]+$ ]] && check 1 || check 0 "damaged state not rewritten: $(<"$state_dir/$sid")"
# Old state files are pruned when a new session's file is created; an old seen
# marker, kept beside the state dir, survives it.
touch -t 202001010000 "$state_dir/stale"
fixture
mkdir -p "$seen_dir" && touch -t 202001010000 "$seen_dir/1.0.0"
step "nudge :: stop"
[[ ! -e "$state_dir/stale" ]] && check 1 || check 0 "stale state file not pruned"
step "seen :: 1.0.0"
step "seen :: 9.8.7"
# A seen marker that can't be written changes nothing else.
fixture
mkdir -p "$XDG_STATE_HOME/claude" && : >"$seen_dir"
step "nudge :: stop"
step "has :: running: scout (scout)."
rm -f "$seen_dir"

printf '%d passed, %d failed\n' "$pass" "$fail"
((fail == 0))
