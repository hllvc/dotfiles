#!/usr/bin/env bash
# Daily update review (LaunchAgent com.hllvc.versions-review): triages tools in
# .versions that drifted from their tested version and drafts plans for the
# ones that matter — see review.sh.

set -u

# shellcheck source=../_lib/log.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../_lib/log.sh"

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly LOG_DIR="${HOME}/Library/Logs/com.hllvc.versions-review"
readonly LOG_FILE="${LOG_DIR}/main.log"
readonly CACHE_DIR="${HOME}/Library/Caches/com.hllvc.versions-review"
readonly LAST_RUN_FILE="${CACHE_DIR}/last_run"
mkdir -p "$LOG_DIR" "$CACHE_DIR"

# Pre-flight: skip if on battery
if ! pmset -g batt | grep -q 'AC Power'; then
  _block_open "$LOG_FILE"
  _block_line "$LOG_FILE" "$(_color dim "Skipped — on battery")"
  _block_close "$LOG_FILE"
  exit 0
fi

# Pre-flight: skip if offline (release notes and the model both need it)
if ! curl -s --connect-timeout 3 https://api.anthropic.com/ -o /dev/null 2>/dev/null; then
  _block_open "$LOG_FILE"
  _block_line "$LOG_FILE" "$(_color dim "Skipped — no network")"
  _block_close "$LOG_FILE"
  exit 0
fi

# Pre-flight: skip if already ran today
today=$(date +%Y-%m-%d)
if [[ -f "$LAST_RUN_FILE" ]] && [[ "$(<"$LAST_RUN_FILE")" == "$today" ]]; then
  exit 0
fi

_block_open "$LOG_FILE"
rc=0
out="$(mktemp)"
bash "$SCRIPT_DIR/review.sh" --auto >"$out" 2>&1 || rc=$?
while IFS= read -r line; do
  _block_line "$LOG_FILE" "$(_color dim "$line")"
done <"$out"
rm -f "$out"

if ((rc == 0)); then
  _block_line "$LOG_FILE" "$(_color green "Done.")"
  printf '%s\n' "$today" >"$LAST_RUN_FILE"
else
  _block_line "$LOG_FILE" "$(_color red "review.sh exited ${rc}")"
fi
_block_close "$LOG_FILE"
