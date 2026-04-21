# Canonical Container Makefile Template

Use this template for workflow-step / runtime containers — images that are built
and pushed to ECR but never deployed directly (the workflow engine pulls them at
runtime). No `deploy:` targets.

Replace `{{PLACEHOLDERS}}` with project-specific values.
All recipe lines use **tabs** (not spaces) — preserved by the Write tool.

Placeholders:
- `{{SERVICE_NAME}}` — service slug for the header comment (e.g. `kubernetes`)
- `{{IMAGE_NAME}}` — ECR image path, same for DASH and PROD (e.g. `workflow-steps/kubernetes`)

---

```makefile
# Makefile for building and pushing Docker images
# StackGuardian Workflow Step: {{SERVICE_NAME}}

# Default version - can be overridden: make dash VERSION=1.2.3
VERSION ?= $(shell git describe --always --dirty)

# Registry and image configuration
BUILD_REGION ?= eu-central-1
IMAGE_NAME = {{IMAGE_NAME}}
REGISTRY = $(ACCOUNT_ID).dkr.ecr.$(BUILD_REGION).amazonaws.com
FULL_IMAGE = $(REGISTRY)/$(IMAGE_NAME)

# Docker build configuration
PLATFORM = linux/amd64
DOCKERFILE = Dockerfile
DOCKER_BUILD_ARGS = --push --pull --platform $(PLATFORM) --provenance=false

# AWS account IDs
DASH_ACCOUNT_ID = 790543352839
PROD_ACCOUNT_ID = 476299211833

# AWS profiles
DASH_PROFILE = default
PROD_PROFILE = sg-prod

# Dynamic variables (set per target)
PROFILE ?=
ACCOUNT_ID ?=

.PHONY: help version login build dash prod

##@ General
help: ## Show this help message
	@echo 'Usage: make <target>'
	@echo ''
	@awk 'BEGIN {FS = ":.*##"; printf ""} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2} /^##@/ {printf "\n\033[1m%s\033[0m\n", substr($$0, 5)}' $(MAKEFILE_LIST)

version: ## Show current version
	@echo $(VERSION)

login:
	@echo "Logging into ECR using profile: $(PROFILE)..."
	@aws --profile $(PROFILE) ecr get-login-password --region $(BUILD_REGION) \
		| docker login --username AWS --password-stdin $(REGISTRY)

build: login ## Build and push Docker image
	@echo "Building and pushing image: $(FULL_IMAGE):$(VERSION)"
	@docker buildx build \
		-f $(DOCKERFILE) $(DOCKER_BUILD_ARGS) \
		-t $(FULL_IMAGE):$(VERSION) .
	@echo "Build completed: $(FULL_IMAGE):$(VERSION)"

##@ DASH
dash: PROFILE=$(DASH_PROFILE)
dash: ACCOUNT_ID=$(DASH_ACCOUNT_ID)
dash: build ## Build and push to DASH

##@ PROD
prod: PROFILE=$(PROD_PROFILE)
prod: ACCOUNT_ID=$(PROD_ACCOUNT_ID)
prod: build ## Build and push to PROD
```

---

## Notes

- No `deploy:` target — these images are consumed by the StackGuardian runtime.
- No `git_token` build secret by default; add `--secret id=git_token,env=GIT_TOKEN \`
  to the `build:` recipe if the `Dockerfile` clones private repos.
- `latest` tag is intentionally omitted. The workflow engine references images
  by version tag; tagging `latest` adds ambiguity.
- `IMAGE_NAME` uses `=` (not `?=`) because each container repo has exactly one
  image path — it is not meant to be overridden at call time.
