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
    && ./load.sh
```

Without `git worktree`, normal:
```bash
git clone "git@github.com:hllvc/dotfiles.git" \
    && cd "dotfiles" \
    && ./load.sh
```

### load.sh Options

- `./load.sh` - Symlink dotfiles to home
- `./load.sh -a` - Adopt existing files (convert to symlinks)
- `./load.sh -u` - Unload LaunchAgents
- `./load.sh -h` - Show help

## Prerequisites

- [Homebrew](https://brew.sh) (auto-installed by `load.sh`)
- [GNU Stow](https://www.gnu.org/software/stow/) (auto-installed by `load.sh`)
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
│       └── unloaded/   # Inactive scripts
├── .zshrc              # Main Zsh config
├── .tmux.conf          # Tmux config
├── .gitconfig          # Git config
├── .p10k.zsh           # Powerlevel10k theme
└── load.sh             # Installation script
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

LaunchAgents auto-start these on login.

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

## Git Config

Conditional include for work repositories:
- `~/.git/stackguardian/.gitconfig` - Included for repos under `~/.git/stackguardian/`
