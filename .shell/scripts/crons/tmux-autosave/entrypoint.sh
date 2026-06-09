#!/usr/bin/env bash
set -euo pipefail

# launchd starts us with no locale; without a UTF-8 locale tmux sanitizes
# control chars (e.g. TAB) in -F formats to '_'. Pin one for consistent output.
export LANG="${LANG:-en_US.UTF-8}"

# shellcheck source=../_lib/log.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../_lib/log.sh"
# shellcheck source=../_lib/notify.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../_lib/notify.sh"

readonly LOG_DIR="${HOME}/Library/Logs/com.hllvc.tmux-autosave"
readonly LOG_FILE="${LOG_DIR}/main.log"
readonly CACHE_DIR="${HOME}/Library/Caches/com.hllvc.tmux-autosave"
readonly LAST_SAVE_FILE="${CACHE_DIR}/last_save_ts"
readonly RESURRECT_SAVE="${HOME}/.tmux/plugins/tmux-resurrect/scripts/save.sh"
readonly SOCKET_DIR="${TMUX_TMPDIR:-${HOME}/.tmux/sockets}/tmux-$(id -u)"
# tmux-resurrect save dir (per-socket subdirs, because @continuum-multiple-sockets 'on').
readonly RESURRECT_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/tmux/resurrect"
# Max timestamped saves to retain per socket. Saves never expire on their own, so
# without this the dirs grow unbounded (they had reached 235/215 files).
readonly KEEP_SAVES=30

# --- stale-session tracking --------------------------------------------------
# tmux's own window_activity / session_last_attached reset on every restore, so
# they can't measure week-scale staleness across reboots. We keep our own ledger
# (session_name<TAB>last_seen_attached_epoch) that survives reboots, stamped on
# every run for each currently-attached session.
readonly USAGE_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/com.hllvc.tmux-autosave/usage"
readonly STALE_THRESHOLD=$(( 7 * 24 * 3600 ))   # 7 days untouched → stale
# SAFETY: stale sessions are only killed when this opt-in flag file exists.
# Until then the run is report-only — it logs candidates but kills nothing.
readonly AUTOPRUNE_FLAG="${XDG_CONFIG_HOME:-${HOME}/.config}/tmux/autoprune-enabled"

# Seconds of HID inactivity needed to trigger an idle-gated save.
readonly IDLE_THRESHOLD=30
# Unconditional save floor — fires even if user is active (seconds since last save).
readonly FORCE_INTERVAL=5400   # 90 min

mkdir -p "$LOG_DIR" "$CACHE_DIR"

_hid_idle_secs() {
  local t
  t=$(ioreg -c IOHIDSystem 2>/dev/null \
    | awk '/HIDIdleTime/ {print int($NF / 1000000000); exit}')
  echo "${t:-0}"
}

_last_save_age() {
  local now ts=0
  now=$(date +%s)
  [[ -f "$LAST_SAVE_FILE" ]] && ts=$(<"$LAST_SAVE_FILE")
  echo $(( now - ts ))
}

