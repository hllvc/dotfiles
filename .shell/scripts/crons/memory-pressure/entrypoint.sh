#!/usr/bin/env bash

readonly LOG_DIR="${HOME}/Library/Logs/com.hllvc.memory-pressure"
readonly LOG_FILE="${LOG_DIR}/main.log"
readonly CACHE_DIR="${HOME}/Library/Caches/com.hllvc.memory-pressure"
readonly SNOOZE_FILE="${CACHE_DIR}/snooze"
readonly STATE_FILE="${CACHE_DIR}/state"
mkdir -p "$LOG_DIR" "$CACHE_DIR"

# Severity thresholds — tune from real data in main.log.
readonly FREE_PCT_ELEVATED=40
readonly FREE_PCT_CRITICAL=20
readonly COMP_PCT_ELEVATED=30
readonly COMP_PCT_CRITICAL=50
readonly SWAP_RATE_ELEVATED=100 # pages/sec
readonly SWAP_RATE_CRITICAL=500

readonly _C_GREEN='\033[0;32m'
readonly _C_YELLOW='\033[0;33m'
readonly _C_RED='\033[0;31m'
readonly _C_DIM='\033[2m'
readonly _C_RESET='\033[0m'

_color() { #{{{
  local name="$1"
  local text="$2"
  case "$name" in
  green) printf '%b%s%b' "$_C_GREEN" "$text" "$_C_RESET" ;;
  yellow) printf '%b%s%b' "$_C_YELLOW" "$text" "$_C_RESET" ;;
  red) printf '%b%s%b' "$_C_RED" "$text" "$_C_RESET" ;;
  dim) printf '%b%s%b' "$_C_DIM" "$text" "$_C_RESET" ;;
  *) printf '%s' "$text" ;;
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

_snooze() { #{{{
  local label="$1"
  local qty unit seconds expiry
  if [[ "$label" =~ ^Snooze\ for\ ([0-9]+)\ (minute|minutes|hour|hours)$ ]]; then
    qty="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[2]}"
    case "$unit" in
    minute | minutes) seconds=$((qty * 60)) ;;
    hour | hours) seconds=$((qty * 3600)) ;;
    esac
    expiry=$(($(date +%s) + seconds))
    printf '%s\n' "$expiry" >"$SNOOZE_FILE"
    _block_open
    _block_line "$(_color dim "Snoozed until $(date -r "$expiry" +'%I:%M %p') (${qty} ${unit})")"
    _block_close
  else
    _block_open
    _block_line "$(_color yellow "Unrecognized snooze label: ${label}")"
    _block_close
  fi
}
#}}}: _snooze

# shellcheck disable=SC2155
_icon_path() { echo "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/warning.png"; }

_alert_critical() { #{{{
  local pressure="$1" metrics="$2" triggers="$3"
  alerter \
    --message "${metrics} · ${triggers}" \
    --title "Memory critical · ${pressure}%" \
    --actions "Snooze for 5 minutes" \
    --app-icon "$(_icon_path)" \
    --ignore-dnd
}
#}}}: _alert_critical

_alert_elevated() { #{{{
  local pressure="$1" metrics="$2" triggers="$3"
  alerter \
    --message "${metrics} · ${triggers}" \
    --title "Memory rising · ${pressure}%" \
    --app-icon "$(_icon_path)" \
    --timeout 30 \
    >/dev/null &
  disown
}
#}}}: _alert_elevated

_alert_recovery() { #{{{
  local metrics="$1"
  alerter \
    --message "$metrics" \
    --title "Memory normal" \
    --app-icon "$(_icon_path)" \
    --timeout 5 \
    >/dev/null &
  disown
}
#}}}: _alert_recovery

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
  "Snooze for "*)
    _snooze "$action"
    ;;
  @ACTIONCLICKED)
    open -a "Activity Monitor"
    ;;
  *)
    exit
    ;;
  esac
}
#}}}: _handle_alert_action

# Parse memory_pressure output in a single pass.
eval "$(memory_pressure | awk '
  /^The system has/            { gsub(/[()]/,""); print "total_pages=" $5 }
  /^Pages free:/               { print "free_pages=" $3 }
  /^Pages used by compressor:/ { print "compressor_pages=" $5 }
  /^Swapouts:/                 { print "swapouts=" $2 }
  /free percentage:/           { gsub(/%/,"",$NF); print "free_pct=" $NF }
