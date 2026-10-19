# Known Drift Patterns

These patterns have been observed in real repositories. When review mode detects a match,
cite the pattern by name so the user has context.

---

## DRIFT-1: Feature branch pin (`variables-to-jsonschema-lambda`)

**Severity:** CRITICAL

`_deploy_qa.yml` and `_deploy_prod.yml` pin the upstream reusable workflow at a feature branch
instead of `@main`.

**Before (drift):**
```yaml
uses: StackGuardian/sg-internal-github-actions/.github/workflows/_deploy_lambda.yml@feat/reusable-cicd
```

**After (canonical):**
```yaml
uses: StackGuardian/sg-internal-github-actions/.github/workflows/_deploy_lambda.yml@main
```

**Why it matters:** Feature branches are not stable and may be force-pushed or deleted.
All callers must pin `@main`.

---

## DRIFT-2: Non-standard build branch + deploy-environment label (`landfast-infra2code-prototype`)

**Severity:** CRITICAL for the branch pin; IMPORTANT for the label

`build_deploy_qa.yml` pins the `_build.yml` reusable at a feature branch, and
`_deploy_prod.yml` uses `deploy-environment: "PROD_DEPLOY"` instead of `"PROD"`.

**Drift — branch pin (CRITICAL):**
```yaml
# build_deploy_qa.yml
uses: StackGuardian/sg-internal-github-actions/.github/workflows/_build.yml@feat/infra2code-sensitive-env
```

**Canonical:**
```yaml
uses: StackGuardian/sg-internal-github-actions/.github/workflows/_build.yml@main
```

**Drift — deploy-environment label (IMPORTANT):**
```yaml
# _deploy_prod.yml
deploy-environment: "PROD_DEPLOY"
```

**Canonical:**
```yaml
deploy-environment: "PROD"
```

**Note:** `dotenv: ".env.prod"` in this repo is a legitimate project-specific value (not drift) —
`.env.prod` is that repo's filename choice, separate from the `"PROD_DEPLOY"` label issue.

---

## DRIFT-3: Missing deploy-environment in build_prod.yml

**Severity:** IMPORTANT

`build_prod.yml` omits `deploy-environment` entirely. All prod build jobs should
pass `"BUILD"` to map to the ungated GitHub Environment (builds run automatically
on tag push; deploys gate on `"PROD"` in `_deploy_prod.yml`).

**Before (drift):**
```yaml
# build_prod.yml — deploy-environment absent
with:
  aws-account-id: "476299211833"
  ecr-repo: "{{ECR_REPO}}"
```

**After (canonical):**
```yaml
with:
  aws-account-id: "476299211833"
  deploy-environment: "BUILD"
  ecr-repo: "{{ECR_REPO}}"
```

**Why it matters:** Without the label the build runs in an untracked GitHub
Environment. `"BUILD"` is intentionally ungated — `"PROD"` is reserved for the
deploy step which carries approval gates.

---

## DRIFT-4: GitHub OIDC sub claim not customised

**Severity:** CRITICAL

The repo uses the default GitHub OIDC sub claim (`use_default: true` or unconfigured).
Without `environment` in the sub claim, the `BUILD` and `PROD` GitHub Environments cannot
be distinguished in the IAM trust policy, breaking scoped OIDC authentication.

**Detect:**
```bash
gh api /repos/{ORG}/{REPO}/actions/oidc/customization/sub
# Drift:    {"use_default":true}  or  missing "environment" in include_claim_keys
# Canonical: {"use_default":false,"include_claim_keys":["repo","job_workflow_ref","environment"]}
```

**Fix:**
```bash
gh api --method PUT \
  /repos/{ORG}/{REPO}/actions/oidc/customization/sub \
  -F 'use_default=false' \
  -F 'include_claim_keys[]=repo' \
  -F 'include_claim_keys[]=job_workflow_ref' \
  -F 'include_claim_keys[]=environment'
```
