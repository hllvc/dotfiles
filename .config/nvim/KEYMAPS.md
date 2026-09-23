# Keymaps & plugins

Hand-maintained reference for this config. The config itself is the source of
truth — when the two disagree, the config wins and this file needs an edit.

Live answers, always correct:

- `<leader>sk` — Telescope keymap picker, searches every active mapping.
- `<leader>` then wait — which-key shows what follows the prefix.
- `:Lazy` — plugin list, load reasons, startup times.

**Leader is `<Space>`.** `<M-…>` is Alt/Option. Buffer-local maps (LSP, gitsigns)
only exist once that plugin attaches to the buffer.

---

## Everyday

| Key                  | Action                                           |
| -------------------- | ------------------------------------------------ |
| `<leader><leader>`   | Write file                                       |
| `jk` / `JK`          | Leave insert/select mode                         |
| `H` / `L`            | Previous / next buffer                           |
| `<leader>l`          | Last buffer (`<C-^>`)                            |
| `<leader>bx`         | Delete buffer                                    |
| `<C-e>` / `<C-y>`    | Scroll down / up 3 lines                         |
| `<leader>p`          | Reselect what was just pasted                    |
| `<` / `>` (visual)   | Indent and keep the selection                    |
| `.` (visual)         | Repeat last change over the selection            |
| `<leader>r` (visual) | Search-and-replace, prefilled from the selection |
| `w!!` (cmdline)      | Write the file with sudo                         |

## Windows, splits, tmux

| Key                                 | Action                                                      |
| ----------------------------------- | ----------------------------------------------------------- |
| `<M-h/j/k/l>`                       | Move between splits **and tmux panes** (vim-tmux-navigator) |
| `<M-\>`                             | Previous split/pane                                         |
| `<leader><M-h/j/k/l>`               | Move the window itself                                      |
| `<leader>ws`                        | Toggle split orientation (vertical ↔ horizontal)            |
| `<C-Left>` / `<C-Right>`            | Resize split width                                          |
| `<C-w>m`                            | Zoom the current split (vim-zoom)                           |
| `<Esc><Esc>`                        | Leave terminal mode                                         |
| `<leader>op` / `os` / `ov` (visual) | Open the selection in a tmux popup / h-split / v-split      |

## Finding things — Telescope

| Key                        | Action                                                          |
| -------------------------- | --------------------------------------------------------------- |
| `<leader>ff` / `fF`        | Find files (root dir / cwd)                                     |
| `<leader>/` / `sG`         | Live grep (root dir / cwd)                                      |
| `<leader>,`                | Switch buffer                                                   |
| `<leader>fr` / `fR`        | Recent files (global / cwd)                                     |
| `<leader>fc`               | Find a file in this config                                      |
| `<leader>sw` / `sW`        | Grep word under cursor (root / cwd); visual greps the selection |
| `<leader>ss` / `sS`        | Document / workspace symbols                                    |
| `<leader>sd` / `sD`        | Document / workspace diagnostics                                |
| `<leader>sh`               | Help pages                                                      |
| `<leader>sk`               | **Keymaps**                                                     |
| `<leader>sb`               | Fuzzy-find in current buffer                                    |
| `<leader>sm` / `s"`        | Marks / registers                                               |
| `<leader>sq` / `sl`        | Quickfix / location list                                        |
| `<leader>sC` / `sa` / `so` | Commands / autocommands / options                               |
| `<leader>sM` / `sH`        | Man pages / highlight groups                                    |
| `<leader>sP`               | Spellfiles                                                      |
| `<leader>sR`               | Resume the last picker                                          |
| `<leader>:`                | Command history                                                 |
| `<leader>uC`               | Colorscheme picker with live preview                            |

Inside a picker: `<C-t>` send to Trouble · `<C-q>` send to quickfix · `<C-s>`
horizontal split · `<C-Up>`/`<C-Down>` cycle prompt history · `<Esc>` close ·
`s` (normal mode) toggle multi-select.

## Jumping — flash.nvim

| Key     | Mode    | Action                                                                         |
| ------- | ------- | ------------------------------------------------------------------------------ |
| `s`     | n, x, o | Type 2 chars, then the label that appears                                      |
| `S`     | n, o    | Jump to a treesitter node                                                      |
| `r`     | o       | Remote — act on a distant textobject without moving (`yr` + jump + textobject) |
| `R`     | o, x    | Treesitter search                                                              |
| `<C-s>` | cmdline | Toggle flash labels during a `/` search                                        |

`s` labels matches both above and below the cursor, in the current window only.
`<CR>` jumps to the first match without a label.

