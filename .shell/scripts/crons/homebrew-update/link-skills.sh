#!/usr/bin/env bash
# Point ~/.claude/skills/<skill> at the skill a Homebrew cask ships, resolved
# through the cask's stable bin symlink so the link follows `brew upgrade`.
#
# Caskroom paths carry the version (Caskroom/<cask>/<version>/...), and
# `brew cleanup` deletes the old one, so a link made at install time dangles
# after the next upgrade. Run after upgrades (entrypoint.sh) and after stow
# (dotctl stow). Idempotent; only ever replaces a symlink, never a real dir.
#
# These links must NOT live in the repo: stow refuses absolute symlinks and
# aborts the whole run. terminal-browser writes one there by itself (via
# ~/.agents/skills -> repo/.claude/skills), so the path is in .gitignore and
# .stow-local-ignore.

set -euo pipefail

readonly BREW_BIN="${HOMEBREW_PREFIX:-/opt/homebrew}/bin"
readonly SKILLS_DIR="$HOME/.claude/skills"

# <bin name> <skill path relative to the cask root, i.e. <bin>/..> <link name>
readonly SKILLS=(
  "terminal-browser skills/default/terminal-browser terminal-browser"
)

rc=0
for entry in "${SKILLS[@]}"; do
  read -r bin rel name <<<"$entry"
  anchor="$BREW_BIN/$bin"
  link="$SKILLS_DIR/$name"

  if [[ -e "$link" && ! -L "$link" ]]; then
    echo "  $name: $link is a real path, not a symlink — left alone" >&2
    rc=1
    continue
  fi

  if [[ ! -e "$anchor" ]]; then
    # Cask gone: drop our link only if it now dangles.
    if [[ -L "$link" && ! -e "$link" ]]; then
      rm -f "$link"
      echo "  $name: $bin not installed, removed dangling link"
    else
      echo "  $name: $bin not installed, skipped"
    fi
    continue
  fi

  root="$(cd -P "$(dirname "$(readlink -f "$anchor")")/.." && pwd)"
  target="$root/$rel"
  if [[ ! -f "$target/SKILL.md" ]]; then
    echo "  $name: no SKILL.md under $target" >&2
    rc=1
    continue
  fi

  if [[ "$(readlink "$link" 2>/dev/null)" == "$target" ]]; then
    echo "  $name: up to date"
  else
    mkdir -p "$SKILLS_DIR"
    ln -sfn "$target" "$link"
    echo "  $name: -> $target"
  fi
done
exit "$rc"
