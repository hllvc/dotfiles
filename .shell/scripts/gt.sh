#!/usr/bin/env bash

# export TMUX_TMPDIR="${HOME}/.tmux/sockets"

readonly socket="$1"

if [[ "$socket" != "no_tmux" ]]; then
  exit
fi

open -na Ghostty.app --args \
  --config-default-files=false \
  --config-file="$HOME"/.config/ghostty/no-tmux/init.conf
