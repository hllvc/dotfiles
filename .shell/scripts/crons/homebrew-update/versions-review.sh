#!/usr/bin/env bash
# Opens a Claude Code planning session on version drift: a new "versions"
# window in the personal tmux server, in the dotfiles repo, started in plan
# mode with versions-review.md as the prompt. Then brings Ghostty forward.
#
#   versions-review.sh <repo-root>

set -u

# shellcheck source=../_lib/notify.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../_lib/notify.sh"

readonly REPO_ROOT="$1"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SOCKET=personal
# launchd's PATH has no ~/.local/bin, where claude lives.
readonly CLAUDE="$HOME/.local/bin/claude"
# Same socket dir the tmux-warmup launch agents start the servers with.
export TMUX_TMPDIR="$HOME/.tmux/sockets"

if ! tmux -L "$SOCKET" has-session 2>/dev/null; then
  _notify_sticky \
    "Dotfiles: versions review" \
    "The ${SOCKET} tmux server isn't running. Run ./dotctl versions in ${REPO_ROOT}."
  exit 1
fi

prompt=$(cat "$SCRIPT_DIR/versions-review.md")

# Open the window in the session a client is looking at, so it shows up at
# once; with no client attached, tmux picks the most recent session.
session=$(tmux -L "$SOCKET" list-clients -F '#{client_session}' 2>/dev/null | head -n 1)
if [[ -n "$session" ]]; then
  tmux -L "$SOCKET" new-window -t "${session}:" -n versions -c "$REPO_ROOT" \
    "$CLAUDE" --permission-mode plan "$prompt"
else
  tmux -L "$SOCKET" new-window -n versions -c "$REPO_ROOT" \
    "$CLAUDE" --permission-mode plan "$prompt"
fi

open -a Ghostty
