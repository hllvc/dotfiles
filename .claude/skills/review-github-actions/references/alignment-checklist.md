# GitHub Actions Alignment Checklist

Use this checklist when comparing workflows across repositories or environments.

## Pre-Review Setup

- [ ] Identify the reference repository/branch
- [ ] List all workflow files in both locations
- [ ] Note project-specific values that should differ

## Reusable Workflow References

- [ ] All `uses:` statements reference `@reusable-actions` (not `@main`)
- [ ] Repository paths are correct: `StackGuardian/sg-internal-github-actions`
- [ ] Workflow filenames match: `_reusable_build_ship_workflow.yml`, `_reusable_deploy_workflow.yml`

## Parameter Names

- [ ] `deploy-workflows` (plural) for triggering multiple deploy workflows
- [ ] Consistent hyphen usage (not underscores)
- [ ] Parameter names match what reusable workflow expects

## Quoting

- [ ] All `${{ inputs.* }}` expressions are quoted
- [ ] All `${{ secrets.* }}` expressions are quoted
- [ ] Static string values are quoted

## Job Configuration

- [ ] Job IDs are region-specific: `deploy-us`, `deploy-eu`
- [ ] Job names match convention: `"Deploy US"`, `"Deploy EU"`
- [ ] Job dependencies (`needs:`) are correct

## Permissions

- [ ] `id-token: write` for OIDC
- [ ] `contents: read` for checkout
- [ ] `actions: write` only when triggering other workflows
- [ ] `secrets: inherit` when needed

## Triggers

- [ ] `workflow_dispatch` is enabled
- [ ] Push triggers are intentionally enabled/disabled
- [ ] Branch filters are correct

## Project-Specific Values (Expected to Differ)

These should differ between projects:

| Parameter | Notes |
|-----------|-------|
| `ecr-repo` | Repository-specific ECR name |
| `function-name` | Lambda function name |
| `build-context` | Docker build context path |
| `dotenv` | Environment file path |
| `additional_repo` | Auxiliary repositories |
| `pipfile` | Python dependencies |

## Common Issues to Flag

### Critical (Must Fix)

1. Wrong branch reference (`@main` instead of `@reusable-actions`)
2. Misspelled parameter names
3. Missing required permissions
4. Incorrect AWS account IDs

### Important (Should Fix)

1. Inconsistent quoting
2. Generic job IDs (`deploy` instead of `deploy-us`)
3. Parameter naming inconsistency

### Minor (Nice to Have)

1. Comment formatting
2. Whitespace consistency
3. Parameter ordering

## Post-Review Actions

- [ ] Generate fix recommendations
- [ ] Validate YAML syntax after changes
- [ ] Test with `workflow_dispatch`
- [ ] Verify deployments work correctly