`f` `F` `t` `T` `;` `,` are stock Vim — flash's `f`/`t` integration is off.

**Operating on a flash target.** `d`, `c` and `y` + `s` do **not** reach flash:
`ds`, `cs` and `ys` are nvim-surround's (delete / change / add surrounding). Use
one of these instead:

| Want                                  | Keys                                                                |
| ------------------------------------- | ------------------------------------------------------------------- |
| Delete / yank / change up to a spot   | `v` `s` _chars_ _label_, then `d` / `y` / `c`                       |
| Act on a distant textobject, stay put | `dr` / `yr` / `cr`, jump, then a textobject — e.g. `yr` _jump_ `iw` |
| Other operators work directly         | `>s` · `<s` · `=s` · `gus` · `gUs` … _chars_ _label_                |

Note `s`/`S` replace Vim's built-in substitute — use `cl`/`cc` for those.

## Textobjects

Treesitter-backed, `a` = around, `i` = inside:

| Object      | Meaning                    |
| ----------- | -------------------------- |
| `af` / `if` | Function                   |
| `ac` / `ic` | Class                      |
| `aa` / `ia` | Parameter / argument       |
| `ao` / `io` | Block                      |
| `am` / `im` | Call                       |
| `ag` / `ig` | Comment                    |
| `an` / `in` | Conditional                |
| `al` / `il` | Line (around / inner)      |
| `ih`        | Git hunk                   |
| `i%` / `a%` | Matched pair (vim-matchup) |

Motions: `]m` / `[m` next/previous function · `]]` / `[[` next/previous class ·
`]M` / `[M` and `][` / `[]` for their ends.

Selection: `<C-Space>` grow the selection to the enclosing node, `<BS>` shrink.

## Editing

| Key                  | Action                                                      |
| -------------------- | ----------------------------------------------------------- |
| `ysiw"`              | Surround a word with quotes (nvim-surround)                 |
| `cs"'`               | Change surrounding `"` to `'`                               |
| `ds"`                | Delete surrounding `"`                                      |
| `S` (visual)         | Surround the selection                                      |
| `gcc` / `gc{motion}` | Toggle line comment                                         |
| `gbc` / `gb{motion}` | Toggle block comment                                        |
| `%`                  | Jump between matching pairs, incl. `if`/`end` (vim-matchup) |
| `<M-u>`              | Undo tree                                                   |
| `:Tabularize /=`     | Align on `=`                                                |
| `<leader>wf`         | Wrap functions in fold markers                              |
| `<leader>Bs` / `Bt`  | Comment box via `boxes`                                     |
| `<leader>E`          | Run the current `.js` in Scriptable                         |
| `<C-g>,`             | Expand an emmet abbreviation (HTML/CSS/JSX)                 |

## LSP

Buffer-local, attached per language server.

| Key                        | Action                                                                 |
| -------------------------- | ---------------------------------------------------------------------- |
| `gd` / `gD`                | Definition / declaration                                               |
| `gr`                       | References                                                             |
| `gi`                       | Implementation                                                         |
| `K`                        | Hover docs                                                             |
| `<leader>k`                | Signature help                                                         |
| `<leader>cr`               | Rename                                                                 |
| `<leader>ca`               | Code action (also visual)                                              |
| `<leader>cD`               | Type definition                                                        |
| `<leader>cd`               | Diagnostic float                                                       |
| `<leader>cq`               | Buffer diagnostics in Trouble                                          |
| `<leader>cu`               | GitHub workflows: bump every `uses:` pin to the version its note names |
| `[d` / `]d`                | Previous / next diagnostic                                             |
| `<leader>wa` / `wr` / `wl` | Add / remove / list workspace folder                                   |

One result jumps straight there; several open Trouble.

## Completion

| Key               | Action                                             |
| ----------------- | -------------------------------------------------- |
| `<C-j>` / `<C-k>` | Next / previous item (`<C-j>` also opens the menu) |
| `<C-l>`           | Confirm, or expand a snippet, or trigger Copilot   |
| `<C-h>`           | Dismiss the menu and any Copilot suggestion        |
| `<C-n>` / `<C-p>` | Jump forward / back through snippet placeholders   |
| `<C-u>` / `<C-d>` | Scroll the docs popup                              |
| `<Tab>`           | Accept the Copilot suggestion                      |
| `<M-]>` / `<M-[>` | Cycle Copilot suggestions                          |

In GitHub workflows (`lua/gha.lua`) the menu also offers the action's tags after
`uses: owner/repo@` (major tags first), the repo's branches and tags under
`branches:` / `tags:` / `ref:`, and repo-relative paths under `paths:` and
`working-directory:`. `uses:` lines pinned behind the latest release get a
`← vN available` note at the end of the line; `<leader>cu` bumps them all (one undo).

