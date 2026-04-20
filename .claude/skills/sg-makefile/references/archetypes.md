# Deploy Archetype Bodies

Use these as the `{{DEPLOY_BODY}}` substitution in `canonical-template.md`.

---

## Lambda (default)

```makefile
deploy:
	@aws lambda update-function-code \
		--region $(DEPLOY_REGION) \
		--function-name $(LAMBDA_NAME) \
		--image-uri $(FULL_IMAGE):$(VERSION)
```

---

## ECS

Replaces the Lambda function update with an ECS force-new-deployment.
The cluster and service name are typically environment-specific; use variables.

```makefile
ECS_CLUSTER ?=
ECS_SERVICE ?=

deploy:
	@aws ecs update-service \
		--region $(DEPLOY_REGION) \
		--cluster $(ECS_CLUSTER) \
		--service $(ECS_SERVICE) \
		--force-new-deployment
```

For ECS, also add `ECS_CLUSTER` and `ECS_SERVICE` to the DASH_VARS and PROD_VARS aggregates,
and set their concrete values in the DASH/PROD configuration sections.

---

## Custom

When the user provides their own deploy command, insert it as the recipe body.
The following variables are available:

| Variable | Value |
|---|---|
| `$(DEPLOY_REGION)` | AWS region (default `eu-central-1`, overridable) |
| `$(LAMBDA_NAME)` | Service/function name (set via DASH_VARS / PROD_VARS) |
| `$(FULL_IMAGE)` | Full ECR image URI |
| `$(VERSION)` | Image tag (git describe output) |
| `$(PROFILE)` | AWS profile (set via DASH_VARS / PROD_VARS) |
| `$(ACCOUNT_ID)` | AWS account ID (set via DASH_VARS / PROD_VARS) |

Example custom body:
```makefile
deploy:
	@aws s3 cp dist/ s3://my-bucket/$(VERSION)/ --recursive
```
