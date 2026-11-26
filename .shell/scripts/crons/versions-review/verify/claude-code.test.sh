#!/usr/bin/env bash
#
# Runs claude-code.sh against fixtures: sessions and team configs under a temp
# CLAUDE_CONFIG_DIR, the seen marker under a temp XDG_STATE_HOME, and a fake
# `ps` first in PATH printing a fixture process table, so no real session,
# team, process or state is read. VERIFY_SUITES=0 for the fixture cases (the
# suite step is checked separately against stub suites in a temp repo root, so
# this never recurses into teammate-sweep.test.sh). Needs jq.
#
#   claude-code.test.sh

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
script="$here/claude-code.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
printf '#!/bin/sh\ncat "%s/procs"\n' "$tmp" >"$tmp/bin/ps"
chmod +x "$tmp/bin/ps"
fake_path="$tmp/bin:$PATH"
V=2.1.400 OLD=2.1.399
now_ms="$(($(date +%s) * 1000))"
declare -i pass=0 fail=0 n=0
root="" out="" rc=0

check() { # <ok?> <description>
  if [[ "$1" == 1 ]]; then pass+=1; else fail+=1; printf 'FAIL  %s\n' "$2"; fi
}

fresh() { # new config root, process table and state
  n+=1
  root="$tmp/c$n"
  rm -rf "$tmp/state"
  mkdir -p "$root/sessions" "$root/teams" "$tmp/state"
  printf '1 05-01:00:00 /sbin/launchd\n77 10:00 -zsh\n' >"$tmp/procs"
}

# session <pid> <sid> [version|-] [etime]: a live lead with its sessions file.
session() {
  jq -cn --argjson p "$1" --arg s "$2" --arg v "${3:-$V}" --argjson t "$now_ms" '
    {pid: $p, sessionId: $s, cwd: "/tmp", startedAt: ($t - 3600000), kind: "interactive"}
    + (if $v == "-" then {} else {version: $v} end)' >"$root/sessions/$1.json"
  proc "$1" "${4:-01:00:00}" "claude --settings {} --resume $2"
}

proc() { printf '%s %s %s\n' "$@" >>"$tmp/procs"; } # <pid> <etime> <args>

# team <name> <lead pid|-> <lead sid> [member json ...]
team() {
  local t="$1" p="$2" s="$3"
  shift 3
  mkdir -p "$root/teams/$t"
  printf '%s\n' "$@" | jq -s --arg t "$t" --arg p "$p" --arg s "$s" '
    {name: $t, leadSessionId: $s}
    + (if $p == "-" then {} else {leadProcess: {pid: ($p | tonumber)}} end)
    + {members: ([{name: "team-lead", backendType: "in-process", joinedAt: 1, isActive: null}] + .)}' \
    >"$root/teams/$t/config.json"
}

# member json: <name> [isActive: true|false|-]
mem() {
  jq -cn --arg n "$1" --arg a "${2:-true}" '
    {name: $n, backendType: "tmux", joinedAt: 2} + (if $a == "-" then {} else {isActive: ($a == "true")} end)'
}

# worker <pid> <name> <team> <parent sid> [binary version]
worker() {
  proc "$1" 05:00 "/Users/u/.local/share/claude/versions/${5:-$V} --agent-id $2@$3 --agent-name $2 --team-name $3 --agent-color cyan --parent-session-id $4"
}

marker() { mkdir -p "$tmp/state/claude/teammate-sweep-seen" && : >"$tmp/state/claude/teammate-sweep-seen/$1"; }

run() { # [version]
  out="$(cd "$tmp" && env CLAUDE_CONFIG_DIR="$root" XDG_STATE_HOME="$tmp/state" PATH="$fake_path" \
    VERIFY_SUITES=0 "$BASH" "$script" "${1:-$V}")"
  rc=$?
}