## Diagnostics, quickfix, TODOs

| Key                   | Action                                                  |
| --------------------- | ------------------------------------------------------- |
| `<leader>xx` / `xX`   | Document / workspace diagnostics (Trouble)              |
| `<leader>xs`          | Symbols panel                                           |
| `<leader>xL`          | LSP definitions/references panel                        |
| `<leader>xq` / `xl`   | Quickfix / location list (Trouble)                      |
| `]q` / `[q`           | Next / previous item                                    |
| `<leader>xcq` / `xcl` | Clear quickfix / location list                          |
| `]t` / `[t`           | Next / previous TODO comment                            |
| `<leader>st` / `sT`   | TODOs in Telescope                                      |
| `<leader>xt` / `xT`   | TODOs in Trouble                                        |
| `<leader>ud`          | Toggle inline (virtual text) diagnostics                |
| `<leader>uu`          | Toggle diagnostic underlines                            |
| `<leader>uh`          | Toggle the hover diagnostic popup                       |
| `<leader>ui`          | Insert the right ignore comment for the diagnostic here |

`<leader>ui` knows shellcheck, yamllint, ruff, pyright, eslint, lua_ls, tflint
and tfsec syntax.

## Formatting

Format-on-save is **changed git hunks only** by default, so touching one line of
an unformatted file does not reformat the whole thing.

| Key                   | Action                                     |
| --------------------- | ------------------------------------------ |
| `<leader>F`           | Format the whole buffer (or selection) now |
| `<leader>uf`          | Toggle changed-lines-only ↔ whole buffer   |
| `<leader>cf` (visual) | Format the selection as another language   |
| `<leader>cF`          | Format injected languages                  |
| `<leader>ci`          | `:ConformInfo` — which formatter runs here |

## Git

| Key                        | Action                                                   |
| -------------------------- | -------------------------------------------------------- |
| `<leader>gs`               | Status (fugitive)                                        |
| `<leader>gc` / `gp` / `gl` | Commit / push / log                                      |
| `<leader>gb`               | Blame                                                    |
| `<leader>gds`              | Diff split                                               |
| `<leader>gB` / `gY`        | Open on GitHub / copy the URL (both work on a selection) |
| `<leader>gC` / `gf`        | Git commits / git files (Telescope)                      |
| `]h` / `[h`                | Next / previous hunk                                     |
| `<leader>ghs` / `ghu`      | Stage / unstage hunk                                     |
| `<leader>ghr` / `ghR`      | Reset hunk / buffer                                      |
| `<leader>ghS`              | Stage buffer                                             |
| `<leader>ghp` / `gt`       | Preview hunk (float / inline)                            |
| `<leader>ghb`              | Blame this line                                          |
| `<leader>ghd` / `ghD`      | Diff against index / `~`                                 |
| `<leader>gw`               | Toggle word diff                                         |
| `ih`                       | Hunk textobject                                          |

Merge conflicts: `]x` / `[x` to move between them, then `<leader>gdo` ours ·
`<leader>gdt` theirs · `<leader>gdb` both · `<leader>gdn` neither.

## AI

| Key                               | Action                                                  |
| --------------------------------- | ------------------------------------------------------- |
| `<C-,>`                           | Toggle / focus Claude (send selection from visual mode) |
| `<leader>as`                      | Send the selection                                      |
| `<leader>ar` / `ac`               | Resume / continue a session                             |
| `<leader>af` / `ag` / `ab` / `aG` | Add files / grep / buffers / git files                  |
| `<leader>aa` / `ad`               | Accept / deny a diff                                    |

## Tools

| Key                           | Action                                       |
| ----------------------------- | -------------------------------------------- |
| `<leader>cm`                  | Mason — install servers, formatters, linters |
| `<leader>vs`                  | Pick a Python virtualenv                     |
| `<leader>snl` / `snh` / `snd` | Noice: last message / history / dismiss      |
| `:Lazy`                       | Plugin manager                               |
| `:StartupTime`                | Profile startup                              |
| `:MarkdownPreviewToggle`      | Live markdown preview in the browser         |

---

## Plugins

### Loaded at startup

| Plugin           | Purpose                                   |
| ---------------- | ----------------------------------------- |
| lazy.nvim        | Plugin manager                            |
| gruvbox-material | Colorscheme                               |
| nvim-treesitter  | Parsing → highlighting, indent, folds     |
| snacks.nvim      | Replaces `vim.ui.select` / `vim.ui.input` |

### Navigation & search

