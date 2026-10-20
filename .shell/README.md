# .shell

Shell configuration files sourced by `.zshrc`.

[Back to root](../)

## Configuration Files

| File | Description |
|------|-------------|
| `aliases` | Shell aliases for directory navigation, git, kubectl, terraform, tmux (`ttl`, `tprune`, `treplace`), permissions, and editors. Scripts at the top of `scripts/` get their aliases from `.zshrc`, not from here |
| `profile` | Environment variables, PATH, history settings, FZF config, and tool configurations: the Terraform plugin cache, `GIT_ASKPASS` (points at `scripts/unloaded/git-askpass.sh`), and the Telegram bot token as an `op://` 1Password reference, not the token itself |
| `functions` | Small zsh helpers: `cpg` / `mvg` (copy or move, then `cd` into a directory target), `take` (mkdir and cd), `copy` / `cpaste` / `lscopy` / `cclean` (a `/tmp/copy` staging clipboard for files), `bup` (copy to `<name>.old`, then offer to delete the original), `res` (copy a file to its name minus the last extension), `vi` (nvim, or `cd` into a directory and open it; remembers the old directory in `~/.curr`), `bundle_id` (fzf-pick an app, copy its bundle id) |
| `zshinit` | Oh-My-Zsh setup, Powerlevel10k theme, plugins, and Zsh behavior settings |
| `tmux-pane-env` | Snapshots each tmux pane's exported env per prompt, and re-applies it (never overwriting) after a pane replace |

## Completions

Zsh completion functions in [`completions/`](completions/), put first on `fpath` by `.zshrc` so they override same-command completers from Homebrew or zsh (run `rm -f ~/.zcompdump*` once after adding a file so compinit picks it up).

| File | Description |
|------|-------------|
| `_sw` | Completes `sw` flags, subcommands (`st`, `carry ls|apply|diff|reset|edit`), branch names and carried file paths |
| `_dotctl` | Completes `dotctl` commands, subcommands, flags, and launch-agent names (short or full label) for `agents load|unload|list` |
| `_tofu` | Completes `tofu` and `terraform` (overriding Homebrew's `_terraform`): subcommands by asking the binary itself, and subcommand flags (`plan -<Tab>`) by parsing `<binary> <subcommand> -help` |
| `_com` | Completes `com` type flags (`-feat`, `-fix`, `-docs`), previewing the prefix the current branch would get |
| `_sgc` | Completes `sgc` commands, `--only`, branches for `switch`, commit flags, and git itself for `diff`/`log`/`each`/`backend`/`agent` |
| `_cmcp` | Completes `cmcp` flags, the connector aliases defined in `cmcp.sh`, and MCP servers configured for Claude Code |
| `_hop` | Completes ssh options for `hop` (the host is picked with fzf, so hosts are not offered) |
| `_gbare` | Completes `git@github.com:<owner>/<repo>` for `gbare` from `gh` (owners, then that owner's repos) |

## Scripts

Custom scripts located in [`scripts/`](scripts/).
