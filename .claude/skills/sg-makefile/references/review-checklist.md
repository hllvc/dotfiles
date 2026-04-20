# Makefile Review Checklist

## CRITICAL — Fix immediately

- [ ] `PLATFORM = linux/amd64` (not `linux/arm64` or any other value)
- [ ] Build secret uses `env=GIT_TOKEN` (not `env=GITHUB_TOKEN` or any other name)
      Full line: `--secret id=git_token,env=GIT_TOKEN \`
- [ ] `DASH_ACCOUNT_ID = 790543352839`
- [ ] `PROD_ACCOUNT_ID = 476299211833`

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

## Expected differences (project-specific — never flag)

| Field | Notes |
|---|---|
| `SERVICE_NAME` | In header comment; varies by service |
| `DASH_IMAGE` / `DASH_LAMBDA` | Service-specific ECR and function names |
| `PROD_IMAGE` / `PROD_LAMBDA` | May differ from DASH names |
| `deploy:` recipe body | Lambda vs ECS vs custom |
| Presence of `--secret` line in `build:` | Some services may not need git_token |
