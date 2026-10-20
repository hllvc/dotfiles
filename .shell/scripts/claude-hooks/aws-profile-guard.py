#!/usr/bin/env python3
"""Parser behind aws-profile-guard.sh.

Reads a PreToolUse payload on stdin. When the Bash command selects a production
AWS profile, prints the hook decision that makes Claude Code ask first; prints
nothing when the command is fine.

A profile is production when its name starts with `sg-prod`, except the
read-only one, `sg-prod-ro`. That covers sg-prod, sg-prod-eu, sg-prod-us and any
sg-prod-* added later. A profile that is only known at run time ($VAR, $(...))
can't be checked, so it asks too.

The selectors it looks for, anywhere in the command text (quoting and heredocs
don't matter, so text that merely mentions one also asks):
  --profile NAME   --profile=NAME   AWS_PROFILE=NAME   AWS_DEFAULT_PROFILE=NAME
"""
import json
import re
import sys

PREFIX = "sg-prod"
ALLOWED = {"sg-prod-ro"}

SELECTOR = re.compile(
    r"""(?:--profile(?:=|\s+)|\bAWS_(?:DEFAULT_)?PROFILE=)["']?([^\s"';|&()<>`]*)"""
)


def findings(command):
    found = []
    for match in SELECTOR.finditer(command):
        value = match.group(1)
        if not value:
            continue
        if value.startswith("$"):
            found.append(f"the AWS profile is chosen at run time ({value}), so it can't be checked")
        elif value.lower().startswith(PREFIX) and value.lower() not in ALLOWED:
            found.append(f"'{value}' is a production AWS profile")
    return found


def main():
    payload = json.load(sys.stdin)
    command = (payload.get("tool_input") or {}).get("command") or ""
    found = findings(command)
    if not found:
        return
    reason = (
        "Production AWS profile guard: " + "; ".join(dict.fromkeys(found)) + ". "
        "StackGuardian production has write access. Approve only if you meant it "
        "(allowed without asking: default, dash, sg-prod-ro)."
    )
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "ask",
                    "permissionDecisionReason": reason,
                }
            }
        )
    )


if __name__ == "__main__":
    main()
