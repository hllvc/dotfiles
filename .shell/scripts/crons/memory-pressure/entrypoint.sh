#!/usr/bin/env bash

readonly LOG_FILE="${HOME}/Library/Logs/com.hllvc.memory-pressure.log"

readonly _C_GREEN='\033[0;32m'
readonly _C_YELLOW='\033[0;33m'
readonly _C_RED='\033[0;31m'
readonly _C_DIM='\033[2m'
readonly _C_RESET='\033[0m'

_color() { #{{{
  local name="$1"
  local text="$2"
  case "$name" in
  green)  printf '%b%s%b' "$_C_GREEN"  "$text" "$_C_RESET" ;;
  yellow) printf '%b%s%b' "$_C_YELLOW" "$text" "$_C_RESET" ;;
  red)    printf '%b%s%b' "$_C_RED"    "$text" "$_C_RESET" ;;
  dim)    printf '%b%s%b' "$_C_DIM"    "$text" "$_C_RESET" ;;
  *)      printf '%s' "$text" ;;
  esac
}
#}}}: _color

_block_open() { #{{{
  local ts
  ts=$(date +"%d-%h-%y | %I:%M %p")
  printf '┌─ %s ──────────────────────────────\n' "$ts" >>"$LOG_FILE"
}
#}}}: _block_open

_block_line() { #{{{
  printf '│  %b\n' "$1" >>"$LOG_FILE"
}
#}}}: _block_line

_block_close() { #{{{
  printf '└─────────────────────────────────────────────────────\n\n' >>"$LOG_FILE"
}
#}}}: _block_close

_alert() { #{{{
  local message="
Be careful on the next app launch.
Your system might freeze.
"
  # shellcheck disable=SC2155
  local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local icon_path="${script_dir}/warning.png"
  local pressure="$1"

  alerter \
    --message "$message" \
    --title "Memory Pressure - ${pressure}%" \
    --app-icon "$icon_path" \
    --ignore-dnd
}
#}}}: _alert

_handle_alert_action() { #{{{
  local action="$1"

  # @CONTENTCLICKED
  # @CLOSED
  # @ACTIONCLICKED
  case "$action" in
  @CONTENTCLICKED)
    open -a "Activity Monitor"
    ;;
  # @CLOSED)
  #   command ...
  #   ;;
  @ACTIONCLICKED)
    open -a "Activity Monitor"
    ;;
  *)
    exit
    ;;
  esac
}
#}}}: _handle_alert_action

free=$(memory_pressure | awk '/percentage/ {print $NF}' | tr -d %)
pressure=$((100 - free))

if ((free >= 60)); then
  sev_color=green
  sev_label="HEALTHY"
elif ((free >= 40)); then
  sev_color=yellow
  sev_label="ELEVATED"
else
  sev_color=red
  sev_label="CRITICAL"
fi

_block_open
_block_line "$(_color "$sev_color" "Pressure: ${pressure}%   Free: ${free}%")   $(_color "$sev_color" "[ ${sev_label} ]")"

if ((free < 40)); then
  alert_action="$(_alert "$pressure")"
  _block_line "Alert shown → action: ${alert_action:-none}"
  _block_close
  _handle_alert_action "$alert_action"
else
  _block_line "$(_color dim 'No action taken')"
  _block_close
fi