expect() { # <description> <exit code> <first line>
  local first="${out%%$'\n'*}"
  [[ "$rc" == "$2" && "$first" == "$3" ]] && check 1 ||
    check 0 "$1: want $2 \"$3\", got $rc: $(printf '%s' "$out" | tr '\n' '|')"
}

OK="verified: hook suite, session files, lead side, worker side"

# 1. Everything in place, a live worker resolves: ok
fresh
session 4242 sid-a
team alpha 4242 sid-a "$(mem scout true)" "$(mem build false)"
worker 5001 scout alpha sid-a
worker 5002 build alpha sid-a
run
expect "ok, live worker" 0 "$OK"

# 2. The seen marker alone is enough on the worker side
fresh
session 4242 sid-a
team alpha 4242 sid-a
marker "$V"
run
expect "ok, marker" 0 "$OK"

# 3. Pending: no marker, no live worker (a marker for another version doesn't count)
fresh
session 4242 sid-a
team alpha 4242 sid-a
marker "$OLD"
run
expect "pending, no marker" 3 "no teammate seen on the installed version yet"
# ...a just-spawned worker (no isActive yet) is no evidence either way
team alpha 4242 sid-a "$(mem fresh -)"
worker 5001 fresh alpha sid-a
run
expect "pending, just spawned" 3 "no teammate seen on the installed version yet"
# ...nor is a resolving worker on another version's binary
team alpha 4242 sid-a "$(mem fresh -)" "$(mem scout true)"
worker 5002 scout alpha sid-a "$OLD"
run
expect "pending, old-binary worker" 3 "no teammate seen on the installed version yet"

# 4. Pending: only sessions on older versions
fresh
session 4242 sid-a "$OLD"
team alpha 4242 sid-a "$(mem scout true)"
worker 5001 scout alpha sid-a "$OLD"
marker "$V"
run
expect "pending, only older sessions" 3 "no session runs the installed version yet"
# The first line stays the same whatever the pids and names
fresh
session 999 sid-zz "$OLD"
marker "$V"
run
expect "pending, stable reason" 3 "no session runs the installed version yet"

# 5. Fail: a live session file without sessionId (a dead pid's file is ignored)
fresh
session 4242 sid-a
team alpha 4242 sid-a
marker "$V"
printf '{"pid":31,"version":"%s"}' "$V" >"$root/sessions/31.json"
run
expect "dead file ignored" 0 "$OK"
proc 31 10:00 "claude"
run
expect "fail, no sessionId" 1 "a live session file lacks a string sessionId or version"
# ...or without a version
fresh
session 4242 sid-a -
marker "$V"
run
expect "fail, no version" 1 "a live session file lacks a string sessionId or version"

# 6. Fail: a config names the session by leadSessionId but has another pid
fresh
session 4242 sid-a
team alpha 4243 sid-a
marker "$V"
run
expect "fail, leadSessionId without pid" 1 "a team config names a session by leadSessionId but not by leadProcess.pid"
# ...or no leadProcess at all, when written since the session started
fresh
session 4242 sid-a
team alpha - sid-a
marker "$V"
run
expect "fail, fresh config without leadProcess" 1 "a team config names a session by leadSessionId but not by leadProcess.pid"
# ...but an untouched older-format config is no evidence
touch -t 202001010000 "$root/teams/alpha/config.json"
run
expect "pending, old-format config" 3 "no team config links a session on the installed version yet"
# ...and a stale config with another pid doesn't matter once one has this pid
team beta 4242 sid-b
team alpha 4243 sid-a
run
expect "ok, linked despite stale" 0 "$OK"

# 7. Fail: lead config members with the wrong field types
fresh
session 4242 sid-a
team alpha 4242 sid-a '{"name":"x","backendType":"tmux","joinedAt":"soon"}'
marker "$V"
run
expect "fail, malformed members" 1 "a lead's team config has members without string name, backendType or numeric joinedAt"

