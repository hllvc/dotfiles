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

Two canonical shapes exist. Constants below apply to **both**; deviations are drift.

| Setting | Canonical value |
|---|---|
| `PLATFORM` | `linux/amd64` |
| Build secret (Lambda/ECS only) | `--secret id=git_token,env=GIT_TOKEN` |
| `DASH_ACCOUNT_ID` | `790543352839` |
| `DASH_PROFILE` | `default` |
| `PROD_ACCOUNT_ID` | `476299211833` |
| `PROD_PROFILE` | `sg-prod` |
| `BUILD_REGION` default | `eu-central-1` |
| PROD US region (Lambda/ECS only) | `us-east-2` |

### Lambda / ECS / Custom archetype

Services with a `deploy:` step. Section order: `General → DASH → PROD → PROD EU → PROD US → PROD All Regions`.
15 `.PHONY` targets. Template: `references/canonical-template.md`.

### Container archetype (workflow-step / runtime container)

Images pushed to ECR only — no `deploy:` step, no PROD US/EU split, no `git_token` by
default. Targets: `help version login build dash prod`. Template: `references/canonical-container-template.md`.

`login:` always authenticates **both** `public.ecr.aws` (us-east-1) **and** the
private build registry — required when any `Dockerfile*` pulls a base image from
`public.ecr.aws/...`. During `setup`, grep the repo's Dockerfiles; if a public
ECR base is found, treat the public-ecr login as mandatory. During `review`,
flag a missing public-ecr login as **CRITICAL** when any `Dockerfile*` references
`public.ecr.aws/`, otherwise IMPORTANT.

Fixed constants: `references/variables.md`.

## Mode: review

**Inputs:** Makefile path (default: `./Makefile`; also try `./src/Makefile`).

**Steps:**
1. `Read` the target Makefile.
2. **Detect archetype:** if the Makefile has no `deploy:` target and no `build-deploy-*` targets → **container archetype**; otherwise → **Lambda/ECS/custom archetype**.
3. Walk the appropriate section of `references/review-checklist.md` check by check.
4. Match against `references/known-drift.md` — cite matching entries by name in the report.
5. Emit a structured report:

```
# Makefile Review: <path>
Archetype: container | lambda/ecs/custom

## Summary
<overall status>

## CRITICAL
<findings>

## IMPORTANT
<findings>

## MINOR
<findings>

## Expected differences (project-specific, not flagged)
- SERVICE_NAME / IMAGE_NAME: <value>
- (Lambda/ECS only) DASH_IMAGE / DASH_LAMBDA / PROD_IMAGE / PROD_LAMBDA: <value>
- (Lambda/ECS only) deploy: recipe body
```

## Mode: update

**Steps:**
1. Run the review pipeline silently (including archetype detection).
2. **Auto-apply all CRITICAL fixes** via `Edit` immediately. List each change in the summary.
3. Surface IMPORTANT and MINOR findings via `AskUserQuestion` multi-select. Apply chosen items.
4. Preserve project-specific values:
   - All archetypes: `SERVICE_NAME` (header comment)
   - Container: `IMAGE_NAME`
   - Lambda/ECS: `DASH_IMAGE`, `DASH_LAMBDA`, `PROD_IMAGE`, `PROD_LAMBDA`, the `deploy:` body (unless the body itself is drift)

## Mode: setup

**Step 1 — Collect inputs via `AskUserQuestion` (one turn):**

| Input | Default |
|---|---|
| Service name (goes in header comment) | — (required) |
| Archetype | `lambda` \| `ecs` \| `custom` \| `container` |

**If archetype = `container`:** ask only for `IMAGE_NAME` (e.g. `workflow-steps/my-step`) and
whether to add `git_token` build secret (default: **no**).

**If archetype = `lambda` / `ecs` / `custom`:** ask for:
- DASH image name (default: service name)
- DASH lambda/function name (default: service name)
- PROD image name (default: service name)
- PROD lambda/function name (default: service name)
- Use git_token build secret? (default: **yes**)
- (ECS) DASH and PROD cluster/service names
- (custom) deploy command body

**Step 2 — `Write` the Makefile:**

- **Container archetype:** use `references/canonical-container-template.md`, substituting
  `{{SERVICE_NAME}}` and `{{IMAGE_NAME}}`. If `git_token` is yes, add
  `--secret id=git_token,env=GIT_TOKEN \` to the `build:` recipe.
- **Lambda/ECS/custom archetype:** use `references/canonical-template.md`, substituting
  `{{SERVICE_NAME}}`, `{{DASH_IMAGE}}`, `{{DASH_LAMBDA}}`, `{{PROD_IMAGE}}`, `{{PROD_LAMBDA}}`,
  `{{DEPLOY_BODY}}` from `references/archetypes.md`. If `git_token` is no, omit the secret line.

**Important:** All recipe lines MUST use tabs (not spaces). The `Write` tool preserves tabs — do not use spaces.

**Step 3 — Print a reminder:**
- `make help` to verify the generated Makefile renders correctly
- (Lambda/ECS) Set `GIT_TOKEN` in your shell before running `make build-dash`

## References

- `references/canonical-template.md` — Lambda/ECS/custom Makefile with `{{PLACEHOLDERS}}`
- `references/canonical-container-template.md` — container (build+push only) Makefile
- `references/variables.md` — fixed account IDs, profiles, regions, `.PHONY` list
- `references/review-checklist.md` — CRITICAL / IMPORTANT / MINOR check catalogue (both archetypes)
- `references/known-drift.md` — confirmed drift patterns with before/after snippets
- `references/archetypes.md` — Lambda / ECS / custom `deploy:` recipe bodies
