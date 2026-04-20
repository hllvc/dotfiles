---
name: sg-github-workflows
description: Review, update, or scaffold StackGuardian GitHub Actions workflows. Use for "review github actions", "audit workflows", "align workflows", "update workflows", "fix workflow drift", "create github actions", "scaffold workflows", "set up CI", "sg-github-workflows".
allowed-tools: Read, Edit, Write, Glob, Grep, Bash, AskUserQuestion
version: 2.0.0
---

# StackGuardian GitHub Workflows Skill

Canonical skill files live at `~/.repos/private/dotfiles/master/.claude/skills/sg-github-workflows/`.

## Mode Selection

Detect mode from the user's phrasing. Use `AskUserQuestion` if ambiguous.

| Phrase | Mode |
|---|---|
| review / audit / check / compare / lint | `review` |
| update / align / fix / fix drift / bring into line | `update` |
| create / generate / scaffold / set up / new | `setup` |

## Canonical Truth

StackGuardian services use a **6-file workflow set** in `.github/workflows/`, all pinned at `@main`.

| File | Trigger | Purpose |
|---|---|---|
| `_deploy_qa.yml` | `workflow_call` | Reusable QA deploy wrapper (`aws-account-id: "790543352839"`) |
| `_deploy_prod.yml` | `workflow_call` | Reusable PROD deploy wrapper (`aws-account-id: "476299211833"`) |
| `build_deploy_qa.yml` | push + workflow_dispatch | Build and Dash deploy entrypoint |
| `build_prod.yml` | push tags `v*` | PROD build entrypoint (triggers regional deploys) |
| `deploy_prod_eu.yml` | workflow_dispatch | Manual PROD EU deploy |
| `deploy_prod_us.yml` | workflow_dispatch | Manual PROD US deploy |

Files prefixed `_` are reusable (`workflow_call` only) — their `name:` starts with `🚫` to signal "do not run directly".

Two archetypes: **Lambda** (default, 3 of 4 repos) and **ECS** (only `api`). Review mode auto-detects from the presence of `ecs-service:` in `build_deploy_qa.yml`. See `references/archetype-ecs.md` for ECS-specific review checks; setup mode only scaffolds Lambda.

Full reusable library API and account/region constants: `references/canonical-set.md`.

## Mode: review

**Inputs:** target repo root path (default: cwd).

**Steps:**
1. `Glob` `.github/workflows/*.yml` in the target directory.
2. Check that all 6 canonical files are present — flag missing files as CRITICAL.
3. `Read` each file and compare against the corresponding template in `references/templates/`. When checking `secrets:` blocks: inspect the repo `Dockerfile` (at `build-context`/`dockerfile` path) for `GIT_TOKEN` references before flagging its presence or absence — it is only expected if the Dockerfile uses it.
4. Detect archetype: check `build_deploy_qa.yml` for `ecs-service:` — if present, apply `references/archetype-ecs.md` checks.
5. Classify all findings per `references/review-checklist.md` and match against `references/known-drift.md`.
6. Check OIDC sub claim: resolve the repo slug via `gh repo view --json nameWithOwner -q .nameWithOwner` in the target directory. Run `gh api /repos/{slug}/actions/oidc/customization/sub` and verify `use_default: false` with keys `[repo, job_workflow_ref, environment]`. If wrong or default: add a CRITICAL finding (DRIFT-4) with the fix command from `references/canonical-set.md`.
7. Emit a single structured report (format below).

**Report format:**
```
# Workflow Review: <repo-name>

## Summary
<overall status: aligned / minor drift / significant drift>

## CRITICAL  (block deploy — fix immediately)
<findings>

## IMPORTANT  (fix soon)
<findings>

## MINOR  (nice to have)
<findings>

## Expected differences (project-specific, not flagged)
- ecr-repo: <value>
- function-name (QA / PROD): <value>
- build-context: <value>
- dotenv (QA / PROD): <value>
```

## Mode: update

