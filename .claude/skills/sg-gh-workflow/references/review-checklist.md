# Workflow Review Checklist

## CRITICAL — Must fix before next deploy

- [ ] All `uses:` lines referencing `StackGuardian/sg-internal-github-actions` pin `@main`
      (never `@feat/...`, `@reusable-actions`, `@v*`)
- [ ] `_deploy_qa.yml` hardcodes `aws-account-id: "790543352839"`
- [ ] `_deploy_prod.yml` hardcodes `aws-account-id: "476299211833"`
- [ ] All 6 canonical files are present (missing file = missing deploy path)
- [ ] `_deploy_qa.yml` and `_deploy_prod.yml` call the correct upstream reusable:
      Lambda → `_deploy_lambda.yml@main`, ECS → `_deploy_ecs.yml@main`
- [ ] `_deploy_qa.yml` sets `deploy-environment: "QA"`, `_deploy_prod.yml` sets `"PROD"`
- [ ] GitHub OIDC sub claim configured: `use_default: false` with keys `[repo, job_workflow_ref, environment]`
      (verify: `gh api /repos/{slug}/actions/oidc/customization/sub`; fix command in `canonical-set.md`)

## CRITICAL — Dockerfile (private-git clone)

Only applies when the repo Dockerfile clones private git deps. See
`references/dockerfile-conventions.md` for the canonical snippet.

- [ ] Clone uses the **bare token** `https://${GIT_TOKEN}@github.com` — no username,
      no `x-access-token:` prefix, no URL-encoding of the token
- [ ] Build secret mount id is `git_token`, mounted `env=GIT_TOKEN`
      (must match what `_build.yml` forwards)
- [ ] Does **not** read `git_user` / `/run/secrets/git_user` (never forwarded — build would fail)
- [ ] The `insteadOf` credential rewrite is undone in the same layer
      (`git config --unset-all ...` or `rm -f ~/.gitconfig`)
- [ ] If Dockerfile mounts `git_token`, the workflow passes it
      (`GIT_TOKEN: ${{ secrets.GIT_TOKEN }}` or `secrets: inherit`) and `GIT_TOKEN` is a repo secret

## IMPORTANT — Fix soon

- [ ] `build_deploy_qa.yml` has `cancel-in-progress: true` in the concurrency block
- [ ] `build_prod.yml` has `cancel-in-progress: false`
- [ ] `build_deploy_qa.yml` permissions: `id-token: write`, `contents: read` (no `actions: write` — uses local reusable workflows, not dispatch)
- [ ] `build_prod.yml` permissions: `id-token: write`, `contents: read`, `actions: write` (needs dispatch for `deploy-workflows`)
- [ ] `deploy_prod_eu.yml` and `deploy_prod_us.yml` permissions: `id-token: write` only
- [ ] `build_prod.yml` passes `deploy-environment: "BUILD"` (not `"PROD"` or `"PROD_DEPLOY"`; missing label is also drift — repos without it should migrate to `"BUILD"`)
- [ ] `build_prod.yml` passes `deploy-workflows: "deploy_prod_eu.yml,deploy_prod_us.yml"`
- [ ] `deploy_prod_eu.yml` job ID is `deploy-eu`; `deploy_prod_us.yml` job ID is `deploy-us`
- [ ] Concurrency group pattern: `${{ github.workflow }}-${{ github.ref }}`

## MINOR — Nice to have

- [ ] `_deploy_qa.yml` and `_deploy_prod.yml` display name starts with `🚫`
- [ ] `build_deploy_qa.yml` includes `deploy-eu-dr` conditional job (DR support)
- [ ] All `${{ inputs.* }}` and `${{ secrets.* }}` expressions are quoted where used in YAML scalar context
- [ ] `workflow_dispatch` on `build_deploy_qa.yml` includes `deploy-eu-dr: boolean` input

## Expected differences (project-specific — never flag)

These values differ legitimately between repos:

| Field | Notes |
|---|---|
| `ecr-repo` | ECR repository name |
| `function-name` | Lambda function name (QA and PROD may differ) |
| `ecs-service`, `ecs-cluster` | ECS archetype only |
| `task-definition`, `container-name` | ECS archetype only |
| `build-context` | Docker build context (e.g. `./src`, `./platform_api`) |
| `dotenv` | Dotenv file (SG convention: `.env.qa` for QA, `.env.prod` for PROD) |
| Dockerfile base image / cleanup steps | Repo-specific; only the git-clone convention is enforced |
| `build-args` | Extra build arguments |
| `tag-match` | Version extraction regex |
| `dockerfile` | Dockerfile path |
| `pipfile` | Python deps path |
| `additional-repo` | Extra repo to checkout |
| `export-secrets` | Whether to export secrets |
| `GH_APP_PEM_*` secrets | App PEM keys |
| Default branch in push trigger | `main` vs `develop` |
