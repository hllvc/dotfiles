---
name: review-github-actions
description: Review and align GitHub Actions workflows. Use when user asks to "review github actions", "compare workflows", "align workflows", "check github actions", or needs to audit workflow files for consistency and best practices.
version: 1.0.0
---

# GitHub Actions Workflow Reviewer

Review GitHub Actions workflow files for consistency, best practices, and alignment with reference implementations.

## Workflow

### Step 1: Identify Workflows to Review

Locate all GitHub Actions workflow files:

1. **Current repository**: Search for `.github/workflows/*.yml` files
2. **Reference repository** (if specified): Compare against a reference implementation
3. **Multiple directories**: If comparing branches (e.g., `actions-us`, `actions-eu`)

Use glob patterns:
```
.github/workflows/*.yml
*/.github/workflows/*.yml
```

### Step 2: Read and Analyze Each Workflow

For each workflow file, extract and document:

**Metadata:**
- Workflow name
- Triggers (push, pull_request, workflow_dispatch, etc.)
- Permissions

**Jobs:**
- Job names (IDs)
- Job display names
- Reusable workflow references (`uses:` with external workflows)
- Branch/tag references (`@main`, `@reusable-actions`, etc.)

**Parameters:**
- Input parameter names
- Parameter naming conventions (hyphens vs underscores)
- With/inputs passed to reusable workflows

**Syntax:**
- Quoting consistency around `${{ }}` expressions
- YAML formatting

### Step 3: Generate Comparison Report

Create a structured comparison table:

```markdown
# GitHub Actions Alignment Analysis

## Comparison: {repo-a} vs {repo-b} (reference)

### Summary

{Overall alignment status: fully aligned / partially aligned / misaligned}

---

## Misalignments Found

### 1. {file.yml} - {Issue Category}
| {repo-a} (current) | {repo-b} (reference) |
|--------------------|----------------------|
| `{current-value}`  | `{reference-value}`  |

**Issue:** {Description of the problem}

---

## Expected Differences (Project-Specific)
These differences are expected and correct:
- {List project-specific values like repo names, function names, etc.}

---

## Recommended Fixes

1. **{file.yml}**
   - {Specific change to make}
   - {Line number if known}

---

## Verification
After making changes:
- Validate YAML syntax
- Test with `workflow_dispatch` trigger
- Verify builds and deployments work correctly
```

### Step 4: Check Against Best Practices

Review each workflow against the best practices checklist in `references/best-practices.md`.

Flag issues for:
- Inconsistent quoting
- Missing permissions
- Hardcoded values that should be inputs
- Non-standard branch references
- Parameter naming inconsistencies

## Review Categories

### 1. Reusable Workflow References

Check `uses:` statements for:
- Consistent branch/tag references (prefer `@reusable-actions` over `@main`)
- Correct repository paths
- Version pinning strategy

**Good:**
```yaml
uses: org/repo/.github/workflows/workflow.yml@reusable-actions
```

**Avoid:**
```yaml
uses: org/repo/.github/workflows/workflow.yml@main
```

### 2. Parameter Naming

Enforce consistent naming:
- Use hyphens for multi-word parameters: `deploy-environment`
- Plural for list parameters: `deploy-workflows`
- Singular for single values: `image-tag`

### 3. Quoting Consistency

Always quote `${{ }}` expressions:

**Good:**
```yaml
ecr-repo: "${{ inputs.ecr-repo }}"
image-tag: "${{ inputs.image-tag }}"
```

**Bad:**
```yaml
ecr-repo: ${{ inputs.ecr-repo }}
```

### 4. Job Naming

Job IDs should be descriptive and region-specific when applicable:
- `deploy-us` instead of `deploy` for US deployments
- `deploy-eu` instead of `deploy` for EU deployments
- `build` for build jobs

### 5. Permissions

Ensure minimal required permissions:
```yaml
permissions:
  id-token: write    # For OIDC/JWT
  contents: read     # For checkout
  actions: write     # Only if triggering other workflows
```

## Output Format

When reviewing, always provide:

1. **Summary table** showing alignment status
2. **Detailed findings** with current vs expected values
3. **Recommended fixes** with specific file and line references
4. **Expected differences** to avoid false positives

## Additional Options

If the user specifies:
- `--fix`: Generate edit commands to fix issues
- `--reference <path>`: Compare against specific reference directory
- `--strict`: Flag all deviations including minor style issues
