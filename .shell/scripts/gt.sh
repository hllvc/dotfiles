#!/usr/bin/env bash

# export TMUX_TMPDIR="${HOME}/.tmux/sockets"

readonly socket="$1"

if [[ -z "$socket" ]]; then
  exit
fi

# _get_sockets() { #{{{
#   find "$TMUX_TMPDIR/tmux-501" \
#     -type s \
#     -exec basename {} \;
# }
# #}}}: _get_sockets
#
# _select_socket() { #{{{
#   printf "%s\n" "$(cat)" | fzf
# }
# #}}}: _select_socket
#
# if [[ -z "$socket" ]]; then
#   mapfile socket_list < <(_get_sockets)
#   if ((${#socket_list[@]} > 0)); then
#     socket="$(printf "%s%s" "${socket_list[@]}" "no_tmux" | _select_socket)"
#     if [[ -z "$socket" ]]; then
#       exit
#     fi
#   else
#     exit
#   fi
# else
#   exit
# fi

# open -na Ghostty.app --args \
#   --title="${socket^}" \
#   -e "/Users/hllvc/.shell/scripts/init/tt.sh ${socket,,}"

if [[ "$socket" == "no_tmux" ]]; then
  open -na Ghostty.app --args \
    --config-default-files=false \
    --config-file="$HOME"/.config/ghostty/no-tmux/init.conf
else
  open -na Ghostty.app --args \
    --config-default-files=false \
    --config-file="$HOME"/.config/ghostty/on-new-window.conf \
    --title="${socket^}" \
    --shell-integration=detect \
    -e /Users/hllvc/.shell/scripts/init/tt.sh "${socket,,}"
fi
