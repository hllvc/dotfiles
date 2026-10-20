#!/usr/bin/env bash
# Update review for the tools in .versions. When a tool's installed version
# drifted from the one the config was checked against (or a brew-pinned
# formula has an upgrade held back), a cheap model triages the changes:
#
#   ignore          no config impact: `dotctl versions accept` + a signed commit
#                   (a held upgrade gets a "safe to upgrade" note instead)
#   review/unsure   a stronger model drafts a plan; it waits as a Claude session
#                   in a window of the `updates` tmux session (updates.sh), with
#                   a "Plan ready" notification
#
#   review.sh --auto [tool...]   every review=auto tool that needs it, or just
#                                the named ones (launch agent, brewup)
#   review.sh <tool...>          just these, whatever their review mode — the
#                                manual trigger behind `dotctl versions
#                                review`; prints instead of notifying
#   --defer-plans                with --auto: triage in the foreground, but hand
#                                each Opus plan to a detached `review.sh --auto
#                                <tool>` (log: plans.log) that notifies when
#                                ready — brewup returns without waiting
#
# Results are cached per tool for one range (tested → target), so a range is
# triaged and planned once. Env overrides, for testing against a clone:
# VERSIONS_REVIEW_REPO, VERSIONS_REVIEW_CACHE, VERSIONS_REVIEW_SESSION.

set -u

# shellcheck source=../_lib/notify.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../_lib/notify.sh"

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO="${VERSIONS_REVIEW_REPO:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)}"
readonly CACHE="${VERSIONS_REVIEW_CACHE:-$HOME/Library/Caches/com.hllvc.versions-review}"
readonly LOG_DIR="$HOME/Library/Logs/com.hllvc.versions-review"
# launchd's PATH has no ~/.local/bin, where claude lives.
readonly CLAUDE="$HOME/.local/bin/claude"
# dotctl and updates.sh read these too.
export VERSIONS_REVIEW_REPO="$REPO" VERSIONS_REVIEW_CACHE="$CACHE"

readonly TRIAGE_MODEL=claude-haiku-5-5 TRIAGE_BUDGET=0.25 TRIAGE_TIMEOUT=300
readonly PLAN_MODEL=claude-opus-5-5 PLAN_BUDGET=3 PLAN_TIMEOUT=900
# Both runs only look: fetched changelogs are untrusted input, so nothing that
# writes is allowed. --add-dir opens the places changes live outside the repo.
readonly READ_TOOLS=(Read Grep Glob WebFetch
  "Bash(git log *)" "Bash(git diff *)" "Bash(git show *)"
  "Bash(git -C * log *)" "Bash(git -C * diff *)" "Bash(git -C * show *)")
readonly READ_DIRS=(/opt/homebrew "$HOME/.oh-my-zsh" "$HOME/.tmux/plugins"
  "$HOME/.local/share/nvim/lazy")

mkdir -p "$CACHE" "$LOG_DIR"

auto=0
defer=0
wanted=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  --auto) auto=1 ;;
  --defer-plans) defer=1 ;;
  -h | --help)
    sed -n '2,/^$/s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
    exit 0
    ;;
  -*)
    echo "review.sh: unknown option: $1" >&2
    exit 1
    ;;
  *) wanted+=("$1") ;;
  esac
  shift
