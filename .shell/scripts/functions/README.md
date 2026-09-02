# functions

Scripts sourced as shell functions so they can change the working directory.

[Back to scripts](../)

## Scripts

| Script | Description |
|--------|-------------|
| `gbare.sh` | Clones a GitHub repo as a bare repository with worktree structure and creates the initial default branch worktree |
| `sw.sh` | fzf branch switcher for bare+worktree repos. One line per branch (local and remote merged) with `worktree`/`local`/`remote`/`merged`/`gone` tags, ahead/behind, age and subject; preview shows worktree status and log. `sw [branch]` switches (nested path preserved, unknown name offers to create), `sw -c [name [base]]` creates (default branch preselected), `sw -d` multi-select delete with dirty-worktree warning, `-a` fetches first, `-l` lists, `-h` help |
