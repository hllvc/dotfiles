# Canonical StackGuardian GitHub Actions Spec

## Account IDs and Regions

| Environment | AWS Account ID | Primary Region | Notes |
|---|---|---|---|
| QA (DASH) | `790543352839` | `eu-central-1` | Used in `_deploy_qa.yml` and QA build |
| PROD | `476299211833` | `eu-central-1` | Used in `_deploy_prod.yml` and PROD build |
| PROD US | `476299211833` | `us-east-2` | Same account; deploy dispatched by `build_prod.yml`. **No separate US build job.** |
| PROD EU DR | `790543352839` | `eu-west-1` | Optional DR; same QA account |

## Single-build, multi-region deploy

PROD builds **only to `eu-central-1`**. The ECR repository in `eu-central-1` is configured with a **cross-region replication rule** that mirrors every pushed image to `us-east-2` (and to any other region that hosts a deploy target). Region-specific deploy jobs (`deploy_prod_eu.yml`, `deploy_prod_us.yml`) reference the **same `image-tag`** from the single build, but each points at the ECR registry in its own region — the image is already there courtesy of replication.

**Implication for new prod workflows:**

- Never add a second `build-us` (or `build-<region>`) job. One `build` job, multiple deploy jobs sharing `${{ needs.build.outputs.image-tag }}`.
- If a new prod region is added, ensure the ECR replication rule covers it before adding the deploy job.
- For deploy jobs that reference a regional ECR URI (e.g., DynamoDB image-pin updates that store a region-qualified ECR URL per regional table), use the deploy job's region, not the build region — the same tag exists in both registries.

## Branch Pin Rule

All `uses:` references to `StackGuardian/sg-internal-github-actions` **must use `@main`**.

```yaml
# Correct
uses: StackGuardian/sg-internal-github-actions/.github/workflows/_build.yml@main

# CRITICAL drift — feature branches are not stable
uses: StackGuardian/sg-internal-github-actions/.github/workflows/_build.yml@feat/something
```

## 6-File Set — Structure and Triggers

### `_deploy_qa.yml` and `_deploy_prod.yml` (reusable wrappers)

- Trigger: `workflow_call` only
- Display name starts with `🚫` ("do not run directly")
- Hardcode their respective `aws-account-id` and `deploy-environment`
- Pass through `aws-region` and `image-tag` from caller
- Call `_deploy_lambda.yml@main` (Lambda archetype) or `_deploy_ecs.yml@main` (ECS archetype)

### `build_deploy_qa.yml`

- Triggers: `push: branches: [<default-branch>]` + `workflow_dispatch`
- `workflow_dispatch` always includes a `deploy-eu-dr: boolean` input (default false)
- Concurrency: `group: ${{ github.workflow }}-${{ github.ref }}`, `cancel-in-progress: true`
- Permissions: `id-token: write`, `contents: read` (no `actions: write` — calls local reusable workflows, not dispatch)
- Jobs: `build` → `deploy-eu` (needs: build) → `deploy-eu-dr` (if: inputs.deploy-eu-dr, needs: build)
- `build` job passes `image-tag` output to deploy jobs

### `build_prod.yml`

- Trigger: `push: tags: ['v*']` only
- Concurrency: same group, `cancel-in-progress: false`
- Permissions: `id-token: write`, `contents: read`, `actions: write` (dispatches `deploy_prod_eu.yml` and `deploy_prod_us.yml` via `deploy-workflows`)
- `build` job passes `deploy-workflows: "deploy_prod_eu.yml,deploy_prod_us.yml"` — the reusable `_build.yml` dispatches these automatically after push
- `deploy-environment: "BUILD"` (ungated GitHub Environment — auto-allows prod builds on tag push; deploys gate on `"PROD"` in `_deploy_prod.yml`)

### `deploy_prod_eu.yml` and `deploy_prod_us.yml`

- Trigger: `workflow_dispatch` with required `image-tag: string` input
- Permissions: `id-token: write` only (no checkout needed)
- Single job calls `./.github/workflows/_deploy_prod.yml` with the appropriate `aws-region`

## Reusable Library API

Repository: `StackGuardian/sg-internal-github-actions`
All references pin `@main`.

### `actions/configure-aws` (composite)

Assumes an AWS IAM role via OIDC.

| Input | Required | Default | Description |
|---|---|---|---|
| `aws-account-id` | yes | — | AWS account number |
| `aws-region` | no | `eu-central-1` | Region for role assumption |
| `iam-role-name` | no | `SGGithubActionsWrite` | Role to assume |

Caller must have `permissions: id-token: write`.

### `.github/workflows/_build.yml` (reusable)

Checkout → OIDC ECR login → Buildx build + push → optionally dispatch deploy workflows.

**Required inputs:** `aws-account-id`, `aws-region`, `ecr-repo`

**Optional inputs:**

