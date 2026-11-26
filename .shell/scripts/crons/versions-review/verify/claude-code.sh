#!/usr/bin/env bash
#
# Verify step for claude-code (see dotctl versions verify): checks that the
# undocumented Claude Code internals teammate-sweep.sh and context-meter.sh read
# still look the way they expect on the installed CLI version.
#
#   claude-code.sh <installed-version>     run from the repo root
#
# Exit 0 = verified, 3 = pending (needs evidence only real use produces),
# anything else = failed. The first stdout line is the reason and stays stable
# across runs (no pids, names, counts or dates); detail lines follow. A check
# that can't run fails; a failure needs a positive witness, mere absence of
# evidence is pending.
#
# - Hook suites: teammate-sweep, context-meter and aws-profile-guard .test.sh
#   pass under `bash` (PATH) and /bin/bash (3.2, what a session without
#   Homebrew in PATH runs the hooks with), each run under /usr/bin/timeout -k 5
#   60 (it kills the whole process group). VERIFY_SUITES=0 skips them all.
# - Session files: every live $root/sessions/<pid>.json has a string sessionId
#   and version (a bad one is re-read once after 2 s). Fails too when
#   interactive `claude` leads have run for a minute or more but no live file
#   exists at all: argv[0] exactly `claude` (as typed in a shell, which helpers
#   started by full path never show), no subcommand, no -p/--print.
# - Lead side, sessions on the installed version: a team config whose
#   leadProcess.pid is the session's pid, with members of string name and
#   backendType and numeric joinedAt. Fails when such a config has malformed
#   members, or when none exists but a config written since the session started
#   names it by leadSessionId (an untouched older-format config is no evidence).
#   Pending when no session runs the installed version or none is linked yet.
# - Worker side: the hook's seen marker for the installed version, or a live
#   `--agent-id <name>@<team>` on the installed binary resolving now to a tmux
#   member with a boolean isActive. Fails when a live teammate, whose
#   --parent-session-id this config root knows, doesn't resolve to a tmux member
#   (rechecked once after 2 s). Teammates on another version's binary are
#   skipped. Pending when no worker has been seen on this version.
# - Transcripts: the real context-meter.sh, fed a synthetic PostToolUse call
#   pointing at $root/projects/*/<sessionId>.jsonl of a live session on the
#   installed version (temp state, budget 0, any model, no model cache), nudges,
#   i.e. it read the main thread's model there. Fails when it doesn't for any
#   session while one transcript's tail (the part the hook reads) has a
#   non-sidechain, non-synthetic "type"/"role": "assistant" line. Pending when
#   none has one yet. Only whether the hook nudged is looked at: no transcript
#   content is printed or kept.
#
# root = CLAUDE_CONFIG_DIR or ~/.claude; marker dir from XDG_STATE_HOME; `ps`
# from PATH. The process table goes to a temp file, never a shell variable.

set -u

