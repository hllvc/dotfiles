# GitHub Actions Best Practices

## Reusable Workflows

### Branch References

| Pattern | Use Case | Recommendation |
|---------|----------|----------------|
| `@reusable-actions` | Production workflows | Preferred - stable branch |
| `@main` | Development/testing | Avoid in production |
| `@v1.0.0` | Strict version pinning | Use for critical workflows |
| `@sha` | Maximum reproducibility | Use for security-sensitive workflows |

### Organization Standards

For StackGuardian internal workflows:
- Repository: `StackGuardian/sg-internal-github-actions`
- Build workflow: `_reusable_build_ship_workflow.yml`
- Deploy workflow: `_reusable_deploy_workflow.yml`
- Branch: `@reusable-actions`

## Parameter Conventions

### Naming Rules

1. **Use hyphens** for multi-word parameters:
   - `deploy-environment` (not `deploy_environment`)
   - `ecr-repo` (not `ecr_repo`)
   - `image-tag` (not `image_tag`)

2. **Use plural** for list/array parameters:
   - `deploy-workflows` (triggers multiple workflows)
   - `allowed-regions` (list of regions)

3. **Use singular** for single values:
   - `deploy-workflow` (only if truly single)
   - `aws-region`
   - `function-name`

### Common Parameters

| Parameter | Description | Example Value |
|-----------|-------------|---------------|
| `aws-account-id` | AWS account number | `"476299211833"` |
| `aws-region` | AWS region code | `"us-east-2"` |
| `ecr-repo` | ECR repository name | `"ai-assistant"` |
| `function-name` | Lambda function name | `"ai-assistant"` |
| `deploy-environment` | Target environment | `"QA"`, `"PROD"` |
| `image-tag` | Docker image tag | `"${{ inputs.image-tag }}"` |
| `build-context` | Docker build context | `"./src"`, `"."` |

## Quoting Standards

### Always Quote Expressions

```yaml
# Correct
ecr-repo: "${{ inputs.ecr-repo }}"
image-tag: "${{ inputs.image-tag }}"
function-name: "${{ inputs.function-name }}"

# Incorrect
ecr-repo: ${{ inputs.ecr-repo }}
```

### Quote Static Strings

```yaml
# Correct
aws-account-id: "476299211833"
aws-region: "us-east-2"
deploy-environment: "PROD"

# Also acceptable (but less consistent)
aws-region: us-east-2
```

## Job Naming

### Job IDs

Use descriptive, region-specific job IDs:

```yaml
jobs:
  build:           # Generic build job
  deploy-us:       # US deployment
  deploy-eu:       # EU deployment
  deploy-euc1:     # EU Central 1 specific
  deploy-euw1:     # EU West 1 specific
```

### Job Display Names

```yaml
jobs:
  deploy-us:
    name: "Deploy US"
  deploy-eu:
    name: "Deploy EU"
```

## Permissions

### Minimal Permissions

Only request what's needed:

```yaml
permissions:
  id-token: write   # Required for OIDC authentication
  contents: read    # Required for actions/checkout
  actions: write    # Only if triggering other workflows
```

### Permission Inheritance

When using `secrets: inherit`, ensure parent workflow has appropriate permissions.

## Triggers

### Workflow Dispatch

Always include for manual triggering:

```yaml
on:
  workflow_dispatch:
    inputs:
      ecr-repo:
        required: true
        type: string
        description: "ECR repository"
```

### Push Triggers

Comment out if not needed for automatic builds:

```yaml
on:
  workflow_dispatch:
  # push:
  #   branches:
  #     - main
```

## Environment-Specific Settings

### QA vs Production

| Setting | QA | Production |
|---------|-----|------------|
| AWS Account | `790543352839` | `476299211833` |
| Environment | `"QA"` | `"PROD"` |
| Branch reference | Can use `@main` | Must use `@reusable-actions` |

### Regional Deployments

| Region | AWS Region Code | Job ID |
|--------|-----------------|--------|
| US East | `us-east-2` | `deploy-us` |
| EU Central | `eu-central-1` | `deploy-eu` or `deploy-euc1` |
| EU West | `eu-west-1` | `deploy-euw1` |

## File Organization

### Standard Workflow Files

| File | Purpose |
|------|---------|
| `build-qa.yml` | Build and push to QA |
| `build-prod.yml` | Build and push to Production |
| `deploy-qa.yml` | Deploy to QA environment |
| `deploy-prod-us.yml` | Deploy to US production |
| `deploy-prod-eu.yml` | Deploy to EU production |

### Naming Convention

- Use hyphens in filenames
- Include environment: `qa`, `prod`
- Include region for deploy files: `us`, `eu`
