# Neovim

Lua-based Neovim configuration with lazy.nvim, the native LSP client (vim.lsp), and nvim-cmp completion.

**Targets Neovim 0.12.6.** The authoritative value lives in `vim.g.nvim_target_version`
(`init.lua`) and is realigned with the installed binary on every config change; startup
warns when the running Neovim and the target drift apart.

See [KEYMAPS.md](KEYMAPS.md) for every keymap and what each plugin is for.

[Back to .config](../)

## Structure

```
nvim/
├── init.lua           # Entry point: leader keys, backup dir, core module loading, version check
├── KEYMAPS.md         # Keymap and plugin reference
├── CLAUDE.md          # Conventions for agents working in this config (version alignment, stylua)
├── lua/
│   ├── options.lua    # Neovim options
│   ├── config.lua     # lazy.nvim bootstrap and plugin loading
│   ├── mappings.lua   # Custom keymaps
│   ├── autocmds.lua   # Autocommands (filetype detection, workflow bump key)
│   ├── format.lua     # Format on save, restricted to changed git hunks
│   ├── gha.lua        # GitHub Actions: tag/branch/path completion, update notes, `<leader>cu` bump
│   ├── todo/          # Todo workflow on checkmate.nvim (views, capture, triage, status)
│   ├── plugins/       # Plugin specs (lazy.nvim)
│   │   ├── ai.lua
│   │   ├── colorscheme.lua
│   │   ├── completion.lua
│   │   ├── editor.lua
│   │   ├── flash.lua
│   │   ├── lsp.lua
│   │   ├── telescope.lua
│   │   ├── todo.lua
│   │   ├── treesitter.lua
│   │   └── ui.lua
│   └── snippets/      # Custom snippets
├── ftplugin/          # Filetype-specific settings (helm, markdown, terraform-vars)
├── linters/           # nvim-lint config files (zizmor.yml)
├── syntax/            # Extra syntax files (terraform-vars.vim)
├── spell/             # Spell files
└── lazy-lock.json     # Plugin version lockfile
```

## Features

- **Plugin manager** - lazy.nvim with lockfile
- **LSP** - TypeScript (typescript-tools), Python, Go, Terraform, Helm, YAML, JSON, Lua, Markdown, ESLint, GitHub Actions (`gh_actions_ls`); Rust off
- **Kubernetes** - manifests validated against their kind's schema, CRDs included
  (schema-companion; `<leader>cs` to pick one by hand); Helm charts detected only
  beside a `Chart.yaml`
- **Completion** - Autocompletion with snippet support
- **Formatting and linting** - conform.nvim formats on save, only the lines changed in git; nvim-lint runs shellcheck, yamllint, ruff and tflint, plus actionlint and zizmor on workflow files (`lua/format.lua`, `linters/`)
- **GitHub Actions** - `lua/gha.lua` completes `uses:` tags, branches and paths, notes when a newer version exists (`← vN available`) and bumps pins with `<leader>cu`; also for `.forgejo` and `.gitea` workflows
- **Search** - Telescope fuzzy finder
- **Syntax** - Treesitter for highlighting and text objects
- **AI** - Copilot inline suggestions; claudecode.nvim to drive Claude Code from the editor (`<C-,>`, `<leader>a…`)
- **Navigation** - Flash for quick motions
- **Todos** - checkmate.nvim with tag-driven views, inbox capture and triage (`<leader>t`)
- **Keymaps** - `jk` escape, `L`/`H` buffer navigation, space as leader
