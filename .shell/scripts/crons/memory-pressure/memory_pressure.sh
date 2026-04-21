#!/usr/bin/env bash

_alert() { #{{{
  local message="
Be careful on the next app launch.
Your system might freeze.
"
  local icon_path="./warning.png"
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

free_percentage=$(memory_pressure | awk '/percentage/ {print $NF}' | tr -d %)
pressure=$((100 - free_percentage))

if ((free_percentage < 30)); then
  alert_action="$(_alert "$pressure")"
fi

echo "[$(date +"%d-%h-%y | %I:%M %p")] Pressure: $pressure, Free: $free_percentage" >>/tmp/com.personal.memory-pressure.out.log

_handle_alert_action "$alert_action"
