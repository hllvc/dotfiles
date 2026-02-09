#!/usr/bin/env bash

current_session=$(tmux display-message -p '#S')

target_session=$(tmux list-sessions -F '#S' | grep -v "^${current_session}$" | fzf --prompt="Move window to session: ")

[[ -z "$target_session" ]] && exit 0

tmux move-window -t "$target_session:"
