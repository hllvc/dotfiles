#!/usr/bin/env bash
#
# cmcp — start Claude Code with selected MCP servers opted in for one session.
#
# MCP is off by default (allowedMcpServers: [] in ~/.claude/settings.json).
# Allowlist entries merge across settings sources, so a --settings flag can
# re-allow servers for a single session without touching the settings file.
#
# Usage: cmcp [-c] [-l] [-h] <server>... [-- <claude args>]
#   server   a claude.ai connector alias (see -l) or a user-added server name
#   -c       check only: run `claude mcp list` with the same allowlist
#   -l       list known connector aliases
#   -h       help
#
# Examples:
#   cmcp notion                 # Notion connector only
#   cmcp notion slack -- -c     # Notion + Slack, continue last session
#   cmcp testapi                # user-added server, matched by name
#   cmcp -c figma               # check what would load

set -eo pipefail

# claude.ai connectors must match by URL: their names ("claude.ai Notion")
# contain spaces and dots, which serverName entries reject silently.
declare -A CONNECTORS=(
  [notion]="https://mcp.notion.com/*"
  [slack]="https://mcp.slack.com/*"
  [fathom]="https://api.fathom.ai/*"
  [posthog]="https://mcp.posthog.com/*"
  [figma]="https://mcp.figma.com/*"
  [excalidraw]="https://mcp.excalidraw.com/*"
  [docs]="https://api.anthropic.com/v1/pages/*"
  [gdrive]="https://drivemcp.googleapis.com/*"
  [gcal]="https://calendarmcp.googleapis.com/*"
)

usage() {
  sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
}

list() {
  local name
  for name in $(printf '%s\n' "${!CONNECTORS[@]}" | sort); do
    printf '  %-12s %s\n' "$name" "${CONNECTORS[$name]}"
  done
}

check=false
servers=()
while (( $# )); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -l|--list) list; exit 0 ;;
    -c|--check) check=true ;;
    --) shift; break ;;
    -*) echo "cmcp: unknown option: $1" >&2; usage >&2; exit 1 ;;
    *) servers+=("$1") ;;
  esac
  shift
done

if (( ${#servers[@]} == 0 )); then
  echo "cmcp: name at least one server" >&2
  usage >&2
  exit 1
fi

entries=()
for server in "${servers[@]}"; do
  key="${server,,}"
  if [[ -n "${CONNECTORS[$key]:-}" ]]; then
    entries+=("$(jq -cn --arg u "${CONNECTORS[$key]}" '{serverUrl: $u}')")
  elif [[ "$server" =~ ^[A-Za-z0-9_-]+$ ]]; then
    entries+=("$(jq -cn --arg n "$server" '{serverName: $n}')")
  else
    echo "cmcp: '$server' is not a known connector (see -l) or a valid server name" >&2
    exit 1
  fi
done

settings="$(printf '%s\n' "${entries[@]}" | jq -cs '{allowedMcpServers: .}')"

if [[ "$check" == true ]]; then
  exec claude --settings "$settings" mcp list
fi

exec claude --settings "$settings" "$@"
