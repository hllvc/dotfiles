# Neovim

Lua-based Neovim configuration with lazy.nvim plugin manager and native LSP.

[Back to .config](../)

## Structure

```
nvim/
├── init.lua           # Entry point: leader keys, backup dir, core module loading
├── lua/
│   ├── options.lua    # Neovim options
│   ├── config.lua     # lazy.nvim bootstrap and plugin loading
│   ├── mappings.lua   # Custom keymaps
│   ├── autocmds.lua   # Autocommands
│   ├── plugins/       # Plugin specs (lazy.nvim)
│   │   ├── ai.lua
│   │   ├── colorscheme.lua
│   │   ├── completion.lua
│   │   ├── editor.lua
│   │   ├── flash.lua
│   │   ├── lsp.lua
│   │   ├── telescope.lua
│   │   ├── treesitter.lua
│   │   └── ui.lua
│   └── snippets/      # Custom snippets
├── ftplugin/          # Filetype-specific settings
├── spell/             # Spell files
└── lazy-lock.json     # Plugin version lockfile
```

## Features

- **Plugin manager** - lazy.nvim with lockfile
- **LSP** - TypeScript, Python, Go, Rust, Terraform, Helm, YAML, JSON, Lua, Markdown
- **Completion** - Autocompletion with snippet support
- **Search** - Telescope fuzzy finder
- **Syntax** - Treesitter for highlighting and text objects
- **AI** - Copilot integration
- **Navigation** - Flash for quick motions
- **Keymaps** - `jk` escape, `L`/`H` buffer navigation, space as leader
