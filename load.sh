#!/usr/bin/env bash

readonly LAUNCH_AGENTS_SOURCE="$HOME/.config/launch-agents"

_command_installed() { #{{{
  local command="$1"

  if command -v "$command" &>/dev/null; then
    return 0
  else
    return 1
  fi
}
#}}}: _command_installed

_install_brew() { #{{{
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  brew update && brew upgrade
}
#}}}: _install_brew

_launchctl_load() { #{{{
  ## Loop over files in local directory that are .plist files
  ## Then link those files to ~/Library/LaunchAgents/
  ## And enable them with launchctl load ~/Library/LaunchAgents/$file
  for file in "$LAUNCH_AGENTS_SOURCE"/*.plist; do
    filename=$(basename "$file")
    ln -sfv "$file" "$HOME/Library/LaunchAgents/$filename"
    launchctl load "$HOME/Library/LaunchAgents/$filename"
  done
}
#}}}: _launchtl_load

_launchctl_unload() { #{{{
  ## If script is run as `load.sh -u`, we only unload all *.plist if the exist
  if [[ "$1" == "-u" ]]; then
    for file in "$LAUNCH_AGENTS_SOURCE"/*.plist; do
      filename=$(basename "$file")
      if [[ -f "$HOME/Library/LaunchAgents/$filename" ]]; then
        launchctl unload "$HOME/Library/LaunchAgents/$filename"
        rm -fv "$HOME/Library/LaunchAgents/$filename"
      fi
    done
    exit 0
  fi
}
#}}}: _launchctl_unload

main() { #{{{
  _launchctl_unload "$@"

  stow -v -t "$HOME" .
  _launchctl_load
}
#}}}: main

if ! _command_installed "brew"; then
  _install_brew
fi

if ! _command_installed "stow"; then
  brew install stow
fi

main "$@"
