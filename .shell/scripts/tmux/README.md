# tmux

Tmux helper scripts.

[Back to scripts](../)

## Scripts

| Script | Description |
|--------|-------------|
| `new-session.sh` | Creates a new tmux session with optional gbare repo setup and automatic window creation |
| `move-window.sh` | Moves the current tmux window to another session selected via fzf |
| `prune-review.sh` | Reviews stale sessions in an fzf multi-select and kills the ones you mark |
| `todo-popup.sh` | Opens the todo file of the pane's repo (nvim, lua/todo) in a popup; `q` or `M-t` closes it |
| `replace-pane.sh` | Replaces the current pane with a fresh login shell in place, keeping cwd, title and exported env, and relaunching editors/claude |
