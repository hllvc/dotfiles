#!/usr/bin/env bash

set -u

# shellcheck source=../_lib/log.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../_lib/log.sh"
# shellcheck source=../_lib/notify.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../_lib/notify.sh"

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly LOG_DIR="${HOME}/Library/Logs/com.hllvc.homebrew-update"
readonly LOG_FILE="${LOG_DIR}/main.log"
readonly CACHE_DIR="${HOME}/Library/Caches/com.hllvc.homebrew-update"
readonly LAST_RUN_FILE="${CACHE_DIR}/last_run"
mkdir -p "$LOG_DIR" "$CACHE_DIR"

# Pre-flight: skip if on battery
if ! pmset -g batt | grep -q 'AC Power'; then
  _block_open "$LOG_FILE"
  _block_line "$LOG_FILE" "$(_color dim "Skipped — on battery")"
  _block_close "$LOG_FILE"
  exit 0
fi

# Pre-flight: skip if offline
if ! curl -s --connect-timeout 3 https://formulae.brew.sh/ -o /dev/null 2>/dev/null; then
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

# The sequence itself is shared with `brewup` (lib/brew-upgrade.sh). Its output
# is copied into the log block; a last "FAILED: a, b" line names failed steps.
upgrade_out=$(mktemp)
bash "$SCRIPT_DIR/../../lib/brew-upgrade.sh" >"$upgrade_out" 2>&1
while IFS= read -r line; do
  case "$line" in
  "── "*)
    line="${line#── }"
    _block_line "$LOG_FILE" "$(_color dim "→ ${line% ──}")"
    ;;
  FAILED:*) ;;
  *) _block_line "$LOG_FILE" "$(_color dim "   $line")" ;;
  esac
done <"$upgrade_out"
failed_list=$(sed -n 's/^FAILED: //p' "$upgrade_out")
rm -f "$upgrade_out"
_block_line "$LOG_FILE" ""

if [[ -z "$failed_list" ]]; then
  _block_line "$LOG_FILE" "$(_color green "All commands succeeded.")"
  _block_close "$LOG_FILE"
  printf '%s\n' "$today" >"$LAST_RUN_FILE"
else
  _block_line "$LOG_FILE" "$(_color red "FAILED: ${failed_list}")"
  _block_close "$LOG_FILE"
  _notify_sticky \
    "Homebrew upgrade failed" \
    "Failed: ${failed_list} — see ~/Library/Logs/com.hllvc.homebrew-update/main.log"
fi