| Input | Default | Description |
|---|---|---|
| `deploy-environment` | — | GitHub Environment label: `"QA"` (QA builds), `"BUILD"` (ungated prod build), `"PROD"` (gated prod deploy) |
| `build-context` | `.` | Docker build context path |
| `additional-repo` | — | Extra repo to checkout |
| `additional-repo-path` | `./` | Where to place additional repo |
| `additional-repo-ref` | — | Ref for additional repo |
| `dotenv` | — | Dotenv file to load before build |
| `pipfile` | — | Path to Pipfile for Python deps |
| `dockerfile` | `Dockerfile` | Dockerfile path |
| `platforms` | `linux/amd64` | Build platform(s) |
| `build-args` | — | Docker `--build-arg` values |
| `deploy-workflows` | — | Comma-separated workflow filenames to dispatch after push |
| `export-secrets` | `false` | Export repository secrets as env vars |
| `tag-match` | `v(.*)` | Regex to extract version from git tag |
| `build-target` | — | Docker build `--target` stage |
| `iam-role-name` | `SGGithubActionsWrite` | IAM role to assume |

**Secrets (all optional):**
`GIT_TOKEN`, `INFRACOST_API_KEY`, `GH_APP_PEM_KEY_NAME`, `GH_APP_PEM`, `GH_APP_PEM_KEY_NAME_US`, `GH_APP_PEM_US`

**Outputs:** `image-tag`, `image-uri`, `registry`

### `.github/workflows/_deploy_lambda.yml` (reusable)

Runs `aws lambda update-function-code` with the given ECR image.

| Input | Required | Default | Description |
|---|---|---|---|
| `aws-account-id` | yes | — | AWS account number |
| `aws-region` | yes | — | Region to deploy into |
| `deploy-environment` | yes | — | Environment label (`"QA"` or `"PROD"`) |
| `function-name` | yes | — | Lambda function name |
| `ecr-repo` | yes | — | ECR repository name |
| `image-tag` | yes | — | Image tag to deploy |
| `iam-role-name` | no | `SGGithubActionsWrite` | IAM role to assume |

No secrets.

### `.github/workflows/_deploy_ecs.yml` (reusable)

Renders a new ECS task definition with updated image/env and deploys.

| Input | Required | Default | Description |
|---|---|---|---|
| `aws-account-id` | yes | — | |
| `aws-region` | yes | — | |
| `deploy-environment` | yes | — | |
| `ecs-service` | yes | — | ECS service name |
| `ecs-cluster` | yes | — | ECS cluster name |
| `task-definition` | no* | — | Task definition name (*required unless force-new-deployment) |
| `container-name` | no* | — | Container in task def |
| `ecr-repo` | no* | — | ECR repo |
| `image-tag` | no* | — | Image tag |
| `force-new-deployment` | no | `false` | Force redeploy without image change |
| `environment-variables` | no | — | `KEY=value` lines for ECS env vars |
| `iam-role-name` | no | `SGGithubActionsWrite` | |

**Secret:** `environment-secrets` (optional, `KEY=value` lines, masked)

## OIDC Sub Claim Configuration

GitHub's default OIDC subject claim is too broad for scoped IAM trust policies.
Each repo must be customised to include `environment` in the sub claim so that
the `BUILD` and `PROD` GitHub Environments map to distinct IAM conditions.

### Per-repo GitHub config (run once per repo)

```bash
# Configure sub claim — replace {ORG}/{REPO}
gh api --method PUT \
  /repos/{ORG}/{REPO}/actions/oidc/customization/sub \
  -F 'use_default=false' \
  -F 'include_claim_keys[]=repo' \
  -F 'include_claim_keys[]=job_workflow_ref' \
  -F 'include_claim_keys[]=environment'

# Verify
gh api /repos/{ORG}/{REPO}/actions/oidc/customization/sub
# Expected: {"use_default":false,"include_claim_keys":["repo","job_workflow_ref","environment"]}
```

### IAM trust policy — `SGGithubActionsWrite`

**PROD account (`476299211833`, `sg-prod` AWS profile):**

Add two `StringLike` condition values to the `token.actions.githubusercontent.com:sub` array:

```
"repo:{ORG}/{REPO}:job_workflow_ref:StackGuardian/sg-internal-github-actions/.github/workflows/_build.yml@refs/heads/main:environment:BUILD",
"repo:{ORG}/{REPO}:job_workflow_ref:*:environment:PROD"
```

- The `BUILD` entry is scoped to `_build.yml@main` — the reusable workflow called by `build_prod.yml`.
- The `PROD` entry uses `*` for the caller (deploys come from `_deploy_lambda.yml` or `_deploy_ecs.yml`).

**Dash account (`790543352839`, `default` AWS profile):**

Add equivalent `QA` entries following the same pattern (check existing trust policy for the current QA condition shape).

### AWS profile mapping

| Account | AWS Profile |
|---|---|
| Dash / QA (`790543352839`) | `default` |
| PROD (`476299211833`) | `sg-prod` |

### Verify current IAM trust policy

```bash
# PROD account
aws iam get-role --role-name SGGithubActionsWrite --profile sg-prod \
  --query 'Role.AssumeRolePolicyDocument.Statement[*].Condition' --output json

# Dash account
aws iam get-role --role-name SGGithubActionsWrite --profile default \
  --query 'Role.AssumeRolePolicyDocument.Statement[*].Condition' --output json
```
