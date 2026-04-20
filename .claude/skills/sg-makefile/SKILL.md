---
name: sg-makefile
description: Review, update, or scaffold StackGuardian-style Makefiles for Docker build/deploy workflows. Use for "review makefile", "audit makefile", "fix makefile drift", "update makefile", "create makefile", "generate makefile", "scaffold makefile", "sg-makefile".
allowed-tools: Read, Edit, Write, Glob, Grep, Bash, AskUserQuestion
version: 2.0.0
---

# StackGuardian Makefile Skill

Canonical skill files live at `~/.repos/private/dotfiles/master/.claude/skills/sg-makefile/`.

## Mode Selection

Detect mode from the user's phrasing. Use `AskUserQuestion` if ambiguous.

| Phrase | Mode |
|---|---|
| review / audit / check / lint | `review` |
| update / align / fix / fix drift / bring into line | `update` |
| create / generate / scaffold / set up / new | `setup` |

## Canonical Truth

StackGuardian Lambda services use a standard Makefile in `src/Makefile` (or the project root).

Key constants — deviations from these are drift:

| Setting | Canonical value |
|---|---|
| `PLATFORM` | `linux/amd64` |
| Build secret | `--secret id=git_token,env=GIT_TOKEN` |
| `DASH_ACCOUNT_ID` | `790543352839` |
| `DASH_PROFILE` | `default` |
| `PROD_ACCOUNT_ID` | `476299211833` |
| `PROD_PROFILE` | `sg-prod` |
| `BUILD_REGION` default | `eu-central-1` |
| PROD US region | `us-east-2` |

Section order: `General → DASH → PROD → PROD EU → PROD US → PROD All Regions`

Full canonical Makefile with placeholders: `references/canonical-template.md`.
Fixed constants: `references/variables.md`.

## Mode: review

**Inputs:** Makefile path (default: `./Makefile`; also try `./src/Makefile`).

**Steps:**
1. `Read` the target Makefile.
2. Walk `references/review-checklist.md` check by check. Classify each finding as CRITICAL, IMPORTANT, or MINOR.
3. Match against `references/known-drift.md` — if a pattern matches, cite the known-drift entry by name in the report.
4. Emit a structured report:

```
# Makefile Review: <path>

## Summary
<overall status>

## CRITICAL
<findings>

## IMPORTANT
<findings>

## MINOR
<findings>

## Expected differences (project-specific, not flagged)
- SERVICE_NAME: <value>
- DASH_IMAGE / DASH_LAMBDA: <value>
- PROD_IMAGE / PROD_LAMBDA: <value>
- deploy: recipe body (if custom)
```

## Mode: update

**Steps:**
1. Run the review pipeline silently to collect all findings.
2. **Auto-apply all CRITICAL fixes** via `Edit` immediately. List each change applied in the summary.
3. Surface IMPORTANT and MINOR findings via `AskUserQuestion` multi-select. Apply chosen items.
4. Preserve project-specific values: `SERVICE_NAME` (in header comment), `DASH_IMAGE`, `DASH_LAMBDA`, `PROD_IMAGE`, `PROD_LAMBDA`, the `deploy:` body (unless that body itself is drift).

## Mode: setup

**Step 1 — Collect inputs via `AskUserQuestion` (one turn):**

| Input | Default |
|---|---|
| Service name (goes in header comment) | — (required) |
| Archetype | `lambda` \| `ecs` \| `custom` |
| DASH image name | service name |
| DASH lambda/function name | service name |
| PROD image name | service name |
| PROD lambda/function name | service name |
| Use git_token build secret? | `yes` |

For ECS archetype: also ask for DASH and PROD cluster/service names (fill into the ECS `deploy:` body from `references/archetypes.md`).
For custom archetype: ask the user to paste their deploy command (uses `$(DEPLOY_REGION)`, `$(LAMBDA_NAME)`, `$(FULL_IMAGE)`, `$(VERSION)`).

**Step 2 — `Write` the Makefile** from `references/canonical-template.md`, substituting:

| Placeholder | Value |
|---|---|
| `{{SERVICE_NAME}}` | service name |
| `{{DASH_IMAGE}}` | DASH image name |
| `{{DASH_LAMBDA}}` | DASH lambda name |
| `{{PROD_IMAGE}}` | PROD image name |
| `{{PROD_LAMBDA}}` | PROD lambda name |
| `{{DEPLOY_BODY}}` | body from `references/archetypes.md` for chosen archetype |

If `use-git-token` is `no`, omit the `--secret id=git_token,env=GIT_TOKEN \` line from the `build:` target.

**Important:** All recipe lines MUST use tabs (not spaces). The `Write` tool preserves tabs — do not use spaces.

**Step 3 — Print a reminder:**
- `make help` to verify the generated Makefile renders correctly
- Set `GIT_TOKEN` in your shell before running `make build-dash`

## References

- `references/canonical-template.md` — full Makefile with `{{PLACEHOLDERS}}`
- `references/variables.md` — fixed account IDs, profiles, regions, `.PHONY` list
- `references/review-checklist.md` — CRITICAL / IMPORTANT / MINOR check catalogue
- `references/known-drift.md` — confirmed drift patterns with before/after snippets
- `references/archetypes.md` — Lambda / ECS / custom `deploy:` recipe bodies
