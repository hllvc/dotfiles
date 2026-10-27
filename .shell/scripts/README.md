# scripts

Custom shell scripts. `.zshrc` wires them up at shell start:

- every executable at the top level of this directory (and of `init/`) is aliased by its basename without `.sh` (`hop.sh` → `hop`), via `_load_scripts`, so a new script is a command as soon as it is `chmod +x`;
- every executable in `functions/` is sourced as a shell function (they can `cd`), via `_load_functions`;
- scripts in other subdirectories get an explicit alias in [`../aliases`](../aliases) when they have one (`tprune`, `treplace`).

[Back to .shell](../)

## Subdirectories

| Directory | Description |
|-----------|-------------|
| [`functions/`](functions/) | Scripts sourced as shell functions (can `cd`): `sw`, `gbare` |
| [`lib/`](lib/) | Shared helpers, not commands: `worktree.sh` is sourced by `sw`/`gbare`; `brew-upgrade.sh` is run by `brewup` and the homebrew-update cron |
| [`init/`](init/) | Startup and initialization scripts |
| [`claude-hooks/`](claude-hooks/) | Claude Code hooks registered in `.claude/settings.json` (not commands): `aws-profile-guard.sh` asks before any command uses a production AWS profile, with its test cases |
| [`tmux/`](tmux/) | Tmux helper scripts (popups, session and window helpers) |
| [`crons/`](crons/) | Scheduled jobs invoked by LaunchAgents; each has its own `install.sh` picked up by `dotctl crons install` |
| `macos/` | `defaults.sh`: the `defaults write` tweaks applied by `dotctl macos apply` |
| [`unloaded/`](unloaded/) | Scripts that aren't aliased, some archived, one still in use (`git-askpass.sh`) |

## Scripts

| Script | Description |
|--------|-------------|
| `brewup.sh` | The manual Homebrew upgrade (`brewup`): `brew update`, brew pins and pin-level upgrades (`dotctl versions pins`/`auto`), `brew upgrade --greedy` (formulae and every cask), `autoremove` + `cleanup -s`, cask-shipped Claude skill links, then a report of tools off their tested version in `.versions` and an immediate triage of them. `brewup -n` previews without installing. The upgrade sequence itself is `lib/brew-upgrade.sh`, shared with the homebrew-update cron |
| `cmcp.sh` | Starts Claude Code with chosen MCP servers opted in for one session (MCP is off by default): `cmcp notion slack`, `-c` checks via `claude mcp list`, `-l` lists connector aliases, args after `--` go to `claude` |
| `com.sh` | Git commit helper with conventional commit prefixes and branch ticket references |
| `gt.sh` | Opens Ghostty terminal windows with specified tmux socket configurations |
| `hexrand.sh` | Generates random hex strings and copies to clipboard |
| `hop.sh` | Interactive SSH host selector using fzf (was `ss`, which is the Linux socket-statistics command) |
| `newsh.sh` | Creates a new shell script with shebang, makes it executable, and opens in nvim (was `mksh`, which zsh mistook for the MirBSD Korn shell) |
| `sgc.sh` | Drives the `~/.repos/stackguardian/sgcode/` two-repo workspace (landfast-backend + sgcode-agent) as one: `init`, `status`, `switch <branch> [-c]`, `commit`, `push`, `each <git args>`; `--only backend\|agent` scopes to one repo |
| `tmsg.sh` | Sends messages to a Telegram channel via bot API |
