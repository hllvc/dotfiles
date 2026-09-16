# .shell

Shell configuration files sourced by `.zshrc`.

[Back to root](../)

## Configuration Files

| File | Description |
|------|-------------|
| `aliases` | Shell aliases for directory navigation, git, kubectl, permissions, and editors |
| `profile` | Environment variables, PATH, history settings, FZF config, and tool configurations |
| `zshinit` | Oh-My-Zsh setup, Powerlevel10k theme, plugins, and Zsh behavior settings |
| `tmux-pane-env` | Snapshots each tmux pane's exported env per prompt, and re-applies it (never overwriting) after a pane replace |

## Completions

Zsh completion functions in [`completions/`](completions/), added to `fpath` by `.zshrc` (run `rm -f ~/.zcompdump*` once after adding a file so compinit picks it up).

| File | Description |
|------|-------------|
| `_sw` | Completes `sw` flags, subcommands (`st`, `carry ls|apply|diff|reset|edit`), branch names and carried file paths |
| `_dotctl` | Completes `dotctl` commands, subcommands, flags, and launch-agent names (short or full label) for `agents load|unload|list` |

## Scripts

Custom scripts located in [`scripts/`](scripts/).
