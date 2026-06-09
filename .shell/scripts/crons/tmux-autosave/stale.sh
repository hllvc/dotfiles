# shellcheck shell=bash
#
# Shared stale-session helpers for the interactive prune-review tool. Safe to
# source standalone. The autosave cron (entrypoint.sh) maintains the usage
# ledgers this reads; here we only QUERY them and act on the user's choice.
#
# Ledger format (one per socket, written by entrypoint.sh):
#   <session_name>\t<last_seen_attached_epoch>
#
# A session is "stale" when it is not currently attached and its ledger stamp is
# older than STALE_THRESHOLD. Keep these defaults in sync with entrypoint.sh.

: "${USAGE_DIR:=${XDG_DATA_HOME:-${HOME}/.local/share}/com.hllvc.tmux-autosave/usage}"
: "${STALE_THRESHOLD:=$(( 7 * 24 * 3600 ))}"   # 7 days
: "${SOCKET_DIR:=${TMUX_TMPDIR:-${HOME}/.tmux/sockets}/tmux-$(id -u)}"

_stale_ledger_stamp() {  # <ledger> <session> -> epoch, or "" if absent
  awk -F'\t' -v s="$2" '$1==s{print $2; exit}' "$1" 2>/dev/null
}

# Emit a TSV row for every stale, non-attached session across all live sockets:
#   <socket>\t<session>\t<idle_days>\t<window_count>
_list_stale_candidates() {
  local now sock_path socket ledger sname sattached stamp age wins
  now=$(date +%s)
  while IFS= read -r -d '' sock_path; do
    socket="$(basename "$sock_path")"
    tmux -L "$socket" has-session 2>/dev/null || continue
    ledger="${USAGE_DIR}/${socket}.tsv"
    [[ -f "$ledger" ]] || continue
    # attached-count first, name as remainder (space-delimited). A literal TAB in
    # the -F format is sanitized to '_' by tmux without a UTF-8 locale.
    while read -r sattached sname; do
      [[ -n "$sname" ]] || continue
      (( ${sattached:-0} > 0 )) && continue              # never touch attached
      stamp="$(_stale_ledger_stamp "$ledger" "$sname")"
      [[ -n "$stamp" ]] || continue
      age=$(( now - stamp ))
      (( age >= STALE_THRESHOLD )) || continue
      wins=$(tmux -L "$socket" list-windows -t "$sname" 2>/dev/null | wc -l | tr -d ' ')
      printf '%s\t%s\t%s\t%s\n' "$socket" "$sname" "$(( age / 86400 ))" "${wins:-0}"
    done < <(tmux -L "$socket" list-sessions -F '#{session_attached} #{session_name}' 2>/dev/null)
  done < <(/usr/bin/find "$SOCKET_DIR" -maxdepth 1 -type s -print0 2>/dev/null)
}

# Kill a session (the prune action). Returns tmux's exit status.
_stale_kill() {  # <socket> <session>
  tmux -L "$1" kill-session -t "$2" 2>/dev/null
}

# Re-stamp a kept session to "now" so it is not re-flagged for another
# STALE_THRESHOLD ("I looked, I want to keep this").
_stale_keep() {  # <socket> <session>
  local ledger="${USAGE_DIR}/${1}.tsv" now tmp
  now=$(date +%s)
  tmp="$(mktemp)"
  [[ -f "$ledger" ]] || touch "$ledger"
  awk -F'\t' -v OFS='\t' -v s="$2" -v n="$now" \
    '$1==s{$2=n; seen=1} {print} END{if(!seen) print s, n}' "$ledger" >"$tmp" \
    && mv "$tmp" "$ledger"
}
