# Dotfiles

Personal dotfiles managed with GNU Stow.

## Quick Start

> [!CAUTION]
> This will install dotfiles to `$HOME`.

Using `git worktree`:

```bash
git clone --bare \
    "git@github.com:hllvc/dotfiles.git" \
    "dotfiles/.bare" && cd "dotfiles" \
    && echo "gitdir: ./.bare" > .git \
    && printf "\tfetch = +refs/heads/*:refs/remotes/origin/*" >> .bare/config \
    && git worktree add "$(git branch --show-current)" \
    && ./dotctl all
```

Without `git worktree`, normal:

```bash
git clone "git@github.com:hllvc/dotfiles.git" \
    && cd "dotfiles" \
    && ./dotctl all
```

### dotctl Commands

- `./dotctl` - Show help (running without a command only prints it)
- `./dotctl all` - Stow + load launch agents + install crons + apply macOS defaults + re-pin brew formulae (`versions pins`)
- `./dotctl stow [--adopt]` - Symlink dotfiles into `$HOME` (adopt folds existing files into the repo), then link Homebrew-shipped Claude skills (see [Cask-shipped skills](#cask-shipped-skills))
- `./dotctl agents <load|unload|disable|enable|list> [name...]` - Manage launch agents under `~/.config/launch-agents` (symlinked into `~/Library/LaunchAgents` on load); a name is the full label, the plist filename or the short suffix (`tmux-autosave`), all agents when omitted. `disable` unloads and keeps an agent off across `load`, `all` and reboots (the plist stays); `enable` undoes it
- `./dotctl crons <install|list>` - Run per-cron `install.sh` hooks under `.shell/scripts/crons/*/`
- `./dotctl macos <apply>` - Apply macOS `defaults write` tweaks (Finder, Dock, trackpad, Safari, Mail, …)
- `./dotctl doctor` - Audit launch-agent plists and scripts for worktree-pinned or missing absolute paths
- `./dotctl orphans [--fix]` - Report dangling symlinks left in `$HOME` by renamed or removed repo files: REPO (ours; `--fix` deletes them and any parent dirs left empty), FOREIGN (broken, pointing elsewhere; listed only) and STALE (resolves to a repo path git no longer tracks; listed only)
- `./dotctl versions [status|review|accept|upgrade|pins|auto|accepted]` - Compare installed tool versions with the ones the config was checked against, triage updates (`status --brief|--issues`, `accept --all|--triaged`, `auto -n`, `accepted --days N`; see [Tool Versions](#tool-versions))
- `./dotctl -h` (or `./dotctl <command> -h`) - Help

Zsh tab completion for all of the above ships in `.shell/completions/_dotctl` and is picked up via `fpath` once stowed.

## Prerequisites

macOS only: LaunchAgents, `defaults`, `pbcopy`, Ghostty and 1Password are assumed throughout.

- [Homebrew](https://brew.sh) (auto-installed by `dotctl`, via Homebrew's install script from the web)
- [GNU Stow](https://www.gnu.org/software/stow/) (auto-installed by `dotctl`)
- Zsh with [Oh-My-Zsh](https://ohmyz.sh), the [Powerlevel10k](https://github.com/romkatv/powerlevel10k) theme, and the plugins `.shell/zshinit` and `.zshrc` load from `~/.oh-my-zsh/custom` (zsh-autosuggestions, zsh-defer, zsh-vi-mode, fast-syntax-highlighting)
- Tools the config calls: `tmux`, `fzf`, `jq`, `gh`, `nvim`, `git-lfs` (required by `.gitconfig`), Ghostty, the Claude Code CLI (`~/.local/bin/claude`), and 1Password with its `op` CLI (commit signing, secrets). `alerter` and `sleepwatcher` are installed by the cron `install.sh` hooks.
- [tpm](https://github.com/tmux-plugins/tpm), not installed by `dotctl`: `git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm`, then `prefix + I` in tmux to fetch the plugins `.tmux.conf` lists (extrakto, tmux-fzf-url, tmux-suspend, the resurrect/continuum forks)
- Optional: kubectl, kubectx and k9s for the Kubernetes aliases

## Structure

```
.
├── .config/            # Application configs
│   ├── nvim/           # Neovim (Lua + lazy.nvim)
│   ├── ghostty/        # Ghostty terminal (no-tmux/ holds a variant with its own keybinds)
│   ├── karabiner/      # Keyboard remapping
│   ├── launch-agents/  # macOS LaunchAgents
│   ├── gh/             # GitHub CLI config (ssh protocol, aliases)
│   └── 1Password/      # SSH agent config
├── .shell/             # Shell configuration
│   ├── profile         # Environment variables, PATH
│   ├── aliases         # Shell aliases
│   ├── functions       # Small zsh helpers (cpg, mvg, take, ...)
│   ├── zshinit         # Zsh plugins/theme setup
│   ├── tmux-pane-env   # Per-pane env snapshot, re-applied after a pane replace
│   ├── completions/    # Zsh completions (dotctl, sw, tofu, ...)
│   └── scripts/        # Custom scripts
│       ├── brewup.sh   # Manual Homebrew upgrade (alias: brewup)
│       ├── functions/  # Scripts that can cd (gbare.sh, sw.sh)
│       ├── lib/        # Shared helpers (worktree.sh, brew-upgrade.sh)
│       ├── init/       # Startup scripts (tt.sh)
│       ├── tmux/       # Tmux helper scripts
│       ├── crons/      # Scheduled jobs (installed by `dotctl crons install`)
│       ├── macos/      # macOS `defaults write` tweaks (`dotctl macos apply`)
│       └── unloaded/   # Not aliased: archived scripts, plus git-askpass.sh, which is in use
├── .claude/            # Claude Code CLI
│   ├── CLAUDE.md       # Global instructions (AGENTS.md links to it)
│   ├── settings.json   # Settings, permissions, plugins, status line
│   ├── statusline-command.sh  # Status line script
│   └── skills/         # Custom skills
├── .codex/             # Codex CLI config
├── .agents/            # Shared agent skills dir (links to .claude/skills)
├── .zshrc              # Main Zsh config
├── .tmux.conf          # Tmux config
├── .gitconfig          # Git config
├── .p10k.zsh           # Powerlevel10k theme
├── .tofurc, .terraformrc  # OpenTofu / Terraform CLI config (shared plugin cache)
├── .sleep              # sleepwatcher hook (saves tmux sessions before sleep)
├── .versions           # Tested tool versions (see Tool Versions; not stowed)
├── .stow-local-ignore  # What stow skips
└── dotctl              # Dotfiles CLI (stow, agents, crons, macos, doctor, orphans, versions)
```

See detailed documentation: [`.config/`](.config/) | [`.shell/`](.shell/)

## Features

### Git Worktree Workflow

- **gbare.sh** - Set up a bare repository with GitHub integration
- **sw.sh** - Smart branch switching with worktree support

### Tmux Multi-Socket

Separate tmux sockets for work/personal contexts:

- `personal` - Personal projects
- `work` - Work projects

LaunchAgents auto-start these on login (`com.hllvc.personal.tmux`, `com.hllvc.work.tmux`). `tt.sh` attaches to one (Ghostty runs it at startup); `ttl` lists sessions. The `updates` session on the `personal` socket holds the drafted update plans (see [Tool Versions](#tool-versions)).

Session state is preserved across reboots via `tmux-resurrect` (forks: `hllvc/tmux-resurrect`, `hllvc/tmux-continuum`). The in-tmux auto-save is disabled (`@continuum-save-interval 0`) to avoid pty hitches; saving is handled externally:

- **Idle / periodic** — `com.hllvc.tmux-autosave` fires every 30 min, saves when HID idle ≥ 30 s (force-saves after 90 min)
- **Sleep / hibernate** — `sleepwatcher` runs `~/.sleep` before the system sleeps
- **Shutdown / reboot** — `com.hllvc.tmux-shutdown-save` daemon catches `SIGTERM` from launchd during shutdown

On restore (`@continuum-restore on`, `@continuum-multiple-sockets on` so each socket keeps its own save), pane contents are captured and only `vi`, `vim`, `view`, `nvim` and `claude` come back running (`claude --continue` when it was started bare, the exact `--resume` otherwise); every other pane restores as a plain shell. Detached sessions untouched for 7+ days count as stale and are offered for pruning with `prefix K` (`tprune` from a shell).

#### Keys and settings (`.tmux.conf`)

The prefix is `C-f` (`C-b` still works). Ghostty's `no-tmux/` profile mirrors the prefix for the same split keys.

| Key (after prefix) | Action |
|--------------------|--------|
| `t` / `C-t` | Popup: a shell / the repo's todo file (`todo-popup.sh`) |
| `T` / `Z` / `O` | Popup: edit `.tmux.conf` / `.zshrc` / `~/.ssh/config` in nvim |
| `C-e` | Popup: scratch nvim buffer (`nvim +enew -`) |
| `N` / `W` | Popup: new session / move the window to another session (fzf) |
| `K` | Popup: review stale sessions to kill; says so if there are none |
| `o` | New window running `hop` (ssh host picker) |
| `C-v` / `C-s` | Split right / down, keeping the directory (`"` is unbound) |
| `C-z` / `C-r` | Zoom the pane / replace it with a fresh shell, keeping cwd, title and env |
| `C-h` `C-j` `C-k` `C-l` | Resize (repeatable) |
| `r` / `Q` | Reload `.tmux.conf` / kill the server |
| `a` / `u` | extrakto (grab text from the window) / tmux-fzf-url |
| `S` / `R` | Save / restore sessions (resurrect) |
| `F2` (no prefix) | tmux-suspend: pass every key to the inner tmux or program |
| `M-h/j/k/l`, `M-\` (no prefix) | Move between panes; passed through to nvim when it's the foreground command |

Other settings: vi copy mode (`v`, `C-v`, `y` copies with `pbcopy`), mouse on, no escape delay, 50,000 lines of history, extended keys (CSI u), passthrough on, windows not renamed automatically, panes numbered from 1. The status line shows the socket name, plus a yellow `tmux X ≠ Y` when the server isn't the tested version (see [Tool Versions](#tool-versions)).

**Dark theme pinned.** tmux 3.8 colors popups, menus and modes from a light or dark theme it detects from the terminal. Ghostty reports light even though it runs a dark theme, which gave gray popups, so `.tmux.conf` sets `set -gq theme dark`.

### Background Crons

Scheduled user-level jobs live under `.shell/scripts/crons/<name>/` and are installed via `dotctl crons install`. Each cron is free to define its own `install.sh` (e.g. for system-level hooks like `newsyslog.d` configs) — `dotctl` auto-discovers and runs them.

> **Path convention:** launchd does no variable expansion, so plists must carry an
> absolute path — always the stowed `~/.shell/...` location, never
> `.repos/private/dotfiles/<worktree>/...`. A plist pinned to a worktree dies
> silently (launchd exit 78) the moment that worktree is renamed. Scripts use
> `$HOME/.shell/...`. `dotctl doctor` enforces both.

- **homebrew-update** — daily at 10:00; skips on battery or offline; runs the same sequence as `brewup` (`.shell/scripts/lib/brew-upgrade.sh`: `brew update`, `dotctl versions pins` + `auto`, `upgrade`, greedy cask `upgrade`, `autoremove`, `cleanup`, then re-points cask-shipped Claude skills at the new version via `link-skills.sh`), without the triage; notifies on failure (LaunchAgent: `com.hllvc.homebrew-update`).
- **memory-pressure** — samples `memory_pressure` every 5 min, logs to `~/Library/Logs/com.hllvc.memory-pressure.log`, fires a macOS alert when free memory drops below 40% (LaunchAgent: `com.hllvc.memory-pressure`).
- **versions-review**: daily at 10:30; skips on battery or offline; triages tool updates and drafts plans (see [Tool Versions](#tool-versions)) (LaunchAgent: `com.hllvc.versions-review`).
- **wifi-watchdog** — every 30 s and on network change; recovers the ISP router's silent 5 GHz stream collapse on the `hllvc` network by bouncing the Wi-Fi radio (details and safeguards in [`crons/README.md`](.shell/scripts/crons/README.md); LaunchAgent: `com.hllvc.wifi-watchdog`).
- **tmux-autosave** — idle-gated tmux session saver; fires every 30 min, saves when idle ≥ 30 s or 90 min has elapsed; also triggered on sleep (`~/.sleep` via `sleepwatcher`) and shutdown (`SIGTERM` trap via `com.hllvc.tmux-shutdown-save`). Replaces `@continuum-save-interval` (LaunchAgents: `com.hllvc.tmux-autosave`, `com.hllvc.tmux-shutdown-save`, `com.hllvc.sleepwatcher`).
- **tmux-warmup** — pre-starts the `work` and `personal` tmux servers at login so `tmux-continuum` auto-restore runs before first attach (LaunchAgents: `com.hllvc.personal.tmux`, `com.hllvc.work.tmux`).

### Tool Versions

`.versions` (repo root, not stowed) records the version of each tool the config was last checked against: tmux, Neovim, fzf, Ghostty, Claude Code, macOS, the Neovim plugin lockfile, and the oh-my-zsh, Powerlevel10k, zsh-vi-mode, fast-syntax-highlighting and tmux-resurrect/continuum checkouts. Upgrades change defaults without asking (tmux 3.8 turned popups gray through its new theme colors), so drift from that version is the cue to read the tool's changes and adjust the config.

- `./dotctl versions`: tested vs installed per tool, the triage state, and where to read the changes.
- `./dotctl versions accept <tool>`: record the installed version and sync the in-file copies (`.tmux.conf` `@target_version`, nvim `init.lua` and README).
- **Brew pins**: tmux, neovim and fzf are `brew pin`ned. The `pin` column sets what the homebrew-update cron may still apply on its own (`patch`, `minor`, or nothing with `exact`); bigger upgrades are held until `./dotctl versions upgrade <tool>`. `brewup` applies these levels on manual upgrades (a plain `brew upgrade` just skips pinned formulae). `./dotctl versions pins` (also run by `dotctl all`) makes brew match the column.
- **Daily review** (`com.hllvc.versions-review`, 10:30, `.shell/scripts/crons/versions-review/`): for each `review=auto`/`strict` tool that drifted or has a held upgrade, Claude Haiku classifies every change in the range twice (kind: fix/docs/internal/performance/feature/default-change/removal/deprecation, and whether the config uses that area), with read-only tools, capped by budget and time. A fixed rule in `review.sh` decides: no config impact only if **both** runs read the full range and every change is a fix/docs/internal/performance change or a feature in an area the config doesn't use. Any default change, removal or deprecation, a feature in a used area, or the runs disagreeing means review.
  - *No config impact*: `.versions` is bumped and committed (`fix: versions — <tool> <version>, no config impact`), silently. If that's blocked (not on `main`, uncommitted edits in those files, signing failed), you get one quiet note, the next run retries, and `./dotctl versions accept --triaged` does it by hand.
  - *Needs review or unsure*: Claude Opus drafts a plan in a session that waits in a window of the `updates` tmux session (personal socket), named `<tool> <from>→<to>`, and a "Plan ready" notification opens it. Accepting the tool closes the window (unless you accept from inside it; then it closes when Claude exits).
  - A held upgrade with no impact gets a "safe to upgrade" note; it is never upgraded automatically.
  - `review=strict` tools (tmux, Neovim) are triaged but always get a drafted plan, never a silent accept.
  - `review=manual` tools (claude-code, macOS) are tracked but only reviewed when you run `./dotctl versions review <tool>`.
  - Silent accepts of the last 14 days are listed under `./dotctl versions` and at the end of `brewup`, with each commit's hash and reason (`./dotctl versions accepted [--days N]`); to reopen a wrong call, `git revert <commit>` and then `./dotctl versions review <tool>`.
- **In-tool warnings**: tmux shows `tmux X ≠ Y` in yellow on the status line while the running server differs from `@target_version`; Neovim warns at startup (`vim.g.nvim_target_version`).

### Key Scripts

Every executable at the top of `.shell/scripts/` is aliased by its name (`hop.sh` → `hop`); the full list is in [`.shell/scripts/README.md`](.shell/scripts/README.md). The ones used daily:

- **brewup.sh** - The manual Homebrew upgrade: `brew update`, brew pins and pin-level upgrades (`dotctl versions pins`/`auto`), formulae, greedy casks, `autoremove` + `cleanup -s`, cask-shipped skill links, then a report of tools off their tested version and an immediate triage (see [Tool Versions](#tool-versions)). The sequence is `lib/brew-upgrade.sh`, shared with the homebrew-update cron. `brewup -n` previews.
- **com.sh** - Git commit with branch prefix extraction
- **tt.sh** - Tmux socket selector with fzf
- **sw.sh**, **gbare.sh** - Worktree switching and bare clones (see above)

Scripts in `.shell/scripts/unloaded/` aren't aliased (`j.sh`, the Jira helper, is one). `git-askpass.sh` there is still in use: `.shell/profile` points `GIT_ASKPASS` at it.

### Neovim

Lua-based config with lazy.nvim, the native LSP client, nvim-cmp, Telescope, Treesitter, Copilot and claudecode.nvim, format on save for changed lines only, GitHub Actions helpers, and a todo workflow. It pins the Neovim version it targets and warns at startup when it drifts. See [`.config/nvim/README.md`](.config/nvim/README.md) and [`KEYMAPS.md`](.config/nvim/KEYMAPS.md) for the details and every keymap.

### Claude Code

`.claude/settings.json` holds the settings: auto permission mode, a deny list for credential paths (`~/.ssh`, `~/.aws`, ...), and a guard that always asks before a command selects a production AWS profile: a `PreToolUse` hook (`.shell/scripts/claude-hooks/aws-profile-guard.sh`) treats every `sg-prod*` profile except `sg-prod-ro` as production, however it's spelled (`--profile x`, `--profile=x`, quoted, `AWS_PROFILE=x`), and also asks when the profile is only known at run time; `default`, `dash` and `sg-prod-ro` aren't asked about. It fails closed (`onFailure: block`), and its text `ask` rules and the auto-mode classifier rules in `settings.json` are extra layers. `aws-profile-guard.test.sh` replays `aws-profile-guard.cases`. It only sees the command text, so a Makefile or script that picks the profile itself isn't caught, the enabled plugins (LSP plugins for Lua, Python, TypeScript, Go and Swift, `frontend-design`, `terminal-browser`, `cache-tax`), three plugin marketplaces, and the status line (`.claude/statusline-command.sh`, which needs `jq`). `.claude/CLAUDE.md` is the global instruction file and `AGENTS.md` links to it, so Codex reads the same one; `.codex/config.toml` is Codex's config. `.claude/skills/` holds the custom skills (sg-* and sikarugir-legendary); six of them (`sg-create-*`, `sg-update-workflow`, `sg-upgrade-workflow`, `sg-manage-secrets`) are written by the StackGuardian org sync through `~/.agents/skills`, so they are in `.gitignore` and `.stow-local-ignore`.

`settings.json` sets `BASH_ENV` to `~/.local/bin/claude-shims-init.sh` (`.codex/config.toml` does too). That file isn't in this repo; without it, shells Claude starts have no shims.

The LSP plugins reuse Neovim's Mason-managed binaries.
Mason installs to `~/.local/share/nvim/mason/bin/`, which isn't in PATH by default.
`mason-link.sh` symlinks all Mason binaries into `~/.local/bin/`:

```bash
~/.shell/scripts/unloaded/mason-link.sh
```

#### Cask-shipped skills

Some casks ship their own Claude skill (currently `terminal-browser`). Its path
is version-pinned (`/opt/homebrew/Caskroom/<cask>/<version>/...`) and `brew
cleanup` deletes the old version, so the link is **not** tracked here. Stow
also refuses absolute symlinks and aborts the whole run if it finds one.
Instead, `.shell/scripts/crons/homebrew-update/link-skills.sh` resolves the
current version through the cask's stable `/opt/homebrew/bin/<bin>` link and
(re)creates `~/.claude/skills/<skill>`. It runs after `dotctl stow` and after
every homebrew-update run. To add another cask, add an entry to its `SKILLS` array.

`terminal-browser` also links its skill on its own (on the first command after
a version change), including into `~/.agents/skills`. That path points at this
repo's `.claude/skills`, so the link lands in the working tree. It's listed in
both `.gitignore` and `.stow-local-ignore`: keep both entries, or the next
`dotctl stow` aborts again.

#### MCP servers — off by default, on per session

`allowedMcpServers: []` blocks every MCP server (user-added, plugin, and
claude.ai connectors). Allowlist entries merge across settings sources, so a
single session can opt servers back in without touching `settings.json`:

```bash
# claude.ai connectors match by URL (their names contain spaces/dots,
# which serverName entries don't accept)
claude --settings '{"allowedMcpServers":[{"serverUrl":"https://mcp.notion.com/*"}]}'

# user-added servers match by name
claude --settings '{"allowedMcpServers":[{"serverName":"testapi"}]}'
```

`cmcp` (`.shell/scripts/cmcp.sh`) wraps this: `cmcp notion slack` opens a session
with just those, `cmcp -c figma` checks what would load, `cmcp -l` lists aliases.
`claude mcp list` accepts the same `--settings` flag to check what would load.
Connector URLs: Notion `mcp.notion.com`, Slack `mcp.slack.com`, Fathom
`api.fathom.ai`, PostHog `mcp.posthog.com`, Figma `mcp.figma.com`, Excalidraw
`mcp.excalidraw.com`, Claude Docs `api.anthropic.com/v1/pages`.

Don't re-add `disableClaudeAiConnectors: true` — any source setting it to
`true` wins, so no per-session flag can turn connectors back on.

#### Potential features

- **Ticket links in the footer** — `footerLinksRegexes` can turn `SG-####` IDs
  in output into clickable badges. Tickets live in Notion; needs the Notion
  database/page URL shape for a ticket ID before it can be wired up.

## Git Config

Commits and tags are signed with the SSH key in `user.signingkey` through 1Password's `op-ssh-sign`; `core.sshCommand` pins `~/.ssh/git_keys/personal_git.pub` for SSH remotes, and `~/.config/1Password/ssh/agent.toml` limits the 1Password SSH agent to the `SSH Keys` vault. Pulls rebase and fast-forward only, merges never fast-forward, push sets the upstream automatically, fetch prunes, and the default branch is `develop`. Git LFS is required (the `lfs` filter has `required = true`, so `git-lfs` must be installed). For HTTPS, `credential.helper store` applies, with `gh auth git-credential` for github.com and gist.github.com; a username/password prompt that still comes up is answered by `GIT_ASKPASS` (set in `.shell/profile`) with the StackGuardian token from 1Password.

Conditional include for work repositories:

- `~/.repos/stackguardian/.gitconfig` - Included for repos under `~/.repos/stackguardian/`
