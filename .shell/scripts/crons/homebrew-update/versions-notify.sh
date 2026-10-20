#!/usr/bin/env bash
# Version-drift alert for the homebrew-update cron. Lists the tools whose
# installed version moved away from .versions and offers two ways in:
#
#   Plan with Claude  a Claude Code session in the dotfiles repo, in plan mode,
#                     that reads the changes and proposes config edits
#   Show report       the plain `dotctl versions --brief` report
#
# Blocks until the alert is answered, so entrypoint.sh starts it detached.
#
#   versions-notify.sh <report-file> <repo-root>

set -u

# shellcheck source=../_lib/notify.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../_lib/notify.sh"

readonly REPORT="$1"
readonly REPO_ROOT="$2"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

count=$(grep -c . "$REPORT")
# One line per issue reads badly in a banner; join them and let alerter clip.
message=$(paste -sd ';' "$REPORT" | sed 's/;/ · /g')

choice=$(_notify_actionable \
  "Dotfiles: ${count} version note(s) to review" \
  "$message" \
  "Plan with Claude,Show report")

case "$choice" in
"Plan with Claude")
  bash "$SCRIPT_DIR/versions-review.sh" "$REPO_ROOT"
  ;;
"Show report" | @CONTENTCLICKED)
  open -t "$REPORT"
  ;;
esac
