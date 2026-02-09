#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

readonly LAUNCH_AGENTS_SOURCE="$HOME/.config/launch-agents"
readonly REQUIRED_TOOLS=( "brew" "stow" )

usage() { #{{{
  cat <<EOF
Usage: ./load.sh [option]

Options:
  (none)    Symlink dotfiles to home and load LaunchAgents
  -a        Adopt existing files (convert to symlinks)
  -u        Unload LaunchAgents
  -h        Show this help message
EOF
}
#}}}: usage

_command_installed() { #{{{
  command -v "$1" &>/dev/null
}
#}}}: _command_installed

_install_brew() { #{{{
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  brew update
}
#}}}: _install_brew

_launchctl_load() { #{{{
  if [[ ! -d "$LAUNCH_AGENTS_SOURCE" ]]; then return 0; fi

  local uid
  uid=$(id -u)

  for file in "$LAUNCH_AGENTS_SOURCE"/*.plist; do
    filename=$(basename "$file")
    label="${filename%.plist}"
    ln -sfv "$file" "$HOME/Library/LaunchAgents/$filename"
    launchctl bootstrap "gui/$uid" "$HOME/Library/LaunchAgents/$filename" \
      || echo "Note: $label may already be loaded"
  done
}
#}}}: _launchctl_load

_launchctl_unload() { #{{{
  if [[ ! -d "$LAUNCH_AGENTS_SOURCE" ]]; then return 0; fi

  local uid
  uid=$(id -u)

  for file in "$LAUNCH_AGENTS_SOURCE"/*.plist; do
    filename=$(basename "$file")
    label="${filename%.plist}"
    if [[ -f "$HOME/Library/LaunchAgents/$filename" ]]; then
      launchctl bootout "gui/$uid/$label" \
        || echo "Note: $label may already be unloaded"
      rm -fv "$HOME/Library/LaunchAgents/$filename"
    fi
  done
}
#}}}: _launchctl_unload

main() { #{{{
  case "$ACTION" in
    adopt)   stow -v -t "$HOME" . --adopt ;;
    unload)  _launchctl_unload ;;
    *)       stow -v -t "$HOME" . && _launchctl_load ;;
  esac
}
#}}}: main

for tool in "${REQUIRED_TOOLS[@]}"; do
  if ! _command_installed "$tool" && [[ "$tool" == "brew" ]]; then
    _install_brew
  elif ! _command_installed "$tool"; then
    brew install "$tool"
  fi
done

ACTION="default"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -a) ACTION="adopt"; shift ;;
    -u) ACTION="unload"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

main