done
if ((!auto && ${#wanted[@]} == 0)); then
  sed -n '2,/^$/s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
  exit 1
fi

# ─── helpers ──────────────────────────────────────────────────────────────

# Headless Claude with only the read-only tool set. --restricted ignores the
# user/project/local settings files, so their allow rules (this repo's
# .claude/settings.json is also ~/.claude/settings.json: tmux, aws, …) can't
# reach a run that reads untrusted changelogs; --tools leaves no tool that
# writes. The prompt comes on stdin: --allowedTools is variadic and would
# swallow a prompt argument.
#   _claude <model> <budget-usd> <timeout-s> <out.json> [flags…] <<<"$prompt"
_claude() {
  local model="$1" budget="$2" secs="$3" out="$4"
  shift 4
  (cd "$REPO" && /usr/bin/timeout "$secs" "$CLAUDE" -p --model "$model" \
    --max-budget-usd "$budget" --output-format json "$@" \
    --restricted --strict-mcp-config \
    --tools Read Grep Glob WebFetch Bash \
    --add-dir "${READ_DIRS[@]}" \
    --allowedTools "${READ_TOOLS[@]}") >"$out" 2>>"$LOG_DIR/claude.err"
}

_cache_file() {
  echo "$CACHE/$1.json"
}

# A field of the tool's cached record, empty when unset.
_cache_get() {
  jq -r "$2 // empty" "$(_cache_file "$1")" 2>/dev/null
}

# Apply a jq filter to the tool's record (created when missing).
#   _cache_put <tool> [--arg k v …] <filter>
_cache_put() {
  local file
  file="$(_cache_file "$1")"
  shift
  [[ -f "$file" ]] || echo '{}' >"$file"
  jq "$@" "$file" >"$file.tmp" && mv "$file.tmp" "$file"
}

# Facts about the update, appended to both prompts.
_context() {
  cat <<EOF

## This update
- tool: $1
- from (the config was checked against): $2
- to: $3
- installed now: $4
- changes source: $5
- probe (for git-log, the checkout path): $6
EOF
}

_session_exists() {
  find "$HOME/.claude/projects" -maxdepth 2 -name "$1.jsonl" 2>/dev/null | grep -q .
}

# Report something: a notification from the agent, a printed line when run by
# hand. _say <quiet|sticky> <title> <message>
_say() {
  echo "  $2 — $3"
  ((auto)) || return 0
  case "$1" in
  quiet) _notify_quiet "$2" "$3" 15 ;;
  sticky) _notify_sticky "$2" "$3" ;;
  esac
}

# "Plan ready" style notification whose Open action shows the plan's window.
# Detached: alerter waits for the click (the plist sets AbandonProcessGroup).
_notify_open() {
  (
    choice="$(_notify_actionable "$1" "$2" "Open")"
    case "$choice" in
    Open | @CONTENTCLICKED) "$SCRIPT_DIR/updates.sh" switch "$3" ;;
    esac
  ) >/dev/null 2>&1 &
  disown
}

# ─── triage ───────────────────────────────────────────────────────────────

# Haiku verdict for tool from → to, stored in the cache. A run that fails,
# times out or returns no verdict counts as unsure — never as ignore.
_triage() {
  local tool="$1" from="$2" to="$3" installed="$4" changes="$5" probe="$6"
  local out="$CACHE/$tool.triage.json" rc=0 verdict reason notable
  {
    cat "$SCRIPT_DIR/triage.md"
    _context "$tool" "$from" "$to" "$installed" "$changes" "$probe"
  } | _claude "$TRIAGE_MODEL" "$TRIAGE_BUDGET" "$TRIAGE_TIMEOUT" "$out" \
    --no-session-persistence --json-schema "$(cat "$SCRIPT_DIR/verdict.schema.json")" || rc=$?

  verdict="$(jq -r '.structured_output.verdict // empty' "$out" 2>/dev/null)"
  if [[ -n "$verdict" ]]; then
    reason="$(jq -r '.structured_output.reason' "$out")"
    notable="$(jq -c '.structured_output.notable // []' "$out")"
  else
    verdict=unsure
    reason="triage didn't finish (exit $rc, $(jq -r '.subtype // "no output"' "$out" 2>/dev/null || echo "no output")); treated as unsure"
    notable='[]'
  fi
  # A record for an older range is superseded, and so is its plan window.
  if [[ -f "$(_cache_file "$tool")" ]]; then
    "$SCRIPT_DIR/updates.sh" close "$tool"
  fi
  rm -f "$(_cache_file "$tool")" "$CACHE/$tool.plan.md"
  _cache_put "$tool" --arg from "$from" --arg to "$to" --arg verdict "$verdict" \
    --arg reason "$reason" --argjson notable "$notable" --arg at "$(date +%FT%T)" \
    '{from: $from, to: $to, verdict: $verdict, reason: $reason, notable: $notable, triaged_at: $at}'
  echo "  triage: $verdict — $reason"
}

# ─── ignore ───────────────────────────────────────────────────────────────