| Plugin                      | Purpose                                    |
| --------------------------- | ------------------------------------------ |
| telescope.nvim              | Fuzzy finder for everything                |
| telescope-fzf-native.nvim   | Native sorter; makes Telescope fast        |
| flash.nvim                  | Label-based jumping; also enhances `f`/`t` |
| nvim-treesitter-textobjects | Syntax-aware textobjects and motions       |

### LSP & completion

| Plugin                                                                  | Purpose                                   |
| ----------------------------------------------------------------------- | ----------------------------------------- |
| nvim-lspconfig                                                          | Starts and configures language servers    |
| mason.nvim / mason-lspconfig.nvim                                       | Installs servers, formatters, linters     |
| nvim-cmp                                                                | Completion menu                           |
| cmp-nvim-lsp, -buffer, -path, -cmdline, -calc, -nvim-lsp-signature-help | Completion sources                        |
| LuaSnip, cmp_luasnip                                                    | Snippet engine and its source             |
| lazydev.nvim, luvit-meta                                                | Neovim API types when editing this config |
| schemastore.nvim                                                        | JSON/YAML schemas                         |
| fidget.nvim                                                             | LSP progress indicator                    |

### Formatting & linting

| Plugin       | Purpose                                                                         |
| ------------ | ------------------------------------------------------------------------------- |
| conform.nvim | Format on save, restricted to changed hunks                                     |
| nvim-lint    | shellcheck, yamllint, ruff, tflint; actionlint + zizmor on `.github/workflows/` |

### Git

| Plugin                    | Purpose                          |
| ------------------------- | -------------------------------- |
| vim-fugitive, vim-rhubarb | Git porcelain and GitHub links   |
| gitsigns.nvim             | Gutter signs and hunk operations |
| conflict-marker.vim       | Merge conflict resolution        |

### Editing

| Plugin                                      | Purpose                                   |
| ------------------------------------------- | ----------------------------------------- |
| nvim-surround                               | Add/change/delete surrounding pairs       |
| Comment.nvim, nvim-ts-context-commentstring | Commenting, correct in embedded languages |
| nvim-autopairs                              | Auto-close brackets and quotes            |
| nvim-ts-autotag                             | Auto-close and rename HTML/JSX tags       |
| vim-matchup                                 | Extends `%` beyond brackets               |
| todo-comments.nvim                          | Highlights and finds TODO/FIX/HACK        |
| tabular                                     | Column alignment                          |
| undotree                                    | Visual undo history                       |

### UI

| Plugin               | Purpose                                |
| -------------------- | -------------------------------------- |
| lualine.nvim         | Statusline and buffer winbar           |
| noice.nvim, nui.nvim | Cmdline and message UI                 |
| which-key.nvim       | Prefix popup                           |
| trouble.nvim         | Diagnostics / quickfix / symbols panel |
| dashboard-nvim       | Start screen                           |
| nvim-web-devicons    | Filetype icons                         |
| vim-startuptime      | Startup profiler                       |

### Languages

| Plugin                | Purpose                                            |
| --------------------- | -------------------------------------------------- |
| typescript-tools.nvim | JS/TS language server                              |
| go.nvim, guihua.lua   | Go tooling                                         |
| venv-selector.nvim    | Python virtualenv picker                           |
| emmet-vim             | HTML/CSS abbreviations                             |
| markdown-preview.nvim | Browser preview                                    |
| rustaceanvim          | Rust — **off** via `cond = false`, still installed |

### AI, tmux, libraries

| Plugin             | Purpose                                   |
| ------------------ | ----------------------------------------- |
| claudecode.nvim    | Claude Code in Neovim                     |
| copilot.lua        | Inline suggestions                        |
| vim-tmux-navigator | Unified split/pane movement               |
| vim-zoom           | Maximize a split                          |
| plenary.nvim       | Lua stdlib used by Telescope and gitsigns |

---

## Gotchas

- `s` and `S` belong to flash, not Vim's substitute. Use `cl` and `cc`.
- `ds` / `cs` / `ys` are nvim-surround, so `d`/`c`/`y` + flash `s` never fire.
  Select first (`vs…d`) or use flash remote (`dr`, `yr`).
- `an` / `in` are mapped to the conditional textobject, which shadows Neovim
  0.12's built-in `an` / `in` node selection. `]n` / `[n` / `]N` / `[N` still
  work, and `<C-Space>` / `<BS>` cover the same ground.
- `<leader>d` has no mappings — there is no debugger configured.
- Saving formats only the lines you changed. `<leader>uf` switches that off.
- Folds are remembered per file via `mkview` / `loadview`.
- Focus loss writes every modified buffer, but skips formatting and the
  whitespace passes, so tmux pane switches stay fast.
