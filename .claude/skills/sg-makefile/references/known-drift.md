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
`VERSION` with `git describe --always --dirty --exclude '*'`.

**Before (drift):**
```makefile
TAG ?= $(shell git rev-parse --short HEAD)
```

**After (canonical):**
```makefile
# Tags are ignored: these are branch builds, and template tags (e.g. kubernetes/v1.4.0) are not valid image tags
VERSION ?= $(shell git describe --always --dirty --exclude '*')
```

**Why it matters:** Makefile builds are branch builds, so the version is the short
commit hash plus a `-dirty` suffix for uncommitted changes (e.g. `abcdef1-dirty`).
`git rev-parse --short HEAD` gives the hash but no dirty indicator, so a locally
modified image is indistinguishable from a clean one. Tags are deliberately
ignored — see DRIFT-10.

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

The private ECR login step hardcodes the region instead of using `$(BUILD_REGION)`.

**Before (drift):**
```makefile
@aws --profile $(PROFILE) ecr get-login-password --region eu-central-1 \
    | docker login --username AWS --password-stdin $(BUILD_REGISTRY)
```

**After (canonical):**
```makefile
@aws --profile $(PROFILE) ecr get-login-password --region $(BUILD_REGION) \
    | docker login --username AWS --password-stdin $(BUILD_REGISTRY)
```

**Why it matters:** `BUILD_REGION` defaults to `eu-central-1` (nonprod and EU prod; the US
prod deploy uses `DEPLOY_REGION=us-east-2` with the replicated image), so in normal use the
two agree. If `BUILD_REGION` is overridden, a hardcoded login authenticates the wrong
registry and the push fails.

---

## DRIFT-8: `build:` does not guard `GIT_TOKEN`

**Severity:** IMPORTANT
**Applies to:** any archetype whose `build:` passes `--secret id=git_token,env=GIT_TOKEN`

The build passes the `git_token` BuildKit secret without first checking that
`GIT_TOKEN` is exported. When it is unset, BuildKit happily mounts an empty
secret and the failure surfaces much later, as an authentication error from
`git clone` / `uv sync` inside the Docker build — several minutes in, with a
message that points at the dependency rather than the missing credential.

**Before (drift):**
```makefile
build: login
	@echo "Building and pushing image: $(BUILD_IMAGE):$(VERSION)"
	@docker buildx build \
		-f $(DOCKERFILE) $(DOCKER_BUILD_ARGS) \
		--secret id=git_token,env=GIT_TOKEN \
		...
```

**After (canonical):**
```makefile
build: login
	@if [ -z "$$GIT_TOKEN" ]; then \
		echo "GIT_TOKEN is not set — export a GitHub PAT with read access to the private deps"; \
		exit 1; \
	fi
	@echo "Building and pushing image: $(BUILD_IMAGE):$(VERSION) (+ :latest)"
	@docker buildx build \
		-f $(DOCKERFILE) $(DOCKER_BUILD_ARGS) \
		--secret id=git_token,env=GIT_TOKEN \
		...
```

Note `$$GIT_TOKEN` — the guard reads the shell environment, not a make variable.
It runs after `login:` (prerequisites go first), which is fine: ECR auth is a
read-only call. Do not add a separate `check-*` target for this; the canonical
`.PHONY` list stays as-is.

Container archetype: only applies if that Makefile opted into the build secret.

---

## DRIFT-9: `build:` pushes only the version tag, not `latest`

**Severity:** IMPORTANT
**Applies to:** all archetypes

`build:` tags the image with `$(VERSION)` alone. Canonical pushes `latest`
alongside it, in the same `buildx --push` invocation, for **both** DASH and PROD
— each account's registry gets its own `latest` pointing at the newest push to
that account.

**Before (drift):**
```makefile
		-t $(BUILD_IMAGE):$(VERSION) .
```

**After (canonical):**
```makefile
		-t $(BUILD_IMAGE):$(VERSION) \
		-t $(BUILD_IMAGE):latest .
```

Container archetype: use `$(FULL_IMAGE)` instead of `$(BUILD_IMAGE)`.

Deploys still reference `$(DEPLOY_IMAGE):$(VERSION)` — `latest` is a
convenience pointer, never the thing a `deploy:` target ships.

---

## DRIFT-10: `VERSION` uses an unscoped `git describe`

**Severity:** IMPORTANT
**Applies to:** all archetypes

`VERSION` runs `git describe` without `--exclude '*'`, so it picks up the
nearest annotated tag anywhere in the repo.

**Before (drift):**
```makefile
VERSION ?= $(shell git describe --always --dirty)
```

**After (canonical):**
```makefile
# Tags are ignored: these are branch builds, and template tags (e.g. kubernetes/v1.4.0) are not valid image tags
VERSION ?= $(shell git describe --always --dirty --exclude '*')
```

**Why it matters:** Makefile builds are branch builds; tags must not leak into
the version. Template release tags are path-scoped (e.g. `kubernetes/v1.4.0`),
so once one exists every template's `make dash` produces something like
`kubernetes/v1.4.0-6-g858e5d1-dirty` — the `/` makes it an invalid Docker image
tag, and a repo-wide describe also labels unrelated templates with another
template's release. `--exclude '*'` keeps the output at `<short-hash>` or
`<short-hash>-dirty`. `make dash VERSION=...` still overrides it; prod images
come from CI on `<template>/v*` tag pushes, not from this line.
