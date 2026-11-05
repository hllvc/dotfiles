#!/usr/bin/env bash
#
# cmcp — start Claude Code with selected MCP servers opted in for one session.
#
# The claude() wrapper loads no MCP servers (allowedMcpServers: []); cmcp
# builds the same --settings with the named servers allowed instead. Servers
# in deniedMcpServers (~/.claude/settings.json) stay off either way.
#
# Usage: cmcp [-a] [-c] [-l] [-h] <server>... [-- <claude args>]
#   server   a claude.ai connector alias (see -l) or a user-added server name
#   -a       all: every remote server (serverUrl "*") plus every configured
#            server by name (user scope, this project, .mcp.json)
#   -c       check only: run `claude mcp list` with the same allowlist
#   -l       list known connector aliases
#   -n       print every pickable name (aliases + configured servers), one per line
#   -h       help
#
# Examples:
#   cmcp notion                 # Notion connector only
#   cmcp notion slack -- -c     # Notion + Slack, continue last session
#   cmcp testapi                # user-added server, matched by name
#   cmcp -c figma               # check what would load
#   cmcp -a                     # everything

set -eo pipefail

# claude.ai connectors must match by URL: their names ("claude.ai Notion")
# contain spaces and dots, which serverName entries reject silently.
declare -A CONNECTORS=(
  [notion]="https://mcp.notion.com/*"
  [slack]="https://mcp.slack.com/*"
  [fathom]="https://api.fathom.ai/*"
  [figma]="https://mcp.figma.com/*"
  [docs]="https://api.anthropic.com/v1/pages/*"
  [gdrive]="https://drivemcp.googleapis.com/*"
  [gcal]="https://calendarmcp.googleapis.com/*"
  [aws]="https://aws-mcp.*.api.aws/*"
  [granola]="https://mcp.granola.ai/*"
  [gdocs]="https://docsmcp.googleapis.com/*"
  [gsheets]="https://sheetsmcp.googleapis.com/*"
  [gslides]="https://slidesmcp.googleapis.com/*"
  [gmail]="https://gmailmcp.googleapis.com/*"
  [jam]="https://mcp.jam.dev/*"
)

usage() {
  sed -n '3,24p' "$0" | sed 's/^# \{0,1\}//'
}

list() {
  local name
  for name in $(printf '%s\n' "${!CONNECTORS[@]}" | sort); do
    printf '  %-12s %s\n' "$name" "${CONNECTORS[$name]}"
  done
}

# Names of every configured server: user scope, this project in
# ~/.claude.json, and the project's .mcp.json.
configured() {
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  jq -r --arg pwd "$PWD" --arg top "$top" '
    (.mcpServers // {} | keys[]),
    (.projects[$pwd].mcpServers // {} | keys[]),
    (.projects[$top].mcpServers // {} | keys[])' ~/.claude.json 2>/dev/null || true
  if [[ -n "$top" && -f "$top/.mcp.json" ]]; then
    jq -r '.mcpServers // {} | keys[]' "$top/.mcp.json" 2>/dev/null || true
  fi
}

all=false
check=false
servers=()
while (( $# )); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -l|--list) list; exit 0 ;;
    -n|--names) { printf '%s\n' "${!CONNECTORS[@]}"; configured; } | sort -u; exit 0 ;;
    -a|--all) all=true ;;
    -c|--check) check=true ;;
    --) shift; break ;;
    -*) echo "cmcp: unknown option: $1" >&2; usage >&2; exit 1 ;;
    *) servers+=("$1") ;;
  esac
  shift
done

if (( ${#servers[@]} == 0 )) && [[ "$all" != true ]]; then
  echo "cmcp: name at least one server" >&2
  usage >&2
  exit 1
fi

entries=()
if [[ "$all" == true ]]; then
  entries+=('{"serverUrl":"*"}')
  while IFS= read -r name; do
    [[ "$name" =~ ^[A-Za-z0-9_-]+$ ]] \
      && entries+=("$(jq -cn --arg n "$name" '{serverName: $n}')")
  done < <(configured | sort -u)
fi
for server in ${servers[@]+"${servers[@]}"}; do
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

settings="$("$HOME/.shell/scripts/unloaded/claude-settings.sh" "${entries[@]}")"

if [[ "$check" == true ]]; then
  exec claude --settings "$settings" mcp list
fi

# Record what this session was started with, for claude-pane.sh (prefix+C-r):
# exec keeps this pid, and the start time guards against pid reuse.
args_used="${servers[*]-}"
[[ "$all" != true ]] || args_used="-a $args_used"
mkdir -p "$HOME/.claude/cmcp"
printf '%s\n%s\n' "$(ps -o lstart= -p $$)" "${args_used% }" >"$HOME/.claude/cmcp/$$"

exec claude --settings "$settings" "$@"
