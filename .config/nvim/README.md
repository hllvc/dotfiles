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
├── init.lua           # Entry point: leader keys, backup dir, core module loading
├── KEYMAPS.md         # Keymap and plugin reference
├── lua/
│   ├── options.lua    # Neovim options
│   ├── config.lua     # lazy.nvim bootstrap and plugin loading
│   ├── mappings.lua   # Custom keymaps
│   ├── autocmds.lua   # Autocommands
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
├── ftplugin/          # Filetype-specific settings
├── spell/             # Spell files
└── lazy-lock.json     # Plugin version lockfile
```

## Features

- **Plugin manager** - lazy.nvim with lockfile
- **LSP** - TypeScript, Python, Go, Terraform, Helm, YAML, JSON, Lua, Markdown (Rust off)
- **Completion** - Autocompletion with snippet support
- **Search** - Telescope fuzzy finder
- **Syntax** - Treesitter for highlighting and text objects
- **AI** - Copilot integration
- **Navigation** - Flash for quick motions
- **Todos** - checkmate.nvim with tag-driven views, inbox capture and triage (`<leader>t`)
- **Keymaps** - `jk` escape, `L`/`H` buffer navigation, space as leader
