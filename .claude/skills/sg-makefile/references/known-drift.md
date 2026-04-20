# Known Makefile Drift Patterns

---

## DRIFT-1: Wrong build-secret env var name (`variables-to-jsonschema-lambda`)

**Severity:** CRITICAL

The `build:` target uses `env=GITHUB_TOKEN` instead of `env=GIT_TOKEN`.

**Before (drift):**
```makefile
--secret id=git_token,env=GITHUB_TOKEN \
```

**After (canonical):**
```makefile
--secret id=git_token,env=GIT_TOKEN \
```

**Why it matters:** `GITHUB_TOKEN` is the name of the GitHub-provided automatic token
(available in all GitHub Actions runners). Using it as the env var name for the Docker
build secret creates ambiguity — the Makefile's `GIT_TOKEN` is a PAT for cloning private
repos during the Docker build, which is a completely different credential. The reusable
`_build.yml` workflow passes `GIT_TOKEN` (the repository secret) into Docker under the
`git_token` secret ID — so the Makefile must also reference `GIT_TOKEN`.

---

## DRIFT-2: Hardcoded `eu-central-1` in `login:` private ECR step

**Severity:** MINOR

Both canonical reference Makefiles have this pattern. The private ECR login step
hardcodes the region rather than using `$(BUILD_REGION)`:

**Current (in both real repos — consistent but imprecise):**
```makefile
@aws --profile $(PROFILE) ecr get-login-password --region eu-central-1 \
    | docker login --username AWS --password-stdin $(REGISTRY)
```

**More correct (uses the variable):**
```makefile
@aws --profile $(PROFILE) ecr get-login-password --region $(BUILD_REGION) \
    | docker login --username AWS --password-stdin $(REGISTRY)
```

**Why flagged:** If `BUILD_REGION` is ever overridden (e.g. `make build-dash BUILD_REGION=us-east-1`),
the `login` target would authenticate the wrong region, causing a push failure. In practice
`eu-central-1` is the only build region used, so this is MINOR.
