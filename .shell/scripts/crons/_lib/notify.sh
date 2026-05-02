# shellcheck shell=bash
# Thin intent-named wrappers around `alerter`. Source from an entrypoint:
#
#   . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../_lib/notify.sh"
#
# Every wrapper passes --ignore-dnd so alerts surface during Do Not Disturb.

# Returns the path to a `warning.png` sitting next to the *calling* script,
# or empty if not present. Callers can pass an explicit icon path instead.
_icon_default() {
  # BASH_SOURCE[1] = the file that sourced/called us
  local caller_dir
  caller_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
  local candidate="${caller_dir}/warning.png"
  [[ -f "$candidate" ]] && printf '%s' "$candidate"
}

# Quiet timed notification. Fire-and-forget.
#   _notify_quiet <title> <message> <timeout_sec> [icon_path]
_notify_quiet() {
  local title="$1" message="$2" timeout="$3" icon="${4:-$(_icon_default)}"
  local args=(--message "$message" --title "$title" --ignore-dnd --timeout "$timeout")
  [[ -n "$icon" ]] && args+=(--app-icon "$icon")
  alerter "${args[@]}" >/dev/null &
  disown
}

# Sticky notification (no timeout). Fire-and-forget.
#   _notify_sticky <title> <message> [icon_path]
_notify_sticky() {
  local title="$1" message="$2" icon="${3:-$(_icon_default)}"
  local args=(--message "$message" --title "$title" --ignore-dnd)
  [[ -n "$icon" ]] && args+=(--app-icon "$icon")
  alerter "${args[@]}" >/dev/null &
  disown
}

# Actionable notification. Blocks; echoes the chosen action label on stdout
# (or @CONTENTCLICKED / @CLOSED / @ACTIONCLICKED on the corresponding events).
#   _notify_actionable <title> <message> <action_label> [icon_path]
_notify_actionable() {
  local title="$1" message="$2" action="$3" icon="${4:-$(_icon_default)}"
  local args=(--message "$message" --title "$title" --actions "$action" --ignore-dnd)
  [[ -n "$icon" ]] && args+=(--app-icon "$icon")
  alerter "${args[@]}"
}
