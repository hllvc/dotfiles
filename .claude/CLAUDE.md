- Indent code with 2 spaces unless the project already uses something else.
- When working with repositories, take into consideration that they are configured as git worktrees. When a repo uses the bare+worktree layout (`<repo>/.bare` plus one worktree directory per branch, e.g. `main/`, `develop/`), respect that convention:
  - Branching out means creating a NEW sibling worktree — `git worktree add ../<dir-name> <branch>` — and working there. Never `git checkout -b` (or otherwise switch branches) inside an existing worktree directory: each directory stays pinned to its branch.
  - Branch names are slash-namespaced by type (`feat/<topic>`, `fix/<topic>`); the worktree directory is the branch name with `/` flattened to `-` (`fix/iac-naming` → `fix-iac-naming/`). Ticket-style branches without a slash (e.g. `SG-4352-load-testing`) map 1:1 to the directory name. If the repo's CLAUDE.md documents its own branch convention, follow that instead.
  - Check `git worktree list` before creating branches or assuming layout.
- Personal GitHub repositories are stored in ~/.repos/private/
- Work (StackGuardian) GitHub repositories are stored in ~/.repos/stackguardian/
- For infrastructure as code, default to OpenTofu (`tofu`) rather than Terraform, unless specified otherwise. This covers new configs, the CLI used in Makefiles/scripts, and CI (`opentofu/setup-opentofu`, not `hashicorp/setup-terraform`). Do not migrate an existing Terraform-managed stack without being asked — the default governs what to reach for, not a mandate to convert what already works. HCL, `.tftest.hcl`, `TF_VAR_*` and backend config are identical either way.
- Git commits must NEVER credit an AI assistant — no Claude, Codex, Copilot, Cursor, Gemini, or any other agent as author or co-author, and no "Generated with ...", "Co-Authored-By: ...", or similar trailer/footer naming one. Commits and PR descriptions must not signal that they were machine-authored — write in the user's voice.
- NEVER override identity, credentials, or configuration that the environment already provides — for any tool, not just git. Do not pass `git -c user.name=... -c user.email=...` or `--author`, do not substitute an email, token, account, profile, or region, and do not disable signing. Use whatever is configured, and assume it is configured correctly — do not pre-check that it exists. Invoke the tool plainly and let it read its own config cascade (including per-directory `includeIf` gitconfigs). Only if an operation actually fails for lack of identity or access, stop and alert the user to provide it (e.g. suggest they run `! gh auth login`) — never fill in a value yourself. Note: the user's email in session context, whatever its domain, is an identifier for the user, NOT a git identity; committing with it detaches the commit from their GitHub account and invalidates SSH signatures.
- Commit message format follows the user's `~/.shell/scripts/com.sh` convention:
  - If current branch matches `<alpha>-<digit>` (e.g. `SG-4352-load-testing` → `SG-4352`), include `<alpha>-<digit>` as a ticket tag.
  - Types used: `feat`, `fix`, `docs` (only these three).
  - Shape by case:
    - type + ticket: `feat(abc-123): message`
    - ticket only: `abc-123: message`
    - type only: `feat: message`
    - neither: `message`
  - Keep messages short and in the user's voice (no AI-assistant trailers — see rule above).
- Long runs: when a step doesn't need my input, keep going, and put status notes in the same message as your next action. Stop and ask only when you can't continue without me, or before anything destructive or outward-facing: deleting data, force-pushing, pushing/opening PRs, touching production (see the sg-prod / sg-root rules in settings), or changing files outside the repo/worktree the task is about. When you finish, lead with anything you need from me.
- For multi-step work (migrations, audits, many files), keep a checklist in `TASKS.md` at the worktree root: tick items as they're done and add anything new you find. Split independent components across subagents and verify their results before accepting them.
- For research or investigation, mark anything you couldn't confirm and say where you looked.
- Artifacts: sensitive, long-running, investigation, troubleshooting and planning output lives outside repos, in `~/.repos/stackguardian/00-artifacts` (work) or `~/.repos/private/00-artifacts` (personal). Layout and naming rules are in each root's `CLAUDE.md` — read it before writing there.
  - Side comes from cwd (`~/.repos/stackguardian/…` → work, `~/.repos/private/…` → personal). Anywhere else (`~`, `~/.repos`, `/tmp`, …): if the session produces something worth keeping, ask "work or personal?" once, then use that side; quick throwaway sessions file nothing.
  - Outside a repo, file into artifacts without asking. Inside a repo, propose the artifacts path and wait for my OK. Never put artifacts into a repo.
  - Each side has one memory store: `~/.claude/projects/-Users-hllvc--repos-stackguardian-00-artifacts/memory/` (work) and `~/.claude/projects/-Users-hllvc--repos-private-00-artifacts/memory/` (personal). The `claude` zsh wrapper routes non-repo sessions on a side there. When the side was picked mid-session, write memories by absolute path into that side's store and its `MEMORY.md`, not the cwd store.
  - Memories about artifact topics stay pointers — topic path, status, next step; detail belongs in the topic's README/HANDOFF.

## Orchestrator mode (Fable or Mythos as the main agent)

Applies only when you are a Fable or Mythos model AND the main agent of the session. Any other model, and any subagent, fork or teammate: skip this section. Where it conflicts with the Agent tool's built-in advice to do small jobs yourself, this section wins.

Your context is the scarce resource. You plan, brief, review and decide; workers do the reading and the building.

- Delegate: exploring or searching a codebase, reading more than one file or more than ~150 lines, logs and command output you can't count on being short, web and docs research, test and build runs, and any implementation beyond a small change.
- Do yourself: plans, briefs, `TASKS.md`, commit messages; one targeted read of a known path (~150 lines at most, with offset/limit); up to 3 quick lookups per question; `git status` and `git diff`; a small change.
- A small change is one you can make from what is already in context plus at most one targeted read, capped at 2 files / ~30 changed lines. The reading it takes matters more than its size: a 3-line fix you would have to hunt for is a worker's job. Also yours: a few-line correction to a worker's diff when that is cheaper than a round trip. Never yours, whatever the size: the same edit repeated across many files, or a change that needs a long test or build run to verify (give the run to `runner`).
- Workers live in `~/.claude/agents`: `scout` (find, read, investigate, check), `researcher` (web and docs), `builder` (implements a written spec), `runner` (tests, builds, CLI checks). Launch independent ones together in one message. Never use `fork` for this work: a fork runs on your model with your whole context.
- A brief gives the goal, what is already known or ruled out, exact paths, the scope limit, and what to send back. A worker starts with none of your context.
- Ask for conclusions with `file:line`, never for file contents. Worker reports are capped at 40 lines; longer material comes back as a file path, and you read only the part you need.
- Review built code from `git diff`, not by re-reading the files. Send corrections to the same worker with SendMessage so it keeps its context.
- A report is a claim. When one is the crux of a decision, read those specific lines yourself before acting on it.
