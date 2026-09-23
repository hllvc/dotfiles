#!/usr/bin/env bash

# Watches one specific 5 GHz link for the ISP router's silent NSS 2 → 1 collapse
# (Tx Rate falls ~866 → <300 Mbps while the signal stays strong) and bounces the
# radio to recover it.
#
# Scope is the Wi-Fi link itself, never the default route: the radio is kept
# healthy even while Ethernet is carrying all the traffic, because the whole
# point is that the link is already usable again by the time Wi-Fi is needed.
#
# Single-shot by design: launchd re-runs it on StartInterval and on network
# change (WatchPaths). Strike count and cooldown live in the state file, not in
# a `sleep` loop — a long-lived bash loop leaks shells across sleep/wake.
#
#   entrypoint.sh [--dry-run] [--status]

# shellcheck source=../_lib/log.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../_lib/log.sh"
# shellcheck source=../_lib/notify.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../_lib/notify.sh"

# ─── tunables ──────────────────────────────────────────────────────────── {{{

readonly IFACE="en0"        # Wi-Fi interface (`networksetup -listallhardwareports`)
readonly SSID_MATCH="hllvc" # only this network is watched; "" watches any
readonly RATE_FLOOR=300     # Mbps — Tx Rate must be under this to count
readonly RSSI_FLOOR=-70     # dBm — RSSI must be strictly better than this
readonly NSS_FLOOR=1        # spatial streams — must be at or below this
readonly STRIKES=3          # consecutive samples meeting ALL of the above
readonly COOLDOWN=60        # s — quiet period after a bounce before checking again
readonly BOUNCE_DELAY=3     # s — radio off→on gap
readonly REJOIN_TIMEOUT=30  # s — how long to wait for SSID_MATCH after a bounce
readonly STALE_AFTER=900    # s — ignore a strike streak older than this (post-wake)

# A bounce needs ALL THREE to hold for STRIKES samples in a row:
#   Tx Rate < RATE_FLOOR, RSSI > RSSI_FLOOR, NSS <= NSS_FLOOR.
# Any one of them failing resets the streak. NSS is the load-bearing one: a link
# can sit well under RATE_FLOOR at full strength while still running two streams
# (86 Mbps at NSS 2 has been observed here), and cycling the radio for that
# would be pure disruption — it is congestion or rate adaptation, not the fault.

# Poll interval is launchd's, not ours: StartInterval in
# ~/.config/launch-agents/com.hllvc.wifi-watchdog.plist (default 30 s).

#}}}: tunables

readonly LOG_DIR="${HOME}/Library/Logs/com.hllvc.wifi-watchdog"
readonly LOG_FILE="${LOG_DIR}/main.log"
readonly CACHE_DIR="${HOME}/Library/Caches/com.hllvc.wifi-watchdog"
mkdir -p "$LOG_DIR" "$CACHE_DIR"

readonly SYSLOG_TAG="wifi-watchdog"
readonly WDUTIL="/usr/bin/wdutil"

DRY_RUN=0
STATUS_ONLY=0
for arg in "$@"; do
  case "$arg" in
  --dry-run) DRY_RUN=1 ;;
  --status) STATUS_ONLY=1 ;;
  -h | --help)
    sed -n '3,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "unknown argument: $arg" >&2
    exit 2
    ;;
  esac
done
readonly DRY_RUN STATUS_ONLY

# A hand-run --dry-run must not disturb the live agent's strike streak or
# cooldown, so it keeps its own state file.
if ((DRY_RUN)); then
  readonly STATE_FILE="${CACHE_DIR}/state.dryrun"
else
  readonly STATE_FILE="${CACHE_DIR}/state"
fi

# Mirror one line to syslog. The tag is repeated inside the message on purpose:
# macOS does not preserve `logger -t` in the unified log (the entry's process is
# just "logger"), so the tag in the body is the only thing left to match on.
#
#   log show --last 1h --predicate 'eventMessage BEGINSWITH "wifi-watchdog:"'
_say() {
  logger -t "$SYSLOG_TAG" "${SYSLOG_TAG}: $1"
}

# ─── link sampling ─────────────────────────────────────────────────────── {{{

