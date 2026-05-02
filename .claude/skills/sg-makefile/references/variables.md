# Fixed Variables and Constants

These values are canonical — deviations are drift.

## AWS Accounts and Profiles

| Environment | Account ID | AWS Profile |
|---|---|---|
| DASH (QA/dev) | `790543352839` | `default` |
| PROD | `476299211833` | `sg-prod` |

## Regions

| Use | Region |
|---|---|
| `BUILD_REGION` default (ECR push) | `eu-central-1` |
| `DEPLOY_REGION` default | `eu-central-1` |
| PROD US override | `us-east-2` |
| ECR-public login (always) | `us-east-1` |

`BUILD_REGION` and `DEPLOY_REGION` must be independent. The build runs once to
`$(BUILD_REGION)`; cross-region replication publishes the image into
`us-east-2` for the US deploy. The canonical template therefore splits:

- `BUILD_REGISTRY` / `BUILD_IMAGE` — derived from `$(BUILD_REGION)`, used by `build:` and `login:`.
- `DEPLOY_REGISTRY` / `DEPLOY_IMAGE` — derived from `$(DEPLOY_REGION)`, used by `deploy:` (`--image-uri`).

A single `REGISTRY`/`FULL_IMAGE` derived from `BUILD_REGION` is drift (see DRIFT-6).

## Platform

```makefile
PLATFORM = linux/amd64
```

Not `linux/arm64`. All canonical Lambda services use `amd64`.

## Build Secret

```makefile
--secret id=git_token,env=GIT_TOKEN
```

The Docker secret ID is always `git_token`. The env var is always `GIT_TOKEN`
(not `GITHUB_TOKEN` — that name conflicts with the GitHub-provided automatic token).

## Canonical `.PHONY` List

```makefile
.PHONY: help version login build deploy build-dash deploy-dash build-deploy-dash build-prod deploy-prod-eu build-deploy-prod-eu deploy-prod-us build-deploy-prod-us deploy-prod-all build-deploy-prod-all
```

All 15 targets must appear in `.PHONY`.

## Section Order

```
##@ General
##@ DASH
##@ PROD
##@ PROD EU
##@ PROD US
##@ PROD All Regions
```

## DASH_VARS / PROD_VARS Pattern

Each section aggregates 4 `KEY=VALUE` pairs for sub-make:

```makefile
DASH_VARS = PROFILE=$(DASH_PROFILE) ACCOUNT_ID=$(DASH_ACCOUNT_ID) IMAGE_NAME=$(DASH_IMAGE) LAMBDA_NAME=$(DASH_LAMBDA)
PROD_VARS = PROFILE=$(PROD_PROFILE) ACCOUNT_ID=$(PROD_ACCOUNT_ID) IMAGE_NAME=$(PROD_IMAGE) LAMBDA_NAME=$(PROD_LAMBDA)
```

Per-env targets are thin wrappers: `$(MAKE) <target> $(<ENV>_VARS)`.

## awk Help Printer

The exact awk command for the `help:` target:

```makefile
@awk 'BEGIN {FS = ":.*##"; printf ""} /^[a-zA-Z_-]+:.*?## / {printf "  %-24s %s\n", $$1, $$2} /^##@/ {printf "\n\033[1m%s\033[0m\n", substr($$0, 5)}' $(MAKEFILE_LIST)
```

Targets with `## Description` appear in help output.
Sections with `##@ Section Name` appear as bold headers.
`login`, `build`, and `deploy` intentionally have no `##` doc comment (they are
internal targets; high-level targets like `build-dash` are the user-facing API).
