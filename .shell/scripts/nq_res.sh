#!/usr/bin/env bash

readonly WIFI_NAME="halilovic5G"
readonly TARGET_SPEED="${1:-350}"
readonly NQ_RESULT_EXAMPLE=$(cat <<EOF
==== SUMMARY ====
Uplink capacity: 65.317 Mbps
Downlink capacity: 384.164 Mbps
Responsiveness: Medium (274.190 milliseconds | 218 RPM)
Idle Latency: 46.343 milliseconds | 1294 RPM
EOF
)

declare downlink

_target_wifi() { #{{{
  ipconfig getsummary en0 \
    | grep -q "SSID : $WIFI_NAME"

  return $?
}
#}}}: _target_wifi

_network_quality() { #{{{
  networkQuality -u
}
#}}}: _network_quality

_get_capacity_for() { #{{{
  local capacity_type="$1"

  local result

  _extract_capacity_wrapper() { #{{{
    _network_quality \
      | grep "${capacity_type} capacity" \
      | grep -Eo "[0-9]{1,3}\.[0-9]{1,3}"
  }
  #}}} _extract_capacity_wrapper

  result="$(_extract_capacity_wrapper)"

  if [[ -n "$2" ]]; then
    local -n ref="$2"
    ref="$result"
    readonly ref
    return
  else
    echo "$result"
  fi
}
#}}}: _get_capacity_for

_is_target_speed() { #{{{
  local target="$TARGET_SPEED"
  local speed="${1%%.*}"

  if (( speed < target )); then
    return 1 # false
  else
    return 0 # true
  fi
}
#}}}: _is_target_speed

main() { #{{{
  if ! _target_wifi; then
    echo "Not connected to <${WIFI_NAME}>"
    exit 0
  fi

  _get_capacity_for "Downlink" downlink
  if _is_target_speed "$downlink"; then
    echo "Fast enough: $downlink Mbps"
    exit 0
  else
    echo "Very slow: $downlink Mbps"
    exit 1
  fi

  # _get_capacity_for "Uplink" uplink
}
#}}}: main

main "$@"
