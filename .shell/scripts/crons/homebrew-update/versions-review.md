The homebrew-update cron found tools in this dotfiles repo whose installed version no longer matches the version recorded in `.versions` (the one the config was last checked against), or a brew-pinned formula with an upgrade waiting. Review them and propose a plan.

1. Run `./dotctl versions` for the table: tested, installed and state per tool. `./dotctl versions -h` explains the states and subcommands.
2. For every row that isn't `ok`, read what changed between `tested` and the installed version (or, for `held`, the available one). The row's `changes` column in `.versions` says where:
   - a file path: read the entries newer than `tested`
   - a URL: fetch the release notes for that range
   - `nvim:help-news`: `nvim -c 'help news' -c only`, and follow `.config/nvim/CLAUDE.md`
   - `git-log`: `git -C <checkout> log --oneline <tested>..HEAD`, where the checkout is the path in the row's probe
3. Check this repo's config for that tool against what changed: removed or renamed options, changed defaults, and new features that would replace something the config does by hand. Search the whole repo; settings for one tool are often spread over several files (for example tmux: `.tmux.conf` and `.shell/scripts/tmux/`).
4. Write the plan. Per tool, say what changed that matters for this config, list the edits with file:line, and for a held upgrade, whether to take it now. If a tool needs no config change, say so. Mark anything you couldn't confirm and say where you looked.

After I approve: make the edits, run `./dotctl versions upgrade <tool>` for each held upgrade I agreed to, and then `./dotctl versions accept <tool>` for every tool reviewed. Commit following the repo's commit conventions. Don't push.
