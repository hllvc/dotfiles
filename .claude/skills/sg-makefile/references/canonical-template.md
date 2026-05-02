# Canonical Makefile Template

Use this template for setup and update modes. Replace `{{PLACEHOLDERS}}` with project-specific values.
All recipe lines use **tabs** (not spaces) — preserved by the Write tool.

Placeholders:
- `{{SERVICE_NAME}}` — service slug used in the header comment
- `{{DASH_IMAGE}}` — ECR image name for DASH (e.g. `my-service`)
- `{{DASH_LAMBDA}}` — Lambda function name for DASH (e.g. `my-service-lambda`)
- `{{PROD_IMAGE}}` — ECR image name for PROD
- `{{PROD_LAMBDA}}` — Lambda function name for PROD
- `{{DEPLOY_BODY}}` — deploy recipe body from `archetypes.md`

---

```makefile
# Makefile for building and pushing Docker images
# StackGuardian Service: {{SERVICE_NAME}}

# Default version - can be overridden via command line: make dash VERSION=1.2.3
VERSION ?= $(shell git describe --always --dirty)

# Registry and image configuration
BUILD_REGION  ?= eu-central-1
DEPLOY_REGION ?= eu-central-1
IMAGE_NAME    ?=

BUILD_REGISTRY  = $(ACCOUNT_ID).dkr.ecr.$(BUILD_REGION).amazonaws.com
DEPLOY_REGISTRY = $(ACCOUNT_ID).dkr.ecr.$(DEPLOY_REGION).amazonaws.com

BUILD_IMAGE  = $(BUILD_REGISTRY)/$(IMAGE_NAME)
DEPLOY_IMAGE = $(DEPLOY_REGISTRY)/$(IMAGE_NAME)

# Build settings
PLATFORM = linux/amd64
DOCKERFILE = Dockerfile
DOCKER_BUILD_ARGS = --push --pull --platform $(PLATFORM) --provenance=false

# ============================================================================
# DASH Configuration
# ============================================================================
DASH_ACCOUNT_ID = 790543352839
DASH_PROFILE = default
DASH_IMAGE = {{DASH_IMAGE}}
DASH_LAMBDA = {{DASH_LAMBDA}}

# ============================================================================
# PROD Configuration
# ============================================================================
PROD_ACCOUNT_ID = 476299211833
PROD_PROFILE = sg-prod
PROD_IMAGE = {{PROD_IMAGE}}
PROD_LAMBDA = {{PROD_LAMBDA}}

# Dynamic variables
PROFILE ?=
ACCOUNT_ID ?=
LAMBDA_NAME ?=

.PHONY: help version login build deploy build-dash deploy-dash build-deploy-dash build-prod deploy-prod-eu build-deploy-prod-eu deploy-prod-us build-deploy-prod-us deploy-prod-all build-deploy-prod-all

##@ General
help: ## Show this help message
	@echo 'Usage: make <target>'
	@echo ''
	@awk 'BEGIN {FS = ":.*##"; printf ""} /^[a-zA-Z_-]+:.*?## / {printf "  %-24s %s\n", $$1, $$2} /^##@/ {printf "\n\033[1m%s\033[0m\n", substr($$0, 5)}' $(MAKEFILE_LIST)

version: ## Show current version
	@echo $(VERSION)

login:
	@echo "Logging into ECR using profile: $(PROFILE)..."
	@aws --profile $(PROFILE) ecr-public get-login-password --region us-east-1 \
		| docker login --username AWS --password-stdin public.ecr.aws
	@aws --profile $(PROFILE) ecr get-login-password --region eu-central-1 \
		| docker login --username AWS --password-stdin $(BUILD_REGISTRY)

build: login
	@echo "Building and pushing image: $(BUILD_IMAGE):$(VERSION)"
	@docker buildx build \
		-f $(DOCKERFILE) $(DOCKER_BUILD_ARGS) \
		--secret id=git_token,env=GIT_TOKEN \
		-t $(BUILD_IMAGE):$(VERSION) .
	@echo "Build completed: $(BUILD_IMAGE):$(VERSION)"

deploy:
{{DEPLOY_BODY}}

##@ DASH
DASH_VARS = PROFILE=$(DASH_PROFILE) ACCOUNT_ID=$(DASH_ACCOUNT_ID) IMAGE_NAME=$(DASH_IMAGE) LAMBDA_NAME=$(DASH_LAMBDA)

build-dash: ## Build and push DASH image
	$(MAKE) build $(DASH_VARS)

deploy-dash: ## Deploy DASH Lambda
	$(MAKE) deploy $(DASH_VARS)

build-deploy-dash: ## Build and deploy DASH
	$(MAKE) build deploy $(DASH_VARS)

##@ PROD
PROD_VARS = PROFILE=$(PROD_PROFILE) ACCOUNT_ID=$(PROD_ACCOUNT_ID) IMAGE_NAME=$(PROD_IMAGE) LAMBDA_NAME=$(PROD_LAMBDA)

build-prod: ## Build and push PROD image
	$(MAKE) build $(PROD_VARS)

##@ PROD EU
deploy-prod-eu: ## Deploy PROD to EU
	$(MAKE) deploy $(PROD_VARS)

build-deploy-prod-eu: ## Build and deploy PROD EU
	$(MAKE) build deploy $(PROD_VARS)

##@ PROD US
deploy-prod-us: ## Deploy PROD to US
	$(MAKE) deploy $(PROD_VARS) DEPLOY_REGION=us-east-2

build-deploy-prod-us: ## Build and deploy PROD US
	$(MAKE) build $(PROD_VARS) && $(MAKE) deploy $(PROD_VARS) DEPLOY_REGION=us-east-2

##@ PROD All Regions
deploy-prod-all: ## Deploy PROD to all regions
	$(MAKE) deploy-prod-eu
	$(MAKE) deploy-prod-us

build-deploy-prod-all: ## Build and deploy PROD all
	$(MAKE) build-prod
	$(MAKE) deploy-prod-eu
	$(MAKE) deploy-prod-us
```
