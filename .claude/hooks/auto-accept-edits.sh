#!/bin/bash
# =============================================================================
# Auto-Accept Edits Hook for Claude Code
# =============================================================================
#
# PROBLEM:
#   Claude Code's "acceptEdits" mode has a bug where it still prompts for
#   permission on Edit/Write operations even when the mode is enabled.
#
# SOLUTION:
#   This PermissionRequest hook intercepts permission dialogs and auto-approves
#   file operations based on the current permission mode.
#
# BEHAVIOR:
#   - acceptEdits mode: Auto-accepts all Edit/Write/MultiEdit operations
#   - plan mode:        Auto-accepts only plan files (~/.claude/plans/*)
#   - ask mode:         Normal permission prompts (no interference)
#
# INSTALLATION:
#   1. Place this script at: ~/.claude/hooks/auto-accept-edits.sh
#   2. Make executable: chmod +x ~/.claude/hooks/auto-accept-edits.sh
#   3. Add to ~/.claude/settings.json under "hooks":
#
#      "PermissionRequest": [
#        {
#          "matcher": "Edit|Write|MultiEdit",
#          "hooks": [
#            {
#              "type": "command",
#              "command": "bash ~/.claude/hooks/auto-accept-edits.sh"
#            }
#          ]
#        }
#      ]
#
#   4. Restart Claude Code
#
# DEBUGGING:
#   Uncomment the DEBUG_LOG lines below to enable logging to /tmp/
#
# =============================================================================

set -euo pipefail

# Uncomment for debugging:
# DEBUG_LOG="/tmp/auto-accept-edits-debug.log"
# log() { echo "$(date): $1" >> "$DEBUG_LOG"; }

input=$(cat)

tool_name=$(echo "$input" | jq -r '.tool_name // empty')
permission_mode=$(echo "$input" | jq -r '.permission_mode // "ask"')
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

output_allow() {
  echo '{"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {"behavior": "allow"}}}'
}

# Only handle file operation tools
if [[ "$tool_name" == "Edit" ]] || [[ "$tool_name" == "Write" ]] || [[ "$tool_name" == "MultiEdit" ]]; then

  # acceptEdits mode: allow all file operations
  if [[ "$permission_mode" == "acceptEdits" ]]; then
    output_allow
    exit 0
  fi

  # plan mode: only allow plan files
  if [[ "$permission_mode" == "plan" ]] && [[ "$file_path" == *"/.claude/plans/"* ]]; then
    output_allow
    exit 0
  fi
fi

exit 0
