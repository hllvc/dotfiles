#!/usr/bin/env bash

# macOS redacts SSID/BSSID for processes without Location Services access, so
# we fingerprint the home network by its router (default gateway) MAC instead.
# Add more MACs here as needed (lowercase, colon-separated).
readonly HOME_ROUTER_MACS=(
  "18:3d:5e:a1:d4:80" # logosoft main router
)
readonly TARGET_SPEED="${1:-350}"
readonly NQ_RESULT_EXAMPLE=$(
  cat <<EOF
==== SUMMARY ====
Uplink capacity: 65.317 Mbps
Downlink capacity: 384.164 Mbps
Responsiveness: Medium (274.190 milliseconds | 218 RPM)
Idle Latency: 46.343 milliseconds | 1294 RPM
EOF
)

declare downlink

_default_iface() { #{{{
  route -n get default 2>/dev/null |
    awk '/interface:/ { print $2; exit }'
}
#}}}: _default_iface

_router_mac() { #{{{
  local iface="$1"
  local gw
  gw="$(route -n get default 2>/dev/null | awk '/gateway:/ { print $2; exit }')"
  [[ -z "$gw" ]] && return

  # Prime the ARP cache, then read the gateway's MAC for this interface.
  ping -c1 -t1 "$gw" >/dev/null 2>&1
  arp -n "$gw" 2>/dev/null |
    awk -v ifc="$iface" '$0 ~ ("on " ifc) {
      for (i = 1; i <= NF; i++)
        if ($i == "at") { print $(i + 1); exit }
    }'
}
#}}}: _router_mac

_is_home_router() { #{{{
  local mac
  mac="$(printf '%s' "$1" | tr "A-Z" "a-z")"
  [[ -z "$mac" ]] && return 1

  local known
  for known in "${HOME_ROUTER_MACS[@]}"; do
    [[ "$mac" == "$known" ]] && return 0
  done
  return 1
}
#}}}: _is_home_router

_network_quality() { #{{{
  networkQuality -u
}
#}}}: _network_quality

_get_capacity_for() { #{{{
  local capacity_type="$1"

  local result

  _extract_capacity_wrapper() { #{{{
    _network_quality |
      grep "${capacity_type} capacity" |
      grep -Eo "[0-9]{1,3}\.[0-9]{1,3}"
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

  if ((speed < target)); then
    return 1 # false
  else
    return 0 # true
  fi
}
#}}}: _is_target_speed

main() { #{{{
  local iface mac
  iface="$(_default_iface)"

  if [[ -z "$iface" ]]; then
    echo "Not connected to any network"
    exit 0
  fi

  mac="$(_router_mac "$iface")"
  if ! _is_home_router "$mac"; then
    echo "Not on home network (router <${mac:-unknown}>)"
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
