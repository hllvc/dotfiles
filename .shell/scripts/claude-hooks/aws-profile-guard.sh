#!/usr/bin/env bash
#
# Claude Code PreToolUse hook (matcher: Bash): always ask before a command uses
# a production AWS profile (sg-prod, sg-prod-eu, sg-prod-us, any sg-prod-*;
# sg-prod-ro is exempt). Registered in .claude/settings.json with
# onFailure "block", so a broken guard stops Bash instead of waving it through.
#
# The text rules in settings.json only match exact spellings; this parses the
# command (aws-profile-guard.py), so --profile=NAME, quotes and ; endings count.
# Cases it must keep getting right: aws-profile-guard.cases, run by
# aws-profile-guard.test.sh.

set -u

input="$(cat)"

# Fast path, no Python: every selector contains "profile" (AWS_PROFILE too).
grep -qi 'profile' <<<"$input" || exit 0

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
python=python3
[[ -x /opt/homebrew/bin/python3 ]] && python=/opt/homebrew/bin/python3

if out="$("$python" "$here/aws-profile-guard.py" <<<"$input" 2>/dev/null)"; then
  [[ -z "$out" ]] || printf '%s\n' "$out"
  exit 0
fi

# The parser itself failed. Ask whenever the text mentions a sg-prod profile,
# rather than letting it through unchecked.
if grep -qi 'sg-prod' <<<"$input"; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Production AWS profile guard could not parse this command and it mentions sg-prod. Approve only if you meant it."}}'
fi
exit 0
