# ECS Archetype Reference

The ECS archetype is used by the `api` repo. Review mode auto-detects it when
`build_deploy_qa.yml` passes `ecs-service:` to the build job or when `_deploy_qa.yml`
references `_deploy_ecs.yml`.

Setup mode does not scaffold ECS — this file is review-mode only.

## Detection

ECS archetype is present if any of the following are true in the 6-file set:
- `_deploy_qa.yml` calls `_deploy_ecs.yml@main` (not `_deploy_lambda.yml`)
- `_deploy_qa.yml` declares `ecs-service`, `ecs-cluster`, or `environment-variables` inputs

## How ECS Differs from Lambda

### `_deploy_qa.yml` and `_deploy_prod.yml`

ECS versions replace the Lambda inputs with ECS-specific ones and call `_deploy_ecs.yml`:

```yaml
# Lambda variant
uses: StackGuardian/sg-internal-github-actions/.github/workflows/_deploy_lambda.yml@main
with:
  ...
  ecr-repo: "{{ECR_REPO}}"
  function-name: "{{FUNCTION_NAME}}"
  image-tag: ${{ inputs.image-tag }}

# ECS variant
uses: StackGuardian/sg-internal-github-actions/.github/workflows/_deploy_ecs.yml@main
with:
  ...
  ecr-repo: "{{ECR_REPO}}"
  image-tag: ${{ inputs.image-tag }}
  ecs-cluster: ${{ inputs.ecs-cluster }}
  ecs-service: ${{ inputs.ecs-service }}
  task-definition: ${{ inputs.task-definition }}
  container-name: ${{ inputs.container-name }}
  environment-variables: ${{ inputs.environment-variables }}
secrets:
  environment-secrets: ${{ secrets.environment-secrets }}
```

ECS `_deploy_*.yml` files also declare these additional `workflow_call` inputs:
- `ecs-cluster` (required, string)
- `ecs-service` (required, string)
- `task-definition` (optional, string)
- `container-name` (optional, string)
- `environment-variables` (optional, string — `KEY=value` lines)

And one secret: `environment-secrets` (optional, masked `KEY=value` lines).

### `build_deploy_qa.yml` and `deploy_prod_*.yml`

For ECS, these entrypoint files pass the full `environment-variables` and `environment-secrets`
blobs to the downstream `_deploy_*.yml` callers. These blobs are project-specific and large —
they contain runtime environment config (feature flags, OIDC issuers, webhook secrets, etc.).

ECS-specific values that are expected to differ between repos (never flag):
- `ecs-cluster`, `ecs-service`, `task-definition`, `container-name`
- `environment-variables` blob
- `environment-secrets` values

## ECS-Specific Review Checks

| Check | Severity | What to look for |
|---|---|---|
| `_deploy_*.yml` calls `_deploy_ecs.yml@main` | CRITICAL | Verify the `@main` pin |
| ECS inputs declared in `_deploy_*.yml` | IMPORTANT | `ecs-cluster`, `ecs-service` must be `required: true` |
| `environment-secrets` declared as secret in `_deploy_*.yml` | IMPORTANT | Should be `required: false` |
| Both accounts correct in `_deploy_qa.yml` / `_deploy_prod.yml` | CRITICAL | `790543352839` vs `476299211833` |
| `deploy-environment` labels | IMPORTANT | `"QA"` and `"PROD"` |

## Note on Per-Region ECS Differences

ECS services may use different environment variable blobs for EU vs US (different OIDC issuers,
webhook secrets, etc.). This is expected and project-specific — do not flag differences between
`deploy_prod_eu.yml` and `deploy_prod_us.yml` ECS config blobs.