**Steps:**
1. Run the review pipeline (same as review mode) to collect all findings.
2. **Auto-apply all CRITICAL fixes** immediately. List each change applied in the summary.
   - Workflow file fixes: apply via `Edit`.
   - OIDC sub claim (DRIFT-4): run the `gh api --method PUT` command from `references/canonical-set.md`.
3. If any IMPORTANT or MINOR findings remain, surface them as a multi-select via `AskUserQuestion` ("Which of these should I also fix?"). Apply chosen items via `Edit`.
4. If any file from the canonical 6-file set is missing entirely, `Write` it from the corresponding `references/templates/` file — ask for project-specific placeholder values first.
5. Print a post-update summary and suggest running `git diff .github/workflows/`.

**Always preserve** these project-specific values (never flag, never change):
`ecr-repo`, `function-name`, `ecs-service`, `ecs-cluster`, `build-context`, `dotenv`, `build-args`, `tag-match`, `dockerfile`, `pipfile`, `additional-repo`, `additional-repo-path`, `additional-repo-ref`.

## Mode: setup

**Step 1 — Collect inputs via `AskUserQuestion` (one turn):**

Ask for all of the following, with defaults shown:

| Input | Default |
|---|---|
| Service display name (for workflow `name:` strings) | — (required) |
| ECR repo name | — (required) |
| Lambda function name (QA) | — (required) |
| Lambda function name (PROD, if different from QA) | same as QA |
| Build context path | `.` |
| Dockerfile path | `Dockerfile` |
| Dotenv file (QA) | `.env.qa` |
| Dotenv file (PROD) | `.env.production` |
| Default branch triggering QA builds | `main` |
| Include EU DR deploy job? | `yes` |
| Extra secrets? | Check repo `Dockerfile` for `GIT_TOKEN` references — include only if found. Ask if also INFRACOST_API_KEY, GH_APP_PEM pairs, export-secrets |

**Step 2 — Ensure `.github/workflows/` exists:**
```bash
mkdir -p .github/workflows
```

**Step 3 — `Write` all 6 workflow files** from `references/templates/`, substituting:

| Placeholder | Value |
|---|---|
| `{{SERVICE_NAME}}` | service display name |
| `{{ECR_REPO}}` | ECR repo |
| `{{QA_FUNCTION_NAME}}` | QA Lambda name |
| `{{PROD_FUNCTION_NAME}}` | PROD Lambda name |
| `{{BUILD_CONTEXT}}` | build context |
| `{{DOTENV_QA}}` | QA dotenv |
| `{{DOTENV_PROD}}` | PROD dotenv |
| `{{DEFAULT_BRANCH}}` | triggering branch |

If EU DR deploy is not needed, omit the `deploy-eu-dr` job from `build_deploy_qa.yml`.

**Step 4 — Print post-setup checklist:**
- [ ] Configure GitHub OIDC sub claim for this repo — run the `gh api --method PUT` command from `references/canonical-set.md`
- [ ] Add `BUILD` + `PROD` trust policy entries to `SGGithubActionsWrite` in PROD account (`sg-prod` AWS profile); add `QA` entries in Dash account (`default` AWS profile) — see `references/canonical-set.md`
- [ ] Add `GIT_TOKEN` to repository secrets (only if Dockerfile references it; and any other additional secrets selected)
- [ ] Push a test commit to `{{DEFAULT_BRANCH}}` to trigger `build_deploy_qa.yml`
- [ ] Push a `v*` tag to test `build_prod.yml` and regional dispatch

## References

- `references/canonical-set.md` — full reusable library API, account/region constants, @main pin rationale
- `references/templates/` — canonical YAML templates with `{{PLACEHOLDERS}}`
- `references/archetype-ecs.md` — ECS-specific review checks (review mode only)
- `references/review-checklist.md` — CRITICAL / IMPORTANT / MINOR check catalogue
- `references/known-drift.md` — confirmed drift patterns with before/after snippets
