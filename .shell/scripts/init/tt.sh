#!/usr/bin/env bash

export TMUX_TMPDIR="${HOME}/.tmux/sockets"

socket="$1"

# if [[ -z "$socket" ]]; then
#   exit
# fi

_get_sockets() { #{{{
  find "$TMUX_TMPDIR/tmux-501" \
    -type s \
    -exec basename {} \;
}
#}}}: _get_sockets

_select_socket() { #{{{
  printf "%s\n" "$(cat)" | fzf
}
#}}}: _select_socket

if [[ -z "$socket" ]]; then
  mapfile socket_list < <(_get_sockets)
  if ((${#socket_list} > 0)); then
    socket="$(printf "%s%s" "${socket_list[@]}" "no_tmux" | _select_socket)"
  else
    exit
  fi
fi
readonly socket

if [[ -z "$socket" ]]; then
  exit 0
elif [[ "$socket" == "no_tmux" ]]; then
  /Users/hllvc/.shell/scripts/gt.sh "no_tmux"
  exit 0
fi

if [[ -n "$TMUX" ]]; then
  tmux detach
fi

if tmux -L "$socket" has-session &>/dev/null; then
  if (( $# > 1 )); then
    shift
    # We use $* explicity like this to expand other parameters to command
    # shellcheck disable=SC2048,SC2086
    tmux -L "$socket" $*
  else
    tmux -L "$socket" at
  fi
else
  tmux -L "$socket" start-server
  if tmux -L "$socket" has-session &>/dev/null; then
    tmux -L "$socket" at
  else
    tmux -L "$socket"
  fi
fi
