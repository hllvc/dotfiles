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

- `./dotctl` - Show help (running without a command is a no-op)
- `./dotctl all` - Stow + load launch agents + install crons + apply macOS defaults
- `./dotctl stow [--adopt]` - Symlink dotfiles into `$HOME` (adopt folds existing files into the repo), then link Homebrew-shipped Claude skills (see [Cask-shipped skills](#cask-shipped-skills))
- `./dotctl agents <load|unload|list> [name...]` - Manage launch agents under `~/.config/launch-agents`; names are optional (`tmux-autosave` or `com.hllvc.tmux-autosave`), all agents when omitted
- `./dotctl crons <install|list>` - Run per-cron `install.sh` hooks under `.shell/scripts/crons/*/`
- `./dotctl macos <apply>` - Apply macOS `defaults write` tweaks (Finder, Dock, trackpad, Safari, Mail, …)
- `./dotctl doctor` - Audit launch-agent plists and scripts for worktree-pinned or missing absolute paths
- `./dotctl orphans [--fix]` - Report (and with `--fix` delete) dangling symlinks left in `$HOME` by renamed or removed repo files
- `./dotctl versions [status|review|accept|upgrade|pins|auto]` - Compare installed tool versions with the ones the config was checked against, triage updates (see [Tool Versions](#tool-versions))
- `./dotctl -h` (or `./dotctl <command> -h`) - Help

Zsh tab completion for all of the above ships in `.shell/completions/_dotctl` and is picked up via `fpath` once stowed.

## Prerequisites

- [Homebrew](https://brew.sh) (auto-installed by `dotctl`)
- [GNU Stow](https://www.gnu.org/software/stow/) (auto-installed by `dotctl`)
- Zsh with [Oh-My-Zsh](https://ohmyz.sh)
- [Powerlevel10k](https://github.com/romkatv/powerlevel10k) theme
- [sleepwatcher](https://formulae.brew.sh/formula/sleepwatcher) — `brew install sleepwatcher` (required for sleep/hibernate save hooks)

## Structure

```
.
├── .config/            # Application configs
│   ├── nvim/           # Neovim (Lua + lazy.nvim)
│   ├── ghostty/        # Ghostty terminal
│   ├── karabiner/      # Keyboard remapping
│   ├── launch-agents/  # macOS LaunchAgents
│   └── 1Password/      # SSH agent config
├── .shell/             # Shell configuration
│   ├── profile         # Environment variables, PATH
│   ├── aliases         # Shell aliases
│   ├── zshinit         # Zsh plugins/theme setup
│   └── scripts/        # Custom scripts
│       ├── functions/  # Scripts that can cd (gbare.sh, sw.sh)
│       ├── init/       # Startup scripts (tt.sh)
│       ├── tmux/       # Tmux helper scripts
│       ├── crons/      # Scheduled jobs (installed by `dotctl crons install`)
│       ├── macos/      # macOS `defaults write` tweaks (`dotctl macos apply`)
│       └── unloaded/   # Inactive scripts
├── .claude/            # Claude Code CLI
│   ├── CLAUDE.md       # Global instructions
│   ├── settings.json   # Settings, permissions, plugins
│   └── skills/         # Custom skills
├── .zshrc              # Main Zsh config
├── .tmux.conf          # Tmux config
├── .gitconfig          # Git config
├── .p10k.zsh           # Powerlevel10k theme
└── dotctl              # Dotfiles CLI (stow, agents, crons)
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

LaunchAgents auto-start these on login (`com.hllvc.personal.tmux`, `com.hllvc.work.tmux`).

Session state is preserved across reboots via `tmux-resurrect` (forks: `hllvc/tmux-resurrect`, `hllvc/tmux-continuum`). The in-tmux auto-save is disabled (`@continuum-save-interval 0`) to avoid pty hitches; saving is handled externally:

- **Idle / periodic** — `com.hllvc.tmux-autosave` fires every 30 min, saves when HID idle ≥ 30 s (force-saves after 90 min)
- **Sleep / hibernate** — `sleepwatcher` runs `~/.sleep` before the system sleeps
- **Shutdown / reboot** — `com.hllvc.tmux-shutdown-save` daemon catches `SIGTERM` from launchd during shutdown

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
- **tmux-autosave** — idle-gated tmux session saver; fires every 30 min, saves when idle ≥ 30 s or 90 min has elapsed; also triggered on sleep (`~/.sleep` via `sleepwatcher`) and shutdown (`SIGTERM` trap via `com.hllvc.tmux-shutdown-save`). Replaces `@continuum-save-interval` (LaunchAgents: `com.hllvc.tmux-autosave`, `com.hllvc.tmux-shutdown-save`, `com.hllvc.sleepwatcher`).
- **tmux-warmup** — pre-starts the `work` and `personal` tmux servers at login so `tmux-continuum` auto-restore runs before first attach (LaunchAgents: `com.hllvc.personal.tmux`, `com.hllvc.work.tmux`).

### Tool Versions

`.versions` (repo root, not stowed) records the version of each tool the config was last checked against: tmux, Neovim, fzf, Ghostty, Claude Code, macOS, the Neovim plugin lockfile, and the oh-my-zsh / tmux plugin checkouts. Upgrades change defaults without asking (tmux 3.8 turned popups gray through its new theme colors), so drift from that version is the cue to read the tool's changes and adjust the config.

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

- **brewup.sh** (`brewup`) - The manual Homebrew upgrade: `brew update`, brew pins and pin-level upgrades (`dotctl versions pins`/`auto`), formulae, greedy casks, `autoremove` + `cleanup -s`, cask-shipped skill links, then a report of tools off their tested version and an immediate triage (see [Tool Versions](#tool-versions)). The sequence is `lib/brew-upgrade.sh`, shared with the homebrew-update cron. `brewup -n` previews.
- **com.sh** - Git commit with branch prefix extraction
- **j.sh** - Jira integration (sprints, worktrees from tickets)
- **tt.sh** - Tmux socket selector with fzf

### Neovim

Lua-based config with:

- lazy.nvim plugin manager
- LSP (TypeScript, Python, Go, Rust, Terraform, Helm, YAML, JSON, Lua, Markdown)
- Telescope, Treesitter, Copilot
- Custom keymaps (jk escape, L/H buffer nav)

### Claude Code

LSP plugins (pyright, lua-language-server) reuse Neovim's Mason-managed binaries.
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

Conditional include for work repositories:

- `~/.repos/stackguardian/.gitconfig` - Included for repos under `~/.repos/stackguardian/`
