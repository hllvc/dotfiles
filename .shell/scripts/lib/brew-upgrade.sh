#!/usr/bin/env bash
#
# The Homebrew upgrade sequence shared by `brewup` (interactive) and the
# homebrew-update cron (unattended), so the two can't drift apart:
#
#   brew update → versions pins → versions auto → brew upgrade --greedy
#   (formulae + all casks) → autoremove + cleanup → link skills
#
# `versions pins`/`auto` (dotctl) keep tmux/neovim/fzf pinned and apply the
# upgrades their .versions pin level allows; `brew upgrade` skips them. Every
# step runs even when an earlier one failed. Output streams as it comes, each
# step under a "── <step> ──" header; the last line is "FAILED: a, b" (exit 1)
# when anything failed. No logging or notifying here: callers decide.

set -u

# ~/.shell links into the dotfiles repo, so the physical path leads to it.
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"
readonly LINK_SKILLS="$SCRIPT_DIR/../crons/homebrew-update/link-skills.sh"

# The "brew cleanup -s" step below covers what brew would otherwise clean up
# after each upgrade on its own; skip that so it runs once.
export HOMEBREW_NO_INSTALL_CLEANUP=1

failed=()

# brew traps Ctrl-C and exits 130 instead of dying of the signal, so bash
# wouldn't stop on its own and _step would just record a failure and go on.
trap 'printf "\ninterrupted\n" >&2; exit 130' INT

_step() {
  local label="$1"
  shift
  printf '\n── %s ──\n' "$label"
  "$@" || failed+=("$label")
}

_step "brew update" brew update
_step "versions pins" "$REPO_ROOT/dotctl" versions pins
_step "versions auto" "$REPO_ROOT/dotctl" versions auto
# --greedy takes in auto_updates and version :latest casks too, so formulae and
# every cask go in one pass.
_step "brew upgrade" brew upgrade --greedy
_step "brew autoremove" brew autoremove
_step "brew cleanup -s" brew cleanup -s
# cleanup just deleted the old Caskroom versions skill links point into.
_step "link skills" bash "$LINK_SKILLS"

if ((${#failed[@]})); then
  summary="$(IFS=,; echo "${failed[*]}" | sed 's/,/, /g')"
  printf '\nFAILED: %s\n' "$summary"
  # For a caller that streams the output to a terminal (brewup) and so can't
  # pick the line out of it.
  if [[ -n "${BREW_UPGRADE_FAILED_FILE:-}" ]]; then
    printf '%s\n' "$summary" >"$BREW_UPGRADE_FAILED_FILE"
  fi
  exit 1
fi
