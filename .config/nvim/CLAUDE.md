# Neovim config

## Neovim version alignment

`vim.g.nvim_target_version` in `init.lua` is the single source of truth for the exact
Neovim release this config is written against. `README.md` repeats it in prose.

**Every change to this config ends by realigning that value with the installed binary:**

1. `nvim --version` — read the exact `NVIM vX.Y.Z`.
2. If it differs from `vim.g.nvim_target_version`, update `init.lua` **and** `README.md`
   in the same commit as the config change.
3. Bumping the number alone is not enough when the minor moved (e.g. 0.12 → 0.13).
   Re-check the config against the new release first:
   - `nvim -c 'help news' -c 'only'` — new, changed, and deprecated APIs.
   - `grep -rn 'vim.deprecate(' "$VIMRUNTIME/lua/vim/"` — what is deprecated and in
     which release it gets removed; cross-check against `lua/**/*.lua`.
   - `nvim -c 'checkhealth' -c 'only'` — plugin-side deprecations and broken assumptions.

Startup warns when the running Neovim and the target disagree. That warning is the
reminder to do the above; it is not a bug. `vim.g.nvim_version_check = false` silences it.

## Conventions

- Lua files are formatted by stylua with its defaults: **tab** indentation, not spaces.
  This overrides the global 2-space rule.
- Plugins are pinned by `lazy-lock.json`. Changing a plugin spec's repo owner (an
  upstream rename) does not need a lockfile edit — lazy keys entries by directory name.
