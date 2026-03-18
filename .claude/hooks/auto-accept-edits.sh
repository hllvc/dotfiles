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
#   This PreToolUse hook intercepts tool calls and auto-approves file operations
#   based on the current permission mode. PreToolUse fires for both the main
#   session and spawned subagents/teammates.
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
#      "PreToolUse": [
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
#   Set CLAUDE_HOOK_DEBUG=1 to enable logging:
#     export CLAUDE_HOOK_DEBUG=1
#   Logs written to: /tmp/auto-accept-edits.log
#   View live: tail -f /tmp/auto-accept-edits.log
#
# =============================================================================

set -euo pipefail

LOG_FILE="/tmp/auto-accept-edits.log"

log() {
  [[ "${CLAUDE_HOOK_DEBUG:-0}" == "1" ]] || return 0
  echo "[$(date '+%H:%M:%S')] $1" >>"$LOG_FILE"
}

input=$(cat)

tool_name=$(echo "$input" | jq -r '.tool_name // empty')
permission_mode=$(echo "$input" | jq -r '.permission_mode // "ask"')
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

log "hook fired: tool=$tool_name mode=$permission_mode file=$file_path"

output_allow() {
  log "AUTO-APPROVED: $tool_name -> $file_path"
  echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}'
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

  log "PASSTHROUGH: mode=$permission_mode (not auto-approving)"
fi

exit 0