# Whether the radio is powered. Power state is NOT redacted, unlike the SSID.
_radio_on() {
  [[ "$(networksetup -getairportpower "$IFACE" 2>/dev/null)" == *": On" ]]
}

# Cheap association proxy (~5 ms): an associated interface has an IPv4 address.
# Worth checking before the ~2 s sample below.
_has_address() {
  [[ -n "$(ipconfig getifaddr "$IFACE" 2>/dev/null)" ]]
}

# Emits shell-assignable KEY=VALUE for the current link.
#
# `wdutil info` is the source because it is the only one that reports NSS, and
# NSS is the whole diagnosis — it separates the fault (one stream at strong
# signal) from a link that is merely slow. Everything else was ruled out by
# measurement:
#
#   airport -I        removed in macOS 14.4
#   networksetup      claims "not associated" while the link is up and routing
#   scutil            empty SSID_STR, BSSID 0x020000000000
#   ipconfig          SSID "<redacted>"
#   system_profiler   works, ~5.2 s, but reports no NSS at any detail level,
#                     and its MCS Index is unreliable — observed pinned at 4
#                     while Tx Rate swung 351 → 526 Mbps
#
# The unprivileged sources are redacted because macOS gates SSID/BSSID behind
# Location Services; as root, wdutil is not. It needs the sudoers rule this
# directory installs, and costs ~2.2 s.
#
# Only the first occurrence of each key is taken: the Wi-Fi section comes first
# and later sections repeat keys (a second "RSSI : 0 dBm" for AWDL, say).
_sample_link() {
  sudo -n "$WDUTIL" info 2>/dev/null | awk '
    function q(s) { gsub(/'"'"'/, "", s); return "'"'"'" s "'"'"'" }
    {
      line = $0
      sub(/^[ \t]+/, "", line)
      p = index(line, ":")
      if (p == 0) next
      key = substr(line, 1, p - 1)
      val = substr(line, p + 1)
      sub(/[ \t]+$/, "", key)
      sub(/^[ \t]+/, "", val); sub(/[ \t]+$/, "", val)
      if (key in seen) next       # first section (Wi-Fi) wins
      seen[key] = 1
      if      (key == "SSID")      ssid = val
      else if (key == "RSSI")    { rssi = val;  sub(/ dBm$/,  "", rssi) }
      else if (key == "Noise")   { noise = val; sub(/ dBm$/,  "", noise) }
      else if (key == "Tx Rate") { rate = val;  sub(/ Mbps$/, "", rate) }
      else if (key == "MCS Index") mcs = val
      else if (key == "NSS")       nss = val
      else if (key == "PHY Mode")  phy = val
      else if (key == "Channel") {
        # "5g36/80" -> band 5g, channel 36, width 80
        chan = val
        if (match(val, /^[0-9]+g/)) {
          band = substr(val, RSTART, RLENGTH)
          rest = substr(val, RSTART + RLENGTH)
          split(rest, c, "/")
          chan = c[1]; width = c[2]
        }
      }
    }
    END {
      printf "ssid=%s\n",  q(ssid)
      printf "phy=%s\n",   q(phy)
      printf "rate=%s\n",  q(rate)
      printf "mcs=%s\n",   q(mcs)
      printf "nss=%s\n",   q(nss)
      printf "rssi=%s\n",  q(rssi)
      printf "noise=%s\n", q(noise)
      printf "chan=%s\n",  q(chan)
      printf "band=%s\n",  q(band)
      printf "width=%s\n", q(width)
    }
  '
}

#}}}: link sampling

# ─── state ─────────────────────────────────────────────────────────────── {{{

strike_count=0
last_bounce=0
last_seen=0
if [[ -f "$STATE_FILE" ]]; then
  read -r strike_count last_bounce last_seen <"$STATE_FILE" 2>/dev/null
  [[ "$strike_count" =~ ^[0-9]+$ ]] || strike_count=0
  [[ "$last_bounce" =~ ^[0-9]+$ ]] || last_bounce=0
  [[ "$last_seen" =~ ^[0-9]+$ ]] || last_seen=0
fi

now=$(date +%s)

# A streak only means something if the samples were consecutive. After sleep or
# a stopped agent the previous strike is stale — start over rather than bounce
# on a single fresh low sample.
if ((strike_count > 0 && last_seen > 0 && now - last_seen > STALE_AFTER)); then
  strike_count=0
fi

_save_state() {
  printf '%s %s %s\n' "$1" "$2" "$3" >"$STATE_FILE"
}

_report() { # color, verdict, metrics, context, extra
  _block_open "$LOG_FILE"
  _block_line "$LOG_FILE" "$(_color "$1" "$3")   $(_color "$1" "[ $2 ]")"
  [[ -n "${4:-}" ]] && _block_line "$LOG_FILE" "$(_color dim "$4")"
  [[ -n "${5:-}" ]] && _block_line "$LOG_FILE" "$5"
  _block_close "$LOG_FILE"
}

#}}}: state

# ─── gates ─────────────────────────────────────────────────────────────── {{{

# Cheap gates first (~5 ms each, against ~2.2 s for a full sample).

if ! _radio_on; then
  # Deliberately not switched back on: Wi-Fi being off is a decision the user
  # made, and a watchdog that undoes it is a worse bug than the one it fixes.
  _save_state 0 "$last_bounce" "$now"
  ((STATUS_ONLY)) && { printf 'RADIO OFF — %s powered down, left alone\n' "$IFACE"; exit 0; }
  _report dim "RADIO OFF" "no link" "${IFACE} powered down — left alone"
  _say "idle state=radio-off iface=${IFACE}"
  exit 0
fi

if ! _has_address; then
  _save_state 0 "$last_bounce" "$now"
  ((STATUS_ONLY)) && { printf 'UNASSOCIATED — radio on, no address on %s\n' "$IFACE"; exit 0; }
  _report dim "UNASSOCIATED" "no link" "radio on, no address on ${IFACE}"
  _say "idle state=unassociated iface=${IFACE}"
  exit 0
fi

# Post-bounce cooldown: the radio needs time to re-associate and settle, and a
# freshly joined link reports a low rate for a few seconds.
if ((now - last_bounce < COOLDOWN)) && ((!STATUS_ONLY)); then
  remaining=$((COOLDOWN - (now - last_bounce)))
  _save_state 0 "$last_bounce" "$now"
  _report dim "COOLDOWN" "settling" "${remaining}s left since last bounce"
  exit 0
fi

#}}}: gates

# ─── check ─────────────────────────────────────────────────────────────── {{{

# Declared up front so the shape of a sample is visible at the point of use —
# every one of these is assigned by the eval that follows.
ssid='' phy='' rate='' mcs='' nss='' rssi='' noise='' chan='' band='' width=''
eval "$(_sample_link)"

rate_i=${rate%%.*}
[[ "$rate_i" =~ ^[0-9]+$ ]] || rate_i=0
rssi_i=${rssi%%.*}
[[ "$rssi_i" =~ ^-?[0-9]+$ ]] || rssi_i=0
nss_i=${nss%%.*}
[[ "$nss_i" =~ ^[0-9]+$ ]] || nss_i=-1

metrics="${rate:-?} Mbps | NSS ${nss:-?} | ${rssi:-?}/${noise:-?} dBm | MCS ${mcs:-?}"
context="ch ${chan:-?} ${band:-?}/${width:-?}MHz | ${phy:-?} | ${ssid:-?}"

if ((STATUS_ONLY)); then
  printf '%s\n%s\nwatching: %s | strikes: %s/%s\n' \
    "$metrics" "$context" "${SSID_MATCH:-<any>}" "$strike_count" "$STRIKES"
  exit 0
fi

# No NSS means no diagnosis. Refusing to act is the only safe answer: without it
# a slow-but-healthy 2-stream link is indistinguishable from the fault, and
# guessing would bounce the radio for ordinary congestion.
if [[ -z "$rate" ]] || ((nss_i < 0)); then
  _save_state 0 "$last_bounce" "$now"
  if ! sudo -n "$WDUTIL" info &>/dev/null; then
    detail="sudo -n ${WDUTIL} info failed — run this cron's install.sh to add the sudoers rule"
  else
    detail="${WDUTIL} returned no usable link data"
  fi
  _report yellow "NO SOURCE" "unknown" "$detail" \
    "$(_color yellow "not bouncing — NSS unknown")"
  _say "no-source ${detail}"
  exit 1
fi

# Watch exactly one network. Any other SSID — a hotspot, an office, a café — is
# somebody else's hardware, and bouncing the radio there is pure disruption.
if [[ -n "$SSID_MATCH" && "$ssid" != "$SSID_MATCH" ]]; then
  _save_state 0 "$last_bounce" "$now"
  _report dim "NOT WATCHED" "on \"${ssid}\"" "only \"${SSID_MATCH}\" is watched"
  exit 0
fi

# A parked link reports no rate adaptation at all: NSS 0, MCS 0, and a channel
# narrowed to 40 MHz. That is "no reading", not "one stream" — but 0 <= NSS_FLOOR,
# so without this gate it satisfies the NSS condition, and the low idle rate
# satisfies the rate condition, and the watchdog bounces the radio roughly every
# two minutes for as long as Ethernet stays primary.
#
# Measured: 10/10 samples read NSS 0 while en7 held the default route, and the
# reading did not come back for a light ping, an 84 KB burst, or sustained
# 1400-byte traffic sampled mid-flight. A link only reports NSS while it is the
# interface actually carrying traffic (NSS 2, MCS 4-7, 80 MHz when it was).
#
# So the fault cannot be diagnosed while Wi-Fi is parked — and it does no harm
# there either. It is caught once Wi-Fi carries traffic again, within STRIKES
# samples, or sooner off the WatchPaths trigger.
if ((nss_i < 1)); then
  _save_state 0 "$last_bounce" "$now"
  _report dim "IDLE" "$metrics" "$context" \
    "$(_color dim "link parked (NSS 0) — nothing to judge until it carries traffic")"
  _say "idle-link ssid=${ssid} rate=${rate_i} rssi=${rssi_i} nss=0"
  exit 0
fi

# All three conditions, evaluated together. Naming each failure separately is
# what makes the log answer "why didn't it fire?" without a rerun.
reasons=""
((nss_i > NSS_FLOOR)) && reasons="NSS ${nss_i} > ${NSS_FLOOR}"
((rate_i >= RATE_FLOOR)) && reasons="${reasons:+$reasons, }rate ${rate_i} ≥ ${RATE_FLOOR}"
((rssi_i <= RSSI_FLOOR)) && reasons="${reasons:+$reasons, }RSSI ${rssi_i} ≤ ${RSSI_FLOOR}"

if [[ -n "$reasons" ]]; then
  # INHIBITED is reserved for the case where the signal guard is the ONLY thing
  # standing in the way — that is the one worth noticing when tuning RSSI_FLOOR.
  # If the rate or NSS also disqualified the sample, the link is simply fine.
  if ((rate_i < RATE_FLOOR)) && ((rssi_i <= RSSI_FLOOR)) && ((nss_i <= NSS_FLOOR)); then
    _save_state 0 "$last_bounce" "$now"
    _report yellow "INHIBITED" "$metrics" "$context" \
      "$(_color yellow "${reasons} — weak signal, not the radio fault")"
    _say "inhibited ssid=${ssid} rate=${rate_i} rssi=${rssi_i} nss=${nss} reason=weak-signal"
  else
    _save_state 0 "$last_bounce" "$now"
    _report green "OK" "$metrics" "$context" "$(_color dim "${reasons} — strikes reset")"
    _say "ok ssid=${ssid} rate=${rate_i} rssi=${rssi_i} nss=${nss}"
  fi
  exit 0
fi

strike_count=$((strike_count + 1))

if ((strike_count < STRIKES)); then
  _save_state "$strike_count" "$last_bounce" "$now"
  _report yellow "STRIKE ${strike_count}/${STRIKES}" "$metrics" "$context" \
    "$(_color dim "rate ${rate_i} < ${RATE_FLOOR}, RSSI ${rssi_i} > ${RSSI_FLOOR}, NSS ${nss} ≤ ${NSS_FLOOR}")"
  _say "strike ${strike_count}/${STRIKES} ssid=${ssid} rate=${rate_i} rssi=${rssi_i} nss=${nss}"
  exit 0
fi

#}}}: check

# ─── bounce ────────────────────────────────────────────────────────────── {{{

if ((DRY_RUN)); then
  _save_state 0 "$now" "$now"
  _report red "DRY RUN" "$metrics" "$context" \
    "$(_color red "would bounce ${IFACE}: off → ${BOUNCE_DELAY}s → on, rejoin \"${SSID_MATCH:-any}\", ${COOLDOWN}s cooldown")"
  _say "dry-run would-bounce ssid=${ssid} rate=${rate_i} rssi=${rssi_i} nss=${nss}"
  exit 0
fi

_say "bouncing iface=${IFACE} ssid=${ssid} rate=${rate_i} rssi=${rssi_i} nss=${nss}"

bounce_err=""
if ! networksetup -setairportpower "$IFACE" off 2>&1; then
  bounce_err="power off failed"
else
  sleep "$BOUNCE_DELAY"
  networksetup -setairportpower "$IFACE" on 2>&1 || bounce_err="power on failed"
fi

# Record the bounce even on failure — the cooldown keeps a broken interface from
# being hammered once every StartInterval.
_save_state 0 "$now" "$now"

if [[ -n "$bounce_err" ]]; then
  _report red "BOUNCE FAILED" "$metrics" "$context" \
    "$(_color red "$bounce_err — ${IFACE} may be left down")"
  _say "bounce failed iface=${IFACE} err=${bounce_err}"
  command -v alerter &>/dev/null &&
    _notify_sticky "Wi-Fi watchdog failed" "${bounce_err} on ${IFACE}" "Dismiss"
  exit 1
fi

# Wait for re-association cheaply, then confirm the SSID once.
waited=0
while ((waited < REJOIN_TIMEOUT)) && ! _has_address; do
  sleep 2
  waited=$((waited + 2))
done

if ! _has_address; then
  _report red "REJOIN TIMEOUT" "$metrics" "$context" \
    "$(_color red "no address on ${IFACE} within ${REJOIN_TIMEOUT}s of the bounce")"
  _say "rejoin timeout iface=${IFACE} after=${REJOIN_TIMEOUT}s"
  command -v alerter &>/dev/null &&
    _notify_sticky "Wi-Fi did not reconnect" "${IFACE} idle ${REJOIN_TIMEOUT}s after bounce" "Dismiss"
  exit 1
fi

# Verify it came back on the *same* network. macOS auto-joins from the keychain,
# but preference order is not ours to assume — and silently landing on a
# neighbour's open network would look like a fix while being the opposite.
eval "$(_sample_link | grep '^ssid=')"
rejoined="$ssid"

if [[ -n "$SSID_MATCH" && "$rejoined" != "$SSID_MATCH" ]]; then
  # One nudge back, relying on the keychain credential; no password is passed or
  # stored here. If it does not take, say so rather than pretend it worked.
  networksetup -setairportnetwork "$IFACE" "$SSID_MATCH" &>/dev/null || true
  sleep 3
  eval "$(_sample_link | grep '^ssid=')"
  rejoined="$ssid"
fi

if [[ -n "$SSID_MATCH" && "$rejoined" != "$SSID_MATCH" ]]; then
  _report red "WRONG NETWORK" "$metrics" "$context" \
    "$(_color red "rejoined \"${rejoined}\" instead of \"${SSID_MATCH}\"")"
  _say "rejoin wrong-network got=${rejoined} want=${SSID_MATCH}"
  command -v alerter &>/dev/null &&
    _notify_sticky "Wi-Fi rejoined wrong network" "On \"${rejoined}\", expected \"${SSID_MATCH}\"" "Dismiss"
  exit 1
fi

_report red "BOUNCED" "$metrics" "$context" \
  "$(_color red "${IFACE} cycled after ${STRIKES} strikes, back on \"${rejoined}\" — cooldown ${COOLDOWN}s")"
_say "bounced iface=${IFACE} ssid=${rejoined} ok"
command -v alerter &>/dev/null &&
  _notify_quiet "Wi-Fi bounced" "${metrics} — cycled ${IFACE}" 10

#}}}: bounce
