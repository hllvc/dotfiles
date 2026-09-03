# functions

Scripts sourced as shell functions so they can change the working directory. Both source the shared helpers in [`../lib/worktree.sh`](../lib/worktree.sh).

[Back to scripts](../)

## Scripts

| Script | Description |
|--------|-------------|
| `gbare.sh` | Clones a GitHub repo as a bare repository with worktree structure and creates the initial default branch worktree |
| `sw.sh` | fzf branch switcher for bare+worktree repos. One line per branch (local and remote merged) with `worktree`/`local`/`remote`/`merged`/`gone`/`recent` tags, ahead/behind, age and subject; preview shows worktree status, carry health and log. `sw [branch]` switches (nested path preserved, unknown name offers to create), `sw -` goes back, `sw -c [name [base]]` creates (offers to move uncommitted changes along, runs `sw.postCreate`, `--no-rebase` or `sw.rebase=false` skips the rebase), `sw -d` multi-select delete warning about dirty worktrees and commits on no remote, `sw st` shows every worktree, `-a` fetches first, `-l` lists, `-L` hides remote-only refs, `-h` help. Picker keys: `ctrl-x` delete, `ctrl-o` create from highlighted, `ctrl-f` fetch, `ctrl-r` reload. `sw carry` manages gitignored local files (tfvars, .env) carried into every worktree: symlinks into `<repo>/.local/` or per-branch copies, detach/forget (`ctrl-s`/`ctrl-o`/`ctrl-x`/`ctrl-f`), `carry ls|apply|diff|reset|edit`, remembered in `.bare/config`. Picker scans every worktree and shows which branches hold each file. `sw.remote` overrides `origin` |
