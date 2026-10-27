#!/usr/bin/env bash
#
# brewup: the manual Homebrew upgrade.
#
#   brewup       upgrade everything (lib/brew-upgrade.sh, shared with the
#                homebrew-update cron), then report tools in .versions that
#                aren't at their tested version and triage them right away
#   brewup -n    preview: what's outdated and what the brew pins would let
#                through or hold; installs nothing
#
# Triage is the versions-review pipeline: verdicts print here; plans that need
# drafting run in the background and notify when ready ("Plan ready").

set -u

# ~/.shell links into the dotfiles repo, so the physical path leads to it.
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"
readonly DOTCTL="$REPO_ROOT/dotctl"
readonly CORE="$SCRIPT_DIR/lib/brew-upgrade.sh"
readonly REVIEW="$SCRIPT_DIR/crons/versions-review/review.sh"

_usage() {
  sed -n '3,/^$/s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
}

_section() {
  printf '\n── %s ──\n' "$1"
}

_preview() {
  _section "brew update"
  brew update || return 1
  _section "outdated (formulae + greedy casks)"
  brew outdated --greedy --greedy-auto-updates --greedy-latest
  _section "pinned formulae (.versions pin levels)"
  local held
  held="$("$DOTCTL" versions auto -n)"
  echo "${held:-all pinned formulae are current}"
}

case "${1:-}" in
"") ;;
-n)
  _preview
  exit
  ;;
-h | --help)
  _usage
  exit 0
  ;;
*)
  echo "brewup: unknown option: $1" >&2
  _usage >&2
  exit 1
  ;;
esac

failed_file="$(mktemp)"
trap 'rm -f "$failed_file"' EXIT
# Ctrl-C ends the whole run, not just the brew step it lands in.
trap 'exit 130' INT

# Straight to the terminal: brew keeps its progress bars and colors, and cask
# sudo prompts work.
BREW_UPGRADE_FAILED_FILE="$failed_file" bash "$CORE"
(($? == 130)) && exit 130

_section "versions"
# Prints only what isn't ok (or says all is), plus the recent silent accepts.
if ! "$DOTCTL" versions status --issues; then
  _section "triage"
  bash "$REVIEW" --auto --defer-plans
fi

if [[ -s "$failed_file" ]]; then
  printf '\nbrewup: FAILED: %s (see above)\n' "$(<"$failed_file")"
  exit 1
fi