# 8. Fail: a live --agent-id that doesn't resolve
fresh
session 4242 sid-a
team alpha 4242 sid-a "$(mem scout true)"
marker "$V"
worker 5001 ghost alpha sid-a
worker 5002 scout beta sid-a
run
expect "fail, unresolvable agent-id" 1 "a live teammate --agent-id does not resolve to a tmux member"
[[ "$out" == *ghost@alpha* && "$out" == *scout@beta* ]] && check 1 || check 0 "unresolved ids not listed: $out"
# ...but not for a teammate of an unknown session (another config root) or an
# older binary
fresh
session 4242 sid-a
team alpha 4242 sid-a
marker "$V"
worker 5001 ghost alpha sid-elsewhere
worker 5002 ghost2 alpha sid-a "$OLD"
run
expect "unknown parent and old binary skipped" 0 "$OK"

# 9. Fail: interactive claude running, but no session file at all
fresh
proc 4242 03:00 "claude --settings {} --resume sid-a"
run
expect "fail, leads without files" 1 "claude sessions are running but none has a session file"
# ...not for one under a minute old, helpers, subcommands or print mode
fresh
proc 4242 00:40 "claude"
proc 4243 01:00:00 "/Users/u/.local/bin/claude --chrome-native-host"
proc 4244 01:00:00 "claude mcp serve"
proc 4245 01:00:00 "claude -p hello"
proc 4246 1-01:00:00 "claude --print"
run
expect "no false lead" 3 "no session runs the installed version yet"
# ...while one running for over a day counts
fresh
proc 4242 1-02:03:04 "claude"
run
expect "fail, day-old lead" 1 "claude sessions are running but none has a session file"

# 10. Usage and missing tools
fresh
run 2.1.x
[[ "$rc" != 0 && "$rc" != 3 && -n "$out" ]] && check 1 || check 0 "bad version: got $rc: $out"
out="$(cd "$tmp" && env PATH=/nonexistent VERIFY_SUITES=0 "$BASH" "$script" "$V")"
rc=$?
expect "jq missing" 1 "jq missing"

# 11. The suite step, against stub suites in a temp repo root
suite_run() { # <stub body>
  local r="$tmp/repo$n"
  mkdir -p "$r/.shell/scripts/claude-hooks"
  printf '%s\n' "$1" >"$r/.shell/scripts/claude-hooks/teammate-sweep.test.sh"
  out="$(cd "$r" && env CLAUDE_CONFIG_DIR="$root" XDG_STATE_HOME="$tmp/state" PATH="$fake_path" "$BASH" "$script" "$V")"
  rc=$?
}
fresh
session 4242 sid-a
team alpha 4242 sid-a
marker "$V"
suite_run 'echo "9 passed, 0 failed"'
expect "suite passes" 0 "$OK"
fresh
session 4242 sid-a
team alpha 4242 sid-a
marker "$V"
suite_run 'echo "8 passed, 1 failed"; exit 1'
first="${out%%$'\n'*}"
[[ "$rc" == 1 && "$first" == "teammate-sweep.test.sh failed under "*bash && "$out" == *"1 failed"* ]] &&
  check 1 || check 0 "suite failure: got $rc: $(printf '%s' "$out" | tr '\n' '|')"
[[ "$out" == *"also: teammate-sweep.test.sh failed under /bin/bash"* || "$first" == *"under /bin/bash" ]] &&
  check 1 || check 0 "suite failure does not name /bin/bash: $out"
out="$(cd "$tmp" && env CLAUDE_CONFIG_DIR="$root" XDG_STATE_HOME="$tmp/state" PATH="$fake_path" "$BASH" "$script" "$V")"
rc=$?
first="${out%%$'\n'*}"
[[ "$rc" == 1 && "$first" == "hook suite cannot run: "* ]] && check 1 || check 0 "missing suite: got $rc: $out"

printf '%d passed, %d failed\n' "$pass" "$fail"
((fail == 0))
