#!/usr/bin/env bash
#
# claude-settings — the --settings JSON for interactive `claude` launches.
# Shared by the claude() wrapper in ~/.shell/functions and cmcp.sh.
#
# Usage: claude-settings.sh [<allowlist entry JSON>...]
#   No entries: allowedMcpServers is [], so the session loads no MCP servers.
#   Entries:    only those servers are allowed (cmcp builds them).
#
# Also routes non-repo sessions on a side (~/.repos/<side> root or anywhere
# under its 00-artifacts, nested repos included) to that side's memory store.
#
# Anything that runs the claude binary directly (IDEs, other tools) skips
# this and gets every server not in deniedMcpServers.

set -eo pipefail

side=
case "$PWD/" in
  "$HOME/.repos/stackguardian/"|"$HOME/.repos/stackguardian/00-artifacts/"*) side=stackguardian ;;
  "$HOME/.repos/private/"|"$HOME/.repos/private/00-artifacts/"*) side=private ;;
esac

memory=
[[ -n "$side" ]] && memory="$HOME/.claude/projects/-Users-hllvc--repos-$side-00-artifacts/memory"

printf '%s\n' "$@" | jq -cs --arg mem "$memory" '
  {allowedMcpServers: map(select(. != null))}
  + (if $mem == "" then {} else {autoMemoryDirectory: $mem} end)'
