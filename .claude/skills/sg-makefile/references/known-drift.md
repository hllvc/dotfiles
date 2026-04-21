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

## DRIFT-3: Container archetype — `TAG` instead of `VERSION`

**Severity:** IMPORTANT  
**Applies to:** container archetype

Uses `TAG` as the version variable with `git rev-parse --short HEAD` instead of
`VERSION` with `git describe --always --dirty`.

**Before (drift):**
```makefile
TAG ?= $(shell git rev-parse --short HEAD)
```

**After (canonical):**
```makefile
VERSION ?= $(shell git describe --always --dirty)
```

**Why it matters:** `git describe --always --dirty` produces meaningful version strings
(e.g. `v1.2.3-4-gabcdef-dirty`) that make it easy to trace a running container back
to its source tag. `git rev-parse --short HEAD` produces a bare hash with no tag
context and no dirty indicator.

---

## DRIFT-4: Container archetype — `REGISTRY` hardcodes `eu-central-1`

**Severity:** MINOR  
**Applies to:** container archetype

`REGISTRY` and/or the `login:` target hardcode `eu-central-1` instead of using
`$(BUILD_REGION)`.

**Before (drift):**
```makefile
REGISTRY = $(ACCOUNT_ID).dkr.ecr.eu-central-1.amazonaws.com
...
@aws --profile $(PROFILE) ecr get-login-password --region eu-central-1 \
```

**After (canonical):**
```makefile
BUILD_REGION ?= eu-central-1
REGISTRY = $(ACCOUNT_ID).dkr.ecr.$(BUILD_REGION).amazonaws.com
...
@aws --profile $(PROFILE) ecr get-login-password --region $(BUILD_REGION) \
```

---

## DRIFT-5: Container archetype — `DOCKER_BUILD_ARGS` missing `--provenance=false`

**Severity:** IMPORTANT  
**Applies to:** container archetype

`DOCKER_BUILD_ARGS` omits `--provenance=false`, causing Docker BuildKit to attach
OCI provenance attestations to the manifest. Some ECR configurations and older
container runtimes do not handle multi-platform manifest lists with attestations
correctly, which can cause image pull failures.

**Before (drift):**
```makefile
DOCKER_BUILD_ARGS = --push --pull --platform $(PLATFORM)
```

**After (canonical):**
```makefile
DOCKER_BUILD_ARGS = --push --pull --platform $(PLATFORM) --provenance=false
```

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
