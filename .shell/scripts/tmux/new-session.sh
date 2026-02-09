#!/usr/bin/env zsh

# Select session directory from ~/.git
dir=$(find ~/.git -maxdepth 1 -mindepth 1 -type d | fzf --prompt="Working directory: ")
[[ -z "$dir" ]] && exit 0

# Prompt for session name
printf "Session name: "
read -r name
[[ -z "$name" ]] && exit 0

# Create session with window 0 "default"
tmux new-session -d -s "$name" -c "$dir" -n "default"

# Show subdirectories + gbare option
subdir=$( (echo "[gbare]"; find "$dir" -maxdepth 1 -mindepth 1 -type d) | fzf --prompt="Window 1 (optional): ")

if [[ -n "$subdir" ]]; then
  if [[ "$subdir" == "[gbare]" ]]; then
    # Run gbare inside session directory, capture output path
    window_dir=$(cd "$dir" && ~/.shell/scripts/functions/gbare.sh)
    window_name=$(basename "$(dirname "$window_dir")")
  else
    window_dir="$subdir"
    window_name=$(basename "$subdir")
  fi

  if [[ -n "$window_dir" && -d "$window_dir" ]]; then
    tmux new-window -t "$name":1 -n "$window_name" -c "$window_dir"
  fi
fi

tmux switch-client -t "$name"
