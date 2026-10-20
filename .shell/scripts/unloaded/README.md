# unloaded

Scripts that `.zshrc` does not alias or source (only executables directly in [`scripts/`](../) and [`scripts/init/`](../init/) get an alias). Most are archived; check before moving one, because a few are referenced by path.

[Back to scripts](../)

## In use

| Script | Description |
|--------|-------------|
| `git-askpass.sh` | Git credential helper for HTTPS remotes: answers the username prompt with `x-access-token` and the password prompt with the StackGuardian token read from 1Password (`op read`). **In use**: `.shell/profile` exports `GIT_ASKPASS` pointing at this path, so moving it breaks HTTPS git auth |
| `mason-link.sh` | Symlinks every Neovim Mason binary into `~/.local/bin/` (run by hand; see the root README) |

## Archived

| Script | Description |
|--------|-------------|
| `check-events.scpt` | AppleScript that checks for upcoming Calendar events |
| `gsw.sh` | Google Cloud configuration switcher |
| `hs.sh` | Selects a command from shell history via fzf and copies it to clipboard |
| `j.sh` | Jira workflow manager for sprint tasks, backlog, and git worktree integration |
| `jtime.sh` | Calculates total time logged in Jira across sprint issues for a given month |
| `kgets.sh` | Extracts Kubernetes secrets and ConfigMaps to a temporary `.env` file |
| `kk.sh` | Interactive kubectl context and namespace selector with k9s launcher |
| `ks.sh` | Interactive Kubernetes secret viewer with decoding and clipboard export |
| `logp.sh` | Interactive Kubernetes pod log viewer with filtering and error highlighting |
| `makepdf.sh` | Converts markdown to PDF using pandoc with XeLaTeX engine |
| `mdpdf.sh` | Creates a markdown template with YAML frontmatter for PDF conversion |
| `multi-jira.sh` | Multi-project Jira workflow manager that swaps config files per project |
| `nq_res.sh` | Tests network downlink speed against a target threshold |
| `swpr.sh` | GitHub PR switcher for switching to PR branches with worktree management |
