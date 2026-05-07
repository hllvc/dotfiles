#!/usr/bin/env bash

set -u

# shellcheck source=../_lib/log.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../_lib/log.sh"
# shellcheck source=../_lib/notify.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../_lib/notify.sh"

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

failed_cmds=()

_run_cmd() {
  local label="$1"; shift
  _block_line "$LOG_FILE" "$(_color dim "→ $label")"
  local tmpout rc=0
  tmpout=$(mktemp)
  "$@" >"$tmpout" 2>&1 || rc=$?
  while IFS= read -r line; do
    _block_line "$LOG_FILE" "$(_color dim "   $line")"
  done < <(tail -n 20 "$tmpout")
  rm -f "$tmpout"
  if ((rc != 0)); then
    failed_cmds+=("$label")
    _block_line "$LOG_FILE" "$(_color red "   exited ${rc}")"
  fi
}

_block_open "$LOG_FILE"

_run_cmd "brew update"  brew update
_block_line "$LOG_FILE" ""
_run_cmd "brew upgrade"  brew upgrade
_block_line "$LOG_FILE" ""
_run_cmd "brew upgrade --cask"  brew upgrade --greedy --greedy-auto-updates --greedy-latest --cask
_block_line "$LOG_FILE" ""
_run_cmd "brew autoremove"  brew autoremove
_block_line "$LOG_FILE" ""
_run_cmd "brew cleanup -s"  brew cleanup -s
_block_line "$LOG_FILE" ""

if ((${#failed_cmds[@]} == 0)); then
  _block_line "$LOG_FILE" "$(_color green "All commands succeeded.")"
  _block_close "$LOG_FILE"
  printf '%s\n' "$today" >"$LAST_RUN_FILE"
else
  failed_list=$(IFS=', '; echo "${failed_cmds[*]}")
  _block_line "$LOG_FILE" "$(_color red "FAILED: ${failed_list}")"
  _block_close "$LOG_FILE"
  _notify_sticky \
    "Homebrew upgrade failed" \
    "Failed: ${failed_list} — see ~/Library/Logs/com.hllvc.homebrew-update/main.log"
fi
