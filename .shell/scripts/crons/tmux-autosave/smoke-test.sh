#!/usr/bin/env bash
#
# Regression smoke test for the stale-session tracker's tmux parsing.
#
# launchd starts the cron with no UTF-8 locale, and tmux then sanitizes control
# chars (e.g. a TAB) in a -F format to '_'. With a tab separator that silently
# corrupted ledger keys "name<TAB>attached" -> "name_attached", which also broke
# attached-detection. The tracker now uses an "<attached> <name>" space-delimited
# format. This test reproduces the launchd condition (env -i, no LANG) and
# asserts the separator survives and parses cleanly, including a name with a
# space. Run it directly; exits non-zero on regression.
set -uo pipefail

sock="${TMPDIR:-/tmp}/tmux-smoke-$$.sock"
sess="smoke test sess"   # deliberately contains spaces
trap 'tmux -S "$sock" kill-server 2>/dev/null; rm -f "$sock"' EXIT

tmux -S "$sock" new-session -d -s "$sess" 2>/dev/null || {
  echo "SKIP: could not start scratch tmux server"; exit 0; }

# Query exactly as the tracker does, under a launchd-like stripped environment.
out="$(env -i PATH="$PATH" HOME="$HOME" \
  /bin/bash -c "tmux -S '$sock' list-sessions -F '#{session_attached} #{session_name}'")"

fail=0
echo "raw output under stripped env: [$out]"
case "$out" in
  *_*) echo "FAIL: separator was mangled to '_' (locale regression): [$out]"; fail=1 ;;
esac

# Parse the way the tracker does: attached first, name as the remainder.
read -r attached name <<<"$out"
[[ "$attached" == "0" ]]   || { echo "FAIL: attached parsed as [$attached], want 0"; fail=1; }
[[ "$name" == "$sess" ]]   || { echo "FAIL: name parsed as [$name], want [$sess]"; fail=1; }

if (( fail )); then
  echo "SMOKE TEST FAILED"
  exit 1
fi
echo "SMOKE TEST PASSED — separator survived stripped env; '$name' / attached=$attached parsed cleanly"