v="${1:-}"
if [[ ! "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "installed version argument is not x.y.z"
  exit 2
fi

root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
seen="${XDG_STATE_HOME:-$HOME/.local/state}/claude/teammate-sweep-seen/$v"
hooks=.shell/scripts/claude-hooks
suites=(teammate-sweep context-meter aws-profile-guard)

fails=() pends=() notes=()
fail() { fails+=("$1"); shift; for d in "$@"; do notes+=("  $d"); done; }
pend() { pends+=("$1"); }

finish() {
  if ((${#fails[@]})); then
    printf '%s\n' "${fails[0]}"
    for r in "${fails[@]:1}"; do printf '  also: %s\n' "$r"; done
    ((${#notes[@]})) && printf '%s\n' "${notes[@]}"
    exit 1
  fi
  if ((${#pends[@]})); then
    printf '%s\n' "${pends[0]}"
    for r in "${pends[@]:1}"; do printf '  also: %s\n' "$r"; done
    exit 3
  fi
  echo "verified: hook suites, session files, lead side, worker side, transcripts"
  exit 0
}

if ! command -v jq >/dev/null; then
  fail "jq missing"
  finish
fi

tmp="$(mktemp -d)" || { fail "cannot create a temp dir"; finish; }
trap 'rm -rf "$tmp"' EXIT

# --- Hook suites ------------------------------------------------------------
if [[ "${VERIFY_SUITES:-1}" != 0 ]]; then
  shells=()
  for sh in "$(command -v bash)" /bin/bash; do
    if [[ -x "$sh" ]]; then shells+=("$sh"); else fail "hook suite cannot run: no interpreter ${sh:-bash}"; fi
  done
  if [[ ! -x /usr/bin/timeout ]]; then
    fail "hook suite cannot run: /usr/bin/timeout missing"
  else
    for name in "${suites[@]}"; do
      suite="$hooks/$name.test.sh"
      if [[ ! -f "$suite" ]]; then
        fail "hook suite cannot run: $suite not found from the working directory"
        continue
      fi
      for sh in ${shells[@]+"${shells[@]}"}; do
        # Output to a file, so a stray descendant can't hold a pipe open.
        /usr/bin/timeout -k 5 60 "$sh" "$suite" </dev/null >"$tmp/suite.log" 2>&1
        rc=$?
        if ((rc == 124 || rc == 137)); then
          fail "$name.test.sh timed out under $sh"
        elif ((rc != 0)); then
          detail=()
          while IFS= read -r l; do detail+=("$l"); done < <(tail -n 5 "$tmp/suite.log")
          fail "$name.test.sh failed under $sh" ${detail[@]+"${detail[@]}"}
        fi
      done
    done
  fi
fi

# --- Process snapshot ---------------------------------------------------------
# pids: every pid. leads: interactive `claude` leads running >= 60 s.
# agents: "<id> <argv0> <parent session id or ->" per --agent-id.
snap() {
  : >"$tmp/pids"; : >"$tmp/leads"; : >"$tmp/agents"
  ps -axo pid=,etime=,args= >"$tmp/ps" || return 1
  awk -v d="$tmp" '
    $1 !~ /^[0-9]+$/ { next }
    {
      print $1 > (d "/pids")
      id = ""; par = "-"
      for (i = 4; i < NF; i++) {
        if ($i == "--agent-id") id = $(i + 1)
        if ($i == "--parent-session-id") par = $(i + 1)
      }
      if (id != "") { print id, $3, par > (d "/agents"); next }
      if ($3 != "claude" || (NF >= 4 && $4 !~ /^-/)) next
      for (i = 4; i <= NF; i++)
        if ($i == "-p" || $i == "--print" || $i == "--chrome-native-host" || $i == "-v" || $i == "--version" || $i == "-h" || $i == "--help") next
      n = split($2, t, ":")
      if ($2 !~ /-/ && n < 3 && t[1] + 0 < 1) next
      print $1 > (d "/leads")
    }' "$tmp/ps"
}
if ! snap; then
  fail "ps failed"
  finish
fi

# --- Session files -----------------------------------------------------------
# Live files: those whose pid is in the process table.
printf '%s\n' "$root"/sessions/*.json |
  awk -F/ 'NR == FNR { live[$1] = 1; next }
    { f = $NF; sub(/\.json$/, "", f); if (f ~ /^[0-9]+$/ && (f in live)) print f "\t" $0 }' "$tmp/pids" - >"$tmp/live"

read_session() { # <file> -> "<sessionId> <version> <startedAt seconds>" or "bad"
  jq -r 'if (.sessionId | type) == "string" and (.version | type) == "string"
    then [.sessionId, .version, ((.startedAt | numbers) // 0 | ./1000 | floor | tostring)] | join(" ")
    else "bad" end' "$1" 2>/dev/null || echo bad
}

: >"$tmp/cur"
nlive=0
while IFS=$'\t' read -r p f; do
  [[ -f "$f" ]] || continue
  nlive=$((nlive + 1))
  row="$(read_session "$f")"
  if [[ "$row" == bad ]]; then
    sleep 2
    [[ -f "$f" ]] || continue
    row="$(read_session "$f")"
  fi
  read -r s ver started <<<"$row"
  if [[ "$row" == bad || ! "$s" =~ ^[A-Za-z0-9._-]+$ ]]; then
    fail "a live session file lacks a string sessionId or version" "$f"
    continue
  fi
  [[ "$ver" == "$v" ]] && printf '%s %s %s\n' "$p" "$s" "$started" >>"$tmp/cur"
done <"$tmp/live"

if ((nlive == 0)) && [[ -s "$tmp/leads" ]]; then
  fail "claude sessions are running but none has a session file" "lead pids: $(tr '\n' ' ' <"$tmp/leads")"
fi

# --- Lead side ---------------------------------------------------------------
configs() { # <grep -E pattern> -> team configs mentioning it
  grep -lE -- "$1" "$root"/teams/*/config.json 2>/dev/null
}

if [[ ! -s "$tmp/cur" ]]; then
  pend "no session runs the installed version yet"
else
  linked=""
  while read -r p s started; do
    good="" badm="" witness=""
    while IFS= read -r c; do
      r="$(jq -r --argjson pid "$p" '
        select(type == "object" and (.leadProcess | type) == "object" and .leadProcess.pid == $pid)
        | if (.members | type) == "array" and (.members | length) > 0
            and all(.members[]; type == "object" and (.name | type) == "string"
              and (.backendType | type) == "string" and (.joinedAt | type) == "number")
          then "good" else "bad" end' "$c" 2>/dev/null)"
      [[ "$r" == good ]] && good="$c"
      [[ "$r" == bad ]] && badm="$c"
    done < <(configs "\"pid\"[[:space:]]*:[[:space:]]*$p([^0-9]|\$)")
    if [[ -z "$good" ]]; then
      while IFS= read -r c; do
        m="$(stat -f %m "$c" 2>/dev/null)" || continue
        if [[ ! "$m" =~ ^[0-9]+$ ]] || ((m < started - 60)); then continue; fi
        r="$(jq -r --arg s "$s" --argjson pid "$p" '
          select(type == "object" and .leadSessionId == $s
            and ((.leadProcess | type) != "object" or .leadProcess.pid != $pid)) | "hit"' "$c" 2>/dev/null)"
        [[ "$r" == hit ]] && witness="$c"
      done < <(configs "\"$s\"")
    fi
    if [[ -n "$good" ]]; then
      linked=1
    elif [[ -n "$badm" ]]; then
      fail "a lead's team config has members without string name, backendType or numeric joinedAt" "$badm"
    elif [[ -n "$witness" ]]; then
      fail "a team config names a session by leadSessionId but not by leadProcess.pid" "$witness (pid $p)"
    fi
  done <"$tmp/cur"
  [[ -n "$linked" ]] || pend "no team config links a session on the installed version yet"
fi

# --- Worker side -------------------------------------------------------------
# resolve <name> <team>: "ok" (tmux, boolean isActive), "new" (tmux, no flag
# yet) or nothing.
resolve() {
  local c r
  while IFS= read -r c; do
    r="$(jq -r --arg t "$2" --arg n "$1" '
      select(type == "object" and .name == $t) | (.members // [])[]?
      | select(type == "object" and .name == $n and .backendType == "tmux")
      | if (.isActive | type) == "boolean" then "ok" else "new" end' "$c" 2>/dev/null)"
    [[ "$r" == *ok* ]] && { echo ok; return; }
    [[ "$r" == *new* ]] && { echo new; return; }
  done < <(grep -lF -- "\"$2\"" "$root"/teams/*/config.json 2>/dev/null)
}

# known <parent session id>: this config root has a session or team for it.
known() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
  grep -qF -- "\"$1\"" "$root"/teams/*/config.json "$root"/sessions/*.json 2>/dev/null
}

check_workers() { # appends unresolved ids to $tmp/unres; sets worker_ok
  local id a0 par name team b r
  : >"$tmp/unres"
  while read -r id a0 par; do
    name="${id%@*}" team="${id#*@}"
    [[ "$id" == *@* && "$name" =~ ^[A-Za-z0-9._-]+$ && "$team" =~ ^[A-Za-z0-9._-]+$ ]] || continue
    b="${a0##*/}"
    [[ "$a0" == */versions/* && "$b" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$b" != "$v" ]] && continue
    r="$(resolve "$name" "$team")"
    if [[ "$r" == ok ]]; then
      [[ "$a0" == */versions/"$v" ]] && worker_ok=1
    elif [[ -z "$r" ]] && known "$par"; then
      echo "$id" >>"$tmp/unres"
    fi
  done <"$tmp/agents"
}

worker_ok=""
[[ -e "$seen" ]] && worker_ok=1
check_workers
if [[ -s "$tmp/unres" ]]; then
  cp "$tmp/unres" "$tmp/unres.first"
  sleep 2
  snap || { fail "ps failed"; finish; }
  check_workers
  # Only ids unresolved both times count.
  unres="$(grep -xF -f "$tmp/unres.first" "$tmp/unres" | tr '\n' ' ')"
  [[ -n "$unres" ]] && fail "a live teammate --agent-id does not resolve to a tmux member" "ids: $unres"
fi
[[ -n "$worker_ok" ]] || pend "no teammate seen on the installed version yet"

# --- Transcripts -------------------------------------------------------------
meter="$hooks/context-meter.sh"

# meter_nudges <transcript> <session id>: the real hook, on one synthetic call
# with its budget at 0 and any model accepted, nudges, so it found a model.
meter_nudges() {
  local out
  out="$(jq -cn --arg s "$2" --arg t "$1" '
    {session_id: $s, transcript_path: $t, hook_event_name: "PostToolUse",
     tool_name: "Read", tool_input: {}, tool_response: "x", tool_use_id: "toolu_verify"}' |
    env XDG_STATE_HOME="$tmp/meter" CONTEXT_METER_KB=0 CONTEXT_METER_CALLS=1 \
      CONTEXT_METER_MODELS=. CONTEXT_METER_MODEL_TTL=0 /usr/bin/timeout -k 2 10 "$BASH" "$meter" 2>/dev/null)"
  jq -e '.hookSpecificOutput.additionalContext | startswith("Context meter:")' <<<"$out" >/dev/null 2>&1
}

# has_assistant <transcript>: the tail the hook reads has a main-thread,
# non-synthetic assistant line (looser than the hook's own filter on purpose).
has_assistant() {
  tail -c 2097152 "$1" | grep -E '"(type|role)"[[:space:]]*:[[:space:]]*"assistant"' |
    grep -vE '"isSidechain"[[:space:]]*:[[:space:]]*true|<synthetic>' | grep -q .
}

if [[ -s "$tmp/cur" ]]; then
  if [[ ! -f "$meter" ]]; then
    fail "transcript check cannot run: $meter not found from the working directory"
  elif [[ ! -x /usr/bin/timeout ]]; then
    fail "transcript check cannot run: /usr/bin/timeout missing"
  else
    meter_ok="" witness="" i=0
    while read -r p s started; do
      for t in "$root"/projects/*/"$s".jsonl; do
        [[ -f "$t" ]] || continue
        i=$((i + 1))
        if meter_nudges "$t" "verify-$i"; then
          meter_ok=1
          break 2
        fi
        has_assistant "$t" && witness="$t"
      done
    done <"$tmp/cur"
    if [[ -z "$meter_ok" && -n "$witness" ]]; then
      fail "context-meter.sh finds no model in a transcript with assistant messages" "$witness"
    elif [[ -z "$meter_ok" ]]; then
      pend "no transcript of a session on the installed version has an assistant message yet"
    fi
  fi
fi

finish
