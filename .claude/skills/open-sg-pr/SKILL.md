---
name: open-sg-pr
description: Open (or update) a draft GitHub PR for the current branch with a generated StackGuardian-style title and description built from the local git diff against the target branch. Use for "open a PR", "open sg pr", "create pull request", "draft PR", "raise a PR", "/open-sg-pr".
allowed-tools: Bash, Read, Write, Grep, Glob, AskUserQuestion
version: 1.0.0
---

# Open StackGuardian PR

Create — or update, if one already exists — a **draft** GitHub PR for the current branch.
Title and body are generated from the **local git diff of the current branch against its
target branch** (not a browser tab). Follow `references/pr-style.md` for all title/body wording.

Canonical skill files live at `~/.repos/private/dotfiles/main/.claude/skills/open-sg-pr/`.

## Arguments

Invoked as `/open-sg-pr [base] [flags] [focus text]`. All optional.

| Token | Meaning |
|---|---|
| a branch name (e.g. `develop`) | Override the base/target branch. Default: repo's default branch. |
| `--ready` | Create as ready-for-review instead of draft. |
| `--type feat\|fix\|docs` | Force the title type instead of inferring it. |
| `--dry-run` | Generate and print title + body, do everything **except** push and create. |
| anything else | Treated as a **focus** hint — a mandatory emphasis override for the body (e.g. "focus on the migration risk"). |

## Procedure

### 1. Preconditions
Run these together and read the results:
- `git rev-parse --is-inside-work-tree` — must be a git repo (repos here are git worktrees).
- `gh auth status` — must be authenticated. If not, tell the user to run `! gh auth login`.
- `git rev-parse --abbrev-ref HEAD` — current branch. If it's `main`/`master`/the default branch, stop and tell the user to switch to a feature branch.

### 2. Gather context (batch these)
- Default branch: `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`
- Repo slug: `gh repo view --json nameWithOwner -q .nameWithOwner`
- Existing PR for this branch: `gh pr list --head <branch> --state open --json number,url,isDraft,title`
- Upstream/ahead-behind: `git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null` and `git status -sb`
- Uncommitted changes: `git status --porcelain` — if non-empty, warn that uncommitted work will **not** be in the PR (do not commit it for them).
- PR template: check, in order, `.github/PULL_REQUEST_TEMPLATE.md`, `.github/pull_request_template.md`, `PULL_REQUEST_TEMPLATE.md`, `docs/PULL_REQUEST_TEMPLATE.md`, and the directory `.github/PULL_REQUEST_TEMPLATE/` (multiple templates — use the default/first, or ask if several). If found, `Read` it.

### 3. Resolve base branch
- Use the `[base]` argument if given, else the default branch.
- `git fetch origin <base> --quiet` then verify `git rev-parse --verify origin/<base>`. If the base doesn't exist, ask.
- Base must differ from the current branch.
- Diff against **`origin/<base>`** so the PR reflects the remote target.

### 4. Compute the diff (three-dot, from the merge-base)
- `git log --reverse --format='%h %s%n%b' origin/<base>...HEAD` — commits to reflect and expand.
- `git diff --stat origin/<base>...HEAD` — files touched.
- `git diff origin/<base>...HEAD` — the patch. If it's very large (e.g. > ~1500 lines), rely on `--stat` plus reading the most significant files rather than the whole patch.
- If there are **no commits** in range, stop — nothing to PR.

### 5. Extract metadata
- **Ticket:** first `SG-\d+` match (case-insensitive) in the branch name, else in commit subjects/bodies. Normalize to uppercase `SG-<n>`.
- **Type** (for the title), unless `--type` given, in this order: branch prefix (`fix|bugfix|hotfix` → `fix`; `feat|feature` → `feat`; `doc|docs` → `docs`); else the majority conventional type across commits; else diff heuristic (only docs/markdown changed → `docs`, otherwise `feat`).
- **Issue links:** collect `#\d+` and `Fixes/Closes/Resolves #\d+` from commit messages for the body's related-issues line.

### 6. Draft title + body
Follow `references/pr-style.md` exactly.
- If a **PR template** was found, fill *its* sections/checklists with generated content instead of imposing the default section set; keep its headings and any required checkboxes.
- Apply the **focus** hint as a mandatory emphasis override if one was passed.
- Write the finished body to a temp file in the scratchpad dir (e.g. `<scratchpad>/pr-body.md`) so it can be passed with `--body-file` (avoids shell-escaping issues with backticks/newlines).

### 7. Confirm before creating
Print: resolved **base**, **head** branch, final **title**, draft/ready state, whether a push is needed, and whether this will **create** or **update** an existing PR. Show the full body. Then confirm with the user (`AskUserQuestion`: Create / Edit wording / Cancel). Skip creation entirely if `--dry-run`.

### 8. Push if needed
If the branch has no upstream or is ahead of its remote (and not `--dry-run`): `git push -u origin <branch>`.

### 9. Create or update
- **Existing open PR** → update in place:
  `gh pr edit <number> --title "<title>" --body-file <file>` (and `--base <base>` if it changed). Note: does not toggle draft state.
- **No PR** → create:
  ```
  gh pr create --draft --base <base> --head <branch> --assignee @me \
    --title "<title>" --body-file <bodyfile>
  ```
  Omit `--draft` if `--ready` was passed.
- Do **not** auto-open a browser.

### 10. Report
Print the PR URL, number, and draft/ready state. If the working tree had uncommitted changes, restate that they were excluded.

## Notes
- Never add Claude/AI authorship or trailers to the title or body (per global rules).
- Assignee is always the current user (`@me`); reviewers/labels are out of scope unless the user asks.
- `gh pr create` fails if the branch isn't pushed — step 8 handles that; if a push is rejected (protected/diverged), surface the error rather than force-pushing.