# Accept and commit a no-impact update: .versions plus the files `accept`
# syncs, by pathspec so nothing else is committed. Blocked (wrong branch,
# rebase/merge, uncommitted edits in those files, signing failure) → nothing
# is left changed, one note per distinct reason, and the next run retries.
_auto_accept() {
  local tool="$1" to="$2" reason="$3" why="" branch p dirty file
  local -a files=(.versions)
  while IFS= read -r p; do
    [[ -n "$p" ]] && files+=("$p")
  done < <("$REPO/dotctl" versions mirrors "$tool")

  branch="$(git -C "$REPO" symbolic-ref --short -q HEAD)"
  if [[ "$branch" != main ]]; then
    why="the repo is on ${branch:-a detached HEAD}, not main"
  fi
  for p in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
    if [[ -z "$why" && -e "$(cd "$REPO" && git rev-parse --git-path "$p")" ]]; then
      why="a rebase or merge is in progress"
    fi
  done
  if [[ -z "$why" ]]; then
    dirty="$(git -C "$REPO" status --porcelain -- "${files[@]}" | awk '{ print $2; exit }')"
    [[ -z "$dirty" ]] || why="$dirty has uncommitted changes"
  fi

  if [[ -z "$why" ]]; then
    file="$(_cache_file "$tool")"
    cp "$file" "$file.bak" # accept drops the record; keep it in case we roll back
    if ! "$REPO/dotctl" versions accept "$tool" >/dev/null; then
      why="dotctl versions accept failed"
    elif ! (cd "$REPO" && /usr/bin/timeout 120 git commit -q \
      -m "fix: versions — $tool $to, no config impact" -m "$reason" \
      -- "${files[@]}") >>"$LOG_DIR/git.err" 2>&1; then
      (cd "$REPO" && git checkout -q -- "${files[@]}")
      why="the commit failed (signing? see $LOG_DIR/git.err)"
    fi
    if [[ -z "$why" ]]; then
      rm -f "$file.bak"
      echo "  accepted and committed $tool $to"
      return 0
    fi
    [[ -f "$file" ]] || mv "$file.bak" "$file"
    rm -f "$file.bak"
  fi

  if [[ "$(_cache_get "$tool" .accept)" != "blocked: $why" ]]; then
    _cache_put "$tool" --arg a "blocked: $why" '.accept = $a'
    _say quiet "$tool $to: no config impact" "couldn't auto-accept: $why — the next run retries, or: dotctl versions accept --triaged"
  else
    echo "  still blocked: $why"
  fi
}

# ─── review / unsure ──────────────────────────────────────────────────────

# Opus drafts the plan once per range, in a session the `updates` window
# resumes. Later runs only make sure the window is there.
_plan() {
  local tool="$1" from="$2" to="$3" installed="$4" changes="$5" probe="$6"
  local name="$tool $from→$to" plan uuid rc=0 out="$CACHE/$tool.plan.json" new=0
  plan="$(_cache_get "$tool" .plan)"
  uuid="$(_cache_get "$tool" .session)"

  if [[ -z "$plan" ]]; then
    new=1
    uuid="$(uuidgen | tr '[:upper:]' '[:lower:]')"
    {
      cat "$SCRIPT_DIR/plan.md"
      _context "$tool" "$from" "$to" "$installed" "$changes" "$probe"
      echo
      echo "## Triage notes"
      jq -r '"Verdict: \(.verdict). \(.reason)", (.notable[] | "- \(.)")' "$(_cache_file "$tool")"
    } | _claude "$PLAN_MODEL" "$PLAN_BUDGET" "$PLAN_TIMEOUT" "$out" \
      --session-id "$uuid" --name "updates: $name" || rc=$?

    if [[ "$(jq -r '.subtype // empty' "$out" 2>/dev/null)" == success ]]; then
      plan=ready
    elif _session_exists "$uuid"; then
      plan=incomplete # a cap (budget or the timeout) stopped it mid-way
    else
      plan=failed
    fi
    jq -r '.result // empty' "$out" >"$CACHE/$tool.plan.md" 2>/dev/null
    _cache_put "$tool" --arg plan "$plan" --arg uuid "$uuid" --arg rc "$rc" \
      '.plan = $plan | .session = $uuid | .plan_exit = $rc'
    echo "  plan: $plan (session $uuid, exit $rc)"
  fi

  if [[ "$plan" == failed ]]; then
    ((new)) && _say sticky "Plan failed: $tool $from → $to" "see $LOG_DIR/claude.err"
    return 0
  fi
  if ! "$SCRIPT_DIR/updates.sh" open "$name" "$uuid" 2>>"$LOG_DIR/claude.err"; then
    ((new)) && _say sticky "Plan $plan: $tool $from → $to" \
      "no updates window (personal tmux server down?) — resume: claude --resume $uuid"
    return 0
  fi
  ((new)) || return 0

  if ((auto)); then
    # The time it was drafted, since the alert may be read much later.
    if [[ "$plan" == ready ]]; then
      _notify_open "Plan ready: $tool $from → $to" "$(date +%H:%M) · $(_cache_get "$tool" .reason)" "$name"
    else
      _notify_open "Plan incomplete: $tool $from → $to" "$(date +%H:%M) · Stopped at a cap — open to continue" "$name"
    fi
  else
    echo "  window: $name (personal socket, session ${VERSIONS_REVIEW_SESSION:-updates})"
    if [[ "${TMUX:-}" == "$HOME/.tmux/sockets/tmux-$(id -u)/personal,"* ]]; then
      "$SCRIPT_DIR/updates.sh" switch "$name"
    fi
  fi
}

