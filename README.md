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
- `./dotctl stow [--adopt]` - Symlink dotfiles into `$HOME` (adopt folds existing files into the repo)
- `./dotctl agents <load|unload|list>` - Manage launch agents under `~/.config/launch-agents`
- `./dotctl crons <install|list>` - Run per-cron `install.sh` hooks under `.shell/scripts/crons/*/`
- `./dotctl macos <apply>` - Apply macOS `defaults write` tweaks (Finder, Dock, trackpad, Safari, Mail, …)
- `./dotctl -h` (or `./dotctl <command> -h`) - Help

## Prerequisites

- [Homebrew](https://brew.sh) (auto-installed by `dotctl`)
- [GNU Stow](https://www.gnu.org/software/stow/) (auto-installed by `dotctl`)
- Zsh with [Oh-My-Zsh](https://ohmyz.sh)
- [Powerlevel10k](https://github.com/romkatv/powerlevel10k) theme

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
│   ├── settings.json   # Settings, plugins, hooks
│   ├── skills/         # Custom skills
│   ├── commands/       # Slash commands
│   └── hooks/          # Lifecycle hooks
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

### Background Crons

Scheduled user-level jobs live under `.shell/scripts/crons/<name>/` and are installed via `dotctl crons install`. Each cron is free to define its own `install.sh` (e.g. for system-level hooks like `newsyslog.d` configs) — `dotctl` auto-discovers and runs them.

- **memory-pressure** — samples `memory_pressure` every 5 min, logs to `~/Library/Logs/com.hllvc.memory-pressure.log`, fires a macOS alert when free memory drops below 40% (LaunchAgent: `com.hllvc.memory-pressure`).

### Key Scripts

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
~/.shell/scripts/mason-link.sh
```

## Git Config

Conditional include for work repositories:

- `~/.repos/stackguardian/.gitconfig` - Included for repos under `~/.repos/stackguardian/`
