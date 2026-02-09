# .shell

Shell configuration files sourced by `.zshrc`.

[Back to root](../)

## Configuration Files

| File | Description |
|------|-------------|
| `aliases` | Shell aliases for directory navigation, git, kubectl, permissions, and editors |
| `profile` | Environment variables, PATH, history settings, FZF config, and tool configurations |
| `zshinit` | Oh-My-Zsh setup, Powerlevel10k theme, plugins, and Zsh behavior settings |

## Scripts

Custom scripts located in `scripts/`.

### Subdirectories

| Directory | Description |
|-----------|-------------|
| [`functions/`](scripts/functions/) | Scripts sourced as shell functions (can `cd`) |
| [`init/`](scripts/init/) | Startup and initialization scripts |
| [`tmux/`](scripts/tmux/) | Tmux helper scripts |
| [`unloaded/`](scripts/unloaded/) | Inactive/archived scripts |

### Top-Level Scripts

| Script | Description |
|--------|-------------|
| `com.sh` | Git commit helper with conventional commit prefixes and branch ticket references |
| `gsw.sh` | Google Cloud configuration switcher |
| `gt.sh` | Opens Ghostty terminal windows with specified tmux socket configurations |
| `hexrand.sh` | Generates random hex strings and copies to clipboard |
| `j.sh` | Jira workflow manager for sprint tasks, backlog, and git worktree integration |
| `jtime.sh` | Calculates total time logged in Jira across sprint issues for a given month |
| `kk.sh` | Interactive kubectl context and namespace selector with k9s launcher |
| `ks.sh` | Interactive Kubernetes secret viewer with decoding and clipboard export |
| `mksh.sh` | Creates a new shell script with shebang, makes it executable, and opens in nvim |
| `nq_res.sh` | Tests network downlink speed against a target threshold |
| `ss.sh` | Interactive SSH host selector using fzf |
| `tmsg.sh` | Sends messages to a Telegram channel via bot API |
| `check-events.scpt` | AppleScript that checks for upcoming Calendar events |

### Data

| File | Description |
|------|-------------|
| `.data` | Data file used by scripts |
