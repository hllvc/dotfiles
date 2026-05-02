# Makefile Review Checklist

## CRITICAL — Fix immediately

- [ ] `PLATFORM = linux/amd64` (not `linux/arm64` or any other value)
- [ ] Build secret uses `env=GIT_TOKEN` (not `env=GITHUB_TOKEN` or any other name)
      Full line: `--secret id=git_token,env=GIT_TOKEN \`
- [ ] `DASH_ACCOUNT_ID = 790543352839`
- [ ] `PROD_ACCOUNT_ID = 476299211833`
- [ ] `deploy:` recipe includes `--profile $(PROFILE)` on the `aws` command (DRIFT-7)
- [ ] Registry/image split: `BUILD_REGISTRY`/`BUILD_IMAGE` use `$(BUILD_REGION)`,
      `DEPLOY_REGISTRY`/`DEPLOY_IMAGE` use `$(DEPLOY_REGION)`. `build:` tags with
      `$(BUILD_IMAGE)`; `deploy:` uses `--image-uri $(DEPLOY_IMAGE):$(VERSION)`.
      Flag any Makefile still using a single `REGISTRY`/`FULL_IMAGE` derived from
      `BUILD_REGION` for the deploy URI (DRIFT-6).

## IMPORTANT — Fix soon

- [ ] Section order: `General → DASH → PROD → PROD EU → PROD US → PROD All Regions`
- [ ] All 15 targets present in `.PHONY`:
      `help version login build deploy build-dash deploy-dash build-deploy-dash build-prod deploy-prod-eu build-deploy-prod-eu deploy-prod-us build-deploy-prod-us deploy-prod-all build-deploy-prod-all`
- [ ] `DASH_PROFILE = default`
- [ ] `PROD_PROFILE = sg-prod`
- [ ] `BUILD_REGION ?= eu-central-1` (must be `?=` not `=`)
- [ ] `DEPLOY_REGION ?= eu-central-1` (must be `?=`)
- [ ] `deploy-prod-us` overrides `DEPLOY_REGION=us-east-2`
- [ ] `DOCKER_BUILD_ARGS = --push --pull --platform $(PLATFORM) --provenance=false`
- [ ] `VERSION ?= $(shell git describe --always --dirty)` (must be `?=`)

## MINOR — Nice to have

- [ ] `login` target: the private ECR login hardcodes `eu-central-1` instead of `$(BUILD_REGION)`.
      Both canonical repos have this; it means `BUILD_REGION` overrides don't affect login.
      Flag for awareness — not a bug in standard usage since `eu-central-1` is the only build region.
- [ ] `login:` → the first `docker login` authenticates ECR public (`public.ecr.aws`)
      using `--region us-east-1` (ECR public is always us-east-1 — this is correct)
- [ ] `build-deploy-dash` uses a single `$(MAKE) build deploy $(DASH_VARS)` call (two goals in one sub-make)
      while `build-deploy-prod-us` uses `&&`-chained sub-makes — inconsistent idiom, though both work.

---

## Container archetype checklist

Use this section when the Makefile has **no `deploy:` target** and **no `build-deploy-*`
targets** — i.e., it is a workflow-step / runtime container Makefile.

Do NOT flag: missing `deploy:`, missing PROD US targets, missing `git_token` build
secret, missing `build-deploy-*` targets, missing `LAMBDA_NAME` / `DEPLOY_REGION`.

### CRITICAL

- [ ] `PLATFORM = linux/amd64`
- [ ] `DASH_ACCOUNT_ID = 790543352839`
- [ ] `PROD_ACCOUNT_ID = 476299211833`

### IMPORTANT

- [ ] `DASH_PROFILE = default`
- [ ] `PROD_PROFILE = sg-prod`
- [ ] `VERSION ?= $(shell git describe --always --dirty)` (flag `TAG` as drift)
- [ ] `BUILD_REGION ?= eu-central-1` (must be `?=`)
- [ ] `DOCKER_BUILD_ARGS` includes `--provenance=false`
- [ ] `.PHONY` contains exactly: `help version login build dash prod`
- [ ] No `latest` tag in `build:` recipe (ambiguous for runtime-pulled images)
- [ ] `login:` authenticates **public ECR** (`aws ecr-public get-login-password
      --region us-east-1 | docker login ... public.ecr.aws`) **before** the
      private-registry login. CRITICAL when any `Dockerfile*` in the repo has a
      `FROM public.ecr.aws/...` line (build will fail without it). IMPORTANT
      otherwise — keep for parity with Lambda/ECS canonical.

### MINOR

- [ ] `REGISTRY` uses `$(BUILD_REGION)` instead of hardcoded `eu-central-1`
- [ ] `login` uses `$(BUILD_REGION)` (not hardcoded `eu-central-1`)

### Expected differences (container — never flag)

| Field | Notes |
|---|---|
| `SERVICE_NAME` | In header comment; varies by repo |
| `IMAGE_NAME` | Varies — e.g. `workflow-steps/kubernetes` |
| `--secret id=git_token,env=GIT_TOKEN` | Omitted by default; only needed if Dockerfile clones private repos |

---

## Expected differences (project-specific — never flag)

| Field | Notes |
|---|---|
| `SERVICE_NAME` | In header comment; varies by service |
| `DASH_IMAGE` / `DASH_LAMBDA` | Service-specific ECR and function names |
| `PROD_IMAGE` / `PROD_LAMBDA` | May differ from DASH names |
| `deploy:` recipe body | Lambda vs ECS vs custom |
| Presence of `--secret` line in `build:` | Some services may not need git_token |