')"

now=$(date +%s)
pressure=$((100 - free_pct))
compressor_pct=$((compressor_pages * 100 / total_pages))

# Swap rate: delta since previous sample. Sentinel -1 = unknown (first run / no prev).
# Also read previous severity to gate one-shot transition notifications.
swap_rate=-1
prev_sev_label="HEALTHY"
if [[ -f "$STATE_FILE" ]]; then
  read -r prev_ts prev_swapouts prev_sev_read <"$STATE_FILE"
  [[ -n "$prev_sev_read" ]] && prev_sev_label="$prev_sev_read"
  dt=$((now - prev_ts))
  if ((dt > 0)); then
    delta=$((swapouts - prev_swapouts))
    ((delta < 0)) && delta=0 # counter resets on reboot
    swap_rate=$((delta / dt))
  fi
fi

# Compose severity as the worst of three signals.
sev=0
triggers=()

if ((free_pct < FREE_PCT_CRITICAL)); then
  sev=2
  triggers+=("free")
elif ((free_pct < FREE_PCT_ELEVATED)); then
  ((sev < 1)) && sev=1
  triggers+=("free")
fi

if ((compressor_pct >= COMP_PCT_CRITICAL)); then
  sev=2
  triggers+=("compressor")
elif ((compressor_pct >= COMP_PCT_ELEVATED)); then
  ((sev < 1)) && sev=1
  triggers+=("compressor")
fi

if ((swap_rate >= 0)); then
  if ((swap_rate >= SWAP_RATE_CRITICAL)); then
    sev=2
    triggers+=("swap")
  elif ((swap_rate >= SWAP_RATE_ELEVATED)); then
    ((sev < 1)) && sev=1
    triggers+=("swap")
  fi
fi

case $sev in
0)
  sev_color=green
  sev_label="HEALTHY"
  ;;
1)
  sev_color=yellow
  sev_label="ELEVATED"
  ;;
2)
  sev_color=red
  sev_label="CRITICAL"
  ;;
esac

# Persist state for next run: timestamp, swapouts counter, current severity.
printf '%s %s %s\n' "$now" "$swapouts" "$sev_label" >"$STATE_FILE"

swap_display="n/a"
((swap_rate >= 0)) && swap_display="${swap_rate} p/s"
metrics_line="Free: ${free_pct}% | Comp: ${compressor_pct}% | Swap: ${swap_display}"

_block_open
_block_line "$(_color "$sev_color" "$metrics_line")   $(_color "$sev_color" "[ ${sev_label} ]")"
if ((${#triggers[@]} > 0)); then
  _block_line "$(_color dim "triggers: $(
    IFS=,
    echo "${triggers[*]}"
  )")"
fi

trigger_list=$(
  IFS=,
  echo "${triggers[*]}"
)

if [[ "$sev_label" == "CRITICAL" ]]; then
  snooze_until=0
  [[ -f "$SNOOZE_FILE" ]] && snooze_until=$(<"$SNOOZE_FILE")

  if ((now < snooze_until)); then
    _block_line "$(_color dim "Alert suppressed (snoozed until $(date -r "$snooze_until" +'%I:%M %p'))")"
    _block_close
  else
    alert_action="$(_alert_critical "$pressure" "$metrics_line" "$trigger_list")"
    _block_line "Critical alert shown → action: ${alert_action:-none}"
    _block_close
    _handle_alert_action "$alert_action"
  fi
elif [[ "$prev_sev_label" == "HEALTHY" && "$sev_label" == "ELEVATED" ]]; then
  _alert_elevated "$pressure" "$metrics_line" "$trigger_list"
  _block_line "$(_color dim "Rising alert shown (HEALTHY → ELEVATED)")"
  _block_close
elif [[ "$prev_sev_label" != "HEALTHY" && "$sev_label" == "HEALTHY" ]]; then
  _alert_recovery "$metrics_line"
  _block_line "$(_color dim "Recovery alert shown (${prev_sev_label} → HEALTHY)")"
  _block_close
else
  _block_close
fi
