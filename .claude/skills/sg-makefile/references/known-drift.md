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

## DRIFT-6: Deploy `--image-uri` tied to `BUILD_REGION` instead of `DEPLOY_REGION`

**Severity:** CRITICAL
**Applies to:** Lambda/ECS/custom archetype

The old canonical pattern used a single `REGISTRY`/`FULL_IMAGE` derived from
`BUILD_REGION` for both build and deploy. When `deploy-prod-us` overrides
`DEPLOY_REGION=us-east-2`, the `--image-uri` still points at the EU registry, so
the US Lambda is updated with (or fails to find) the EU image URI. In PROD, EU →
US replication makes the image available in the US ECR; the deploy must reference
that US URI.

**Before (drift):**
```makefile
BUILD_REGION ?= eu-central-1
REGISTRY = $(ACCOUNT_ID).dkr.ecr.$(BUILD_REGION).amazonaws.com
IMAGE_NAME ?=
FULL_IMAGE = $(REGISTRY)/$(IMAGE_NAME)
...
deploy:
	@aws --profile $(PROFILE) lambda update-function-code \
		--region $(DEPLOY_REGION) \
		--function-name $(LAMBDA_NAME) \
		--image-uri $(FULL_IMAGE):$(VERSION)
```

**After (canonical):**
```makefile
BUILD_REGION  ?= eu-central-1
DEPLOY_REGION ?= eu-central-1
IMAGE_NAME    ?=

BUILD_REGISTRY  = $(ACCOUNT_ID).dkr.ecr.$(BUILD_REGION).amazonaws.com
DEPLOY_REGISTRY = $(ACCOUNT_ID).dkr.ecr.$(DEPLOY_REGION).amazonaws.com

BUILD_IMAGE  = $(BUILD_REGISTRY)/$(IMAGE_NAME)
DEPLOY_IMAGE = $(DEPLOY_REGISTRY)/$(IMAGE_NAME)
...
build: login
	...
	-t $(BUILD_IMAGE):$(VERSION) .

deploy:
	@aws --profile $(PROFILE) lambda update-function-code \
		--region $(DEPLOY_REGION) \
		--function-name $(LAMBDA_NAME) \
		--image-uri $(DEPLOY_IMAGE):$(VERSION)
```

**Why it matters:** One build pushes to `eu-central-1`; cross-region replication
makes the image available in `us-east-2`. The deploy target must reference the
image URI in the deploy region, not the build region.

---

## DRIFT-7: `deploy:` missing `--profile $(PROFILE)`

**Severity:** CRITICAL
**Applies to:** Lambda/ECS/custom archetype

The `deploy:` recipe runs `aws lambda update-function-code` (or equivalent)
without `--profile $(PROFILE)`, relying on the ambient default AWS profile. When
`deploy-prod-*` is invoked with `PROFILE=sg-prod` via `PROD_VARS`, the variable
is set but never consumed — the command silently runs against whichever profile
is active in the shell.

**Before (drift):**
```makefile
deploy:
	@aws lambda update-function-code \
		--region $(DEPLOY_REGION) \
		...
```

**After (canonical):**
```makefile
deploy:
	@aws --profile $(PROFILE) lambda update-function-code \
		--region $(DEPLOY_REGION) \
		...
```

Applies to all archetype bodies (Lambda, ECS, custom).

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