# Trim each socket's resurrect dir to the newest $KEEP_SAVES saves. The 'last'
# symlink always points at the newest file, so it is never pruned. Runs only
# after saves fire (the only time the dirs grow).
_prune_saves() {
  local sockdir
  for sockdir in "$RESURRECT_DIR"/*/; do
    [[ -d "$sockdir" ]] || continue
    local -a files=()
    while IFS= read -r f; do files+=("$f"); done \
      < <(ls -1t "${sockdir}"tmux_resurrect_*.txt 2>/dev/null)
    (( ${#files[@]} > KEEP_SAVES )) || continue
    local -a old=( "${files[@]:KEEP_SAVES}" )
    rm -f -- "${old[@]}"
    _block_line "$LOG_FILE" "$(_color dim "pruned ${#old[@]} old save(s) in $(basename "$sockdir")")"
  done
  return 0   # never let a false `(( ))`/continue make this function exit non-zero
}

# Look up a session's stored last-seen epoch in a ledger ("" if absent).
_ledger_stamp() {
  local ledger="$1" session="$2"
  awk -F'\t' -v s="$session" '$1==s{print $2; exit}' "$ledger" 2>/dev/null
}

# Refresh the usage ledger for every live socket and report (or, if opted in,
# kill) sessions untouched for >= STALE_THRESHOLD. Never touches attached
# sessions; brand-new sessions get a grace stamp of "now" on first sight.
_track_and_prune_sessions() {
  mkdir -p "$USAGE_DIR"
  local now autoprune=0 sock_path socket ledger tmp sname sattached stamp age days
  local stale_count=0 stale_sig=""
  now=$(date +%s)
  [[ -e "$AUTOPRUNE_FLAG" ]] && autoprune=1

  while IFS= read -r -d '' sock_path; do
    socket="$(basename "$sock_path")"
    tmux -L "$socket" has-session 2>/dev/null || continue
    ledger="${USAGE_DIR}/${socket}.tsv"
    touch "$ledger"
    tmp="$(mktemp)"

    # Rebuild the ledger from the sessions that currently exist (this also drops
    # entries for sessions that are already gone, and adds new ones).
    # NB: attached-count first, name as the remainder, space-delimited. tmux
    # sanitizes a literal TAB in the format to '_' when there's no UTF-8 locale
    # (as under launchd), which silently corrupted names to "name_<attached>".
    while read -r sattached sname; do
      [[ -n "$sname" ]] || continue
      if (( ${sattached:-0} > 0 )); then
        stamp=$now                                   # attached now → fresh
      else
        stamp="$(_ledger_stamp "$ledger" "$sname")"
        [[ -n "$stamp" ]] || stamp=$now              # first sight → grace
      fi
      printf '%s\t%s\n' "$sname" "$stamp" >>"$tmp"

      if (( ${sattached:-0} == 0 )); then
        age=$(( now - stamp ))
        if (( age >= STALE_THRESHOLD )); then
          days=$(( age / 86400 ))
          if (( autoprune )); then
            if tmux -L "$socket" kill-session -t "$sname" 2>/dev/null; then
              _block_line "$LOG_FILE" "$(_color yellow "pruned stale session ${socket}:${sname} (idle ${days}d)")"
            fi
          else
            _block_line "$LOG_FILE" "$(_color dim "stale candidate ${socket}:${sname} (idle ${days}d) · review with prefix+K")"
            stale_count=$(( stale_count + 1 ))
            stale_sig="${stale_sig}${socket}:${sname},"
          fi
        fi
      fi
    done < <(tmux -L "$socket" list-sessions -F '#{session_attached} #{session_name}' 2>/dev/null)

    mv "$tmp" "$ledger"
  done < <(/usr/bin/find "$SOCKET_DIR" -maxdepth 1 -type s -print0 2>/dev/null)

  # Report mode: nudge once per stale set (and at most daily) toward an
  # interactive review, rather than killing anything automatically.
  # NB: use `if`, not `(( )) &&` — a false `(( ))` returns 1, and as the last
  # statement in this function it would make the function (and, under `set -e`,
  # the whole script) exit non-zero whenever nothing is stale.
  if (( autoprune == 0 && stale_count > 0 )); then
    _notify_stale "$stale_count" "$stale_sig"
  fi
  return 0
}

# Fire a throttled notification about stale sessions. Re-notifies only when the
# stale set changes or 24h have passed, so it never nags every 30-min tick.
_notify_stale() {
  local count="$1" sig="$2" state_file="${USAGE_DIR}/.notify_state"
  local prev_sig="" prev_ts=0 now2
  now2=$(date +%s)
  [[ -f "$state_file" ]] && IFS='|' read -r prev_sig prev_ts <"$state_file"
  if [[ "$sig" != "$prev_sig" ]] || (( now2 - ${prev_ts:-0} >= 86400 )); then
    # Sticky (no timeout) so it persists until acknowledged. The "Will do" button
    # just dismisses it (you actually prune with prefix+K).
    _notify_sticky "🧹 ${count} stale tmux session(s)" "idle >7d · press prefix+K to review & prune" "Will do"
    printf '%s|%s\n' "$sig" "$now2" >"$state_file"
  fi
}

force=0
[[ "${1:-}" == "--force" ]] && force=1

idle=$(_hid_idle_secs)
age=$(_last_save_age)

_block_open "$LOG_FILE"

# Runs every tick (even on idle-skip) so usage tracking is independent of saves.
_track_and_prune_sessions

if (( force )); then
  reason="forced (sleep/shutdown)"
elif (( idle >= IDLE_THRESHOLD )); then
  reason="idle=${idle}s"
elif (( age >= FORCE_INTERVAL )); then
  reason="force (${age}s since last save)"
else
  _block_line "$LOG_FILE" "$(_color dim "skip · idle=${idle}s · last_save ${age}s ago")"
  _block_close "$LOG_FILE"
  exit 0
fi

_block_line "$LOG_FILE" "$(_color dim "saving · ${reason}")"

found=0
while IFS= read -r -d '' sock_path; do
  socket="$(basename "$sock_path")"
  if tmux -L "$socket" has-session 2>/dev/null; then
    tmux -L "$socket" run-shell -b "$RESURRECT_SAVE"
    _block_line "$LOG_FILE" "$(_color green "socket=${socket} · save fired")"
    found=$(( found + 1 ))
  else
    _block_line "$LOG_FILE" "$(_color dim "socket=${socket} · no server, skipped")"
  fi
done < <(/usr/bin/find "$SOCKET_DIR" -maxdepth 1 -type s -print0 2>/dev/null)

if (( found == 0 )); then
  _block_line "$LOG_FILE" "$(_color yellow "no live sockets found under ${SOCKET_DIR}")"
fi

_prune_saves

printf '%s\n' "$(date +%s)" > "$LAST_SAVE_FILE"
_block_close "$LOG_FILE"