# ─── main ─────────────────────────────────────────────────────────────────

_review_tool() {
  local tool="$1" tested="$2" installed="$3" held="$4" changes="$5" probe="$6" to
  if [[ "$installed" == "-" ]]; then
    echo "$tool: probe printed nothing — skipped"
    return 0
  fi
  to="$installed"
  [[ "$held" == "-" ]] || to="$held"
  if [[ "$to" == "$tested" ]]; then
    ((auto)) || echo "$tool: at its tested version ($tested), nothing to review"
    return 0
  fi

  echo "$tool: $tested → $to"
  if [[ "$(_cache_get "$tool" .from)" == "$tested" && "$(_cache_get "$tool" .to)" == "$to" ]]; then
    echo "  triage (cached): $(_cache_get "$tool" .verdict) — $(_cache_get "$tool" .reason)"
  else
    _triage "$tool" "$tested" "$to" "$installed" "$changes" "$probe"
  fi

  if [[ "$(_cache_get "$tool" .verdict)" == ignore ]]; then
    if [[ "$to" != "$installed" ]]; then
      # Held by a brew pin: never upgraded from here, only flagged once.
      if [[ "$(_cache_get "$tool" .notified)" != true ]]; then
        _say quiet "$tool $to: no config impact" "safe to upgrade: dotctl versions upgrade $tool"
        _cache_put "$tool" '.notified = true'
      fi
    else
      _auto_accept "$tool" "$to" "$(_cache_get "$tool" .reason)"
    fi
  elif ((defer)) && [[ -z "$(_cache_get "$tool" .plan)" ]]; then
    # The cached verdict lets the detached run go straight to the plan.
    nohup bash -c 'echo "── $(date "+%F %T") ──"; exec bash "$0" --auto "$1"' \
      "$SCRIPT_DIR/review.sh" "$tool" >>"$LOG_DIR/plans.log" 2>&1 &
    disown
    echo "  plan: drafting in the background (notification when ready; log: $LOG_DIR/plans.log)"
  else
    _plan "$tool" "$tested" "$to" "$installed" "$changes" "$probe"
  fi
}

rows="$("$REPO/dotctl" versions rows)" || exit 1
found=()
while IFS=$'\t' read -r tool review tested installed held changes probe; do
  if ((auto)); then
    [[ "$review" == auto ]] || continue
    if ((${#wanted[@]})); then
      [[ " ${wanted[*]} " == *" $tool "* ]] || continue
      found+=("$tool")
    fi
  else
    [[ " ${wanted[*]} " == *" $tool "* ]] || continue
    found+=("$tool")
  fi
  _review_tool "$tool" "$tested" "$installed" "$held" "$changes" "$probe"
done <<<"$rows"

if ((${#wanted[@]})); then
  for tool in "${wanted[@]}"; do
    [[ " ${found[*]:-} " == *" $tool "* ]] || echo "$tool: not in .versions" >&2
  done
fi
exit 0
