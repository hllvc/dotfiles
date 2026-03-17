---
name: sg-container-bash
description: Scaffold a new StackGuardian Workflow Step container with Dockerfile, main.sh, schemas, CI/CD workflows, and Makefile. Use when user asks to "create a new workflow step", "scaffold container", "sg container bash", or needs a new SG workflow step template.
version: 1.0.0
---

# StackGuardian Workflow Step Container Scaffolder

Scaffold a complete StackGuardian Workflow Step container following established conventions.

## Workflow

### Step 1: Gather Information

Ask the user for all of the following:

1. **Step name / directory** — lowercase, hyphen-separated (e.g., `dns-scanner`). This becomes the directory name under the repo root.
2. **Human-readable description** — short description for README and workflow names (e.g., "DNS Zone Scanner")
3. **Base Docker image** — default: `python:3.12-alpine3.20`
4. **Additional apk packages** — space-separated list beyond the defaults (`bash jq curl ca-certificates git`), or "none"
5. **Additional pip packages** — space-separated list, or "none" (if "none", omit the pip install layer entirely)
6. **ECR repo name** — path under `workflow-steps/` (e.g., `workflow-steps/dns-scanner`)
7. **Input parameters** — for each parameter, ask:
   - key name (camelCase)
   - JSON Schema type (`string`, `boolean`, `number`)
   - title (human-readable label)
   - default value (optional)
   - enum values (optional)
   - whether it is required

### Step 2: Generate Files

Create the following files in `{step-name}/` relative to the repository root.

---

#### `{step-name}/Dockerfile`

```dockerfile
FROM {{BASE_IMAGE}}

SHELL ["/bin/sh", "-o", "pipefail", "-c"]

# hadolint ignore=DL3018
RUN apk add --no-cache \
  bash \
  jq \
  curl \
  ca-certificates \
  git{{EXTRA_APK_PACKAGES}}

{{PIP_INSTALL_BLOCK}}

RUN addgroup -g 911 -S stackguardian \
  && adduser -u 911 -S stackguardian -G stackguardian

COPY main.sh ./
RUN chmod u+r main.sh

USER stackguardian

CMD ["/usr/bin/env", "bash", "main.sh"]
```

**Template notes:**
- `{{EXTRA_APK_PACKAGES}}` — if user specified extra apk packages, append each on its own continuation line (` \` + newline + `  packagename`). If none, end the apk add line at `git`.
- `{{PIP_INSTALL_BLOCK}}` — if user specified pip packages, insert:
  ```dockerfile
  RUN pip install --no-cache-dir {{PIP_PACKAGES}}
  ```
  If no pip packages, omit entirely (no blank RUN line).

---

#### `{step-name}/main.sh`

Generate this file with the **exact** logging functions below. Do not modify them.

```bash
#!/usr/bin/env bash

set -e

declare -A C=(
  [red]="\u001b[31m"
  [green]="\u001b[32m"
  [yellow]="\u001b[33m"
  [blue]="\u001b[34m"
  [magenta]="\u001b[35m"
  [cyan]="\u001b[36m"
  [reset]="\u001b[0m"
)

_color_print_prefix() { #{{{
  local color="$1"
  local prefix="${2:-"::"}"

  printf "${C[$color]}%s${C[reset]}" "$prefix"
}
#}}}: _color_print_prefix

_error() { #{{{
  local msg="$1"
  local prefix="$(_color_print_prefix "red")"

  printf "%s %s\n" "$prefix" "$msg" >&2
  exit 1
}
#}}}: _error

_info() { #{{{
  local msg="$1"
  local prefix="$(_color_print_prefix "green")"

  printf "%s %s\n" "$prefix" "$msg"
}
#}}}: _info

_warn() { #{{{
  local msg="$1"
  local prefix="$(_color_print_prefix "yellow" "!!")"

  printf "%s %s\n" "$prefix" "$msg"
}
#}}}: _warn

_debug() { #{{{
  local msg="$1"
  local prefix="$(_color_print_prefix "cyan" "[SG_DEBUG]")"

  printf "%s %s\n" "$prefix" "$msg"
}
#}}}: _debug

_command_log() { #{{{
  local msg="$1"
  local prefix="$(_color_print_prefix "cyan" "Executing:")"
  local dollarSign="$(_color_print_prefix "green" "$")"

  printf "%s\n%s %s\n\n" "$prefix" "$dollarSign" "$msg"
}
#}}}: _command_log

_parse_variables() { #{{{
  _debug "Parsing workflow variables"
  workingDir="$LOCAL_IAC_SOURCE_CODE_DIR"
  workingDir="${workingDir%/}"  # Remove trailing slash if present
  workflowStepInputParams="$(echo "$BASE64_WORKFLOW_STEP_INPUT_VARIABLES" | base64 -d -i -)"
  workflowIACInputVariables="$(echo "$BASE64_IAC_INPUT_VARIABLES" | base64 -d -i -)"
  _debug "Variables parsed successfully"
}
#}}}: _parse_variables

main() { #{{{
  _info "Starting {{STEP_DESCRIPTION}}"

  _parse_variables

  # TODO: Extract step-specific parameters from workflowStepInputParams
  # Example: myParam="$(echo "$workflowStepInputParams" | jq -r '.myParam // empty')"

  # TODO: Implement step-specific logic here

  _info "{{STEP_DESCRIPTION}} completed successfully"
}
#}}}: main

main "$@"
```

**Template notes:**
- Replace `{{STEP_DESCRIPTION}}` with the human-readable description the user provided.
- The logging functions and `_parse_variables` must be copied **verbatim** from the template above. Do not modify indentation, fold markers, or function signatures.

---

#### `{step-name}/schemas/input_schema.json`

Generate a JSON Schema based on the parameters the user specified:

```json
{
  "type": "object",
  "title": "",
  "required": [{{REQUIRED_FIELDS}}],
  "properties": {
    {{PROPERTIES}}
  }
}
```

Follow the pattern from the kubernetes schema:
- Each property has `type`, `title`, and optionally `default`, `enum`, `enumNames`
- Required fields are listed in the top-level `required` array
- Use `dependencies` for conditional fields if the user specifies any

---

#### `{step-name}/schemas/ui_schema.json`

Generate a UI schema that:
- Has a `ui:order` array listing all property keys in display order
- For `enum` fields, use `"ui:widget": "select"` (or `"radio"` with `"ui:options": {"inline": true}` for short lists)
- For `boolean` fields, use `"ui:widget": "checkbox"`
- For `string` fields, add a `"ui:placeholder"` where appropriate

---

#### `{step-name}/README.md`

```markdown
# {{STEP_DESCRIPTION}}

{{DESCRIPTION_PARAGRAPH}}

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
{{PARAMETER_TABLE_ROWS}}

## Environment Variables

| Variable | Description |
|----------|-------------|
| `LOCAL_IAC_SOURCE_CODE_DIR` | Path to checked out VCS repository |
| `BASE64_WORKFLOW_STEP_INPUT_VARIABLES` | Base64-encoded workflow step parameters |
| `BASE64_IAC_INPUT_VARIABLES` | Base64-encoded IaC input variables |
```

---

### Step 3: Generate CI/CD Workflows

Create two workflow files in `.github/workflows/` at the repository root.

#### `.github/workflows/{step-name}-qa.yml`

```yaml
name: "🛠️ [DASH] {{DISPLAY_NAME}}"

on:
  workflow_dispatch:
  push:
    branches:
      - main
    paths:
      - {{STEP_NAME}}/**

permissions:
  id-token: write # This is required for requesting the JWT
  contents: read  # This is required for actions/checkout
  actions: write # This is required for trigger other GitHub Actions

jobs:
  build:
    name: "Build and Push"
    secrets: inherit

    uses: StackGuardian/sg-internal-github-actions/.github/workflows/_build.yml@main
    with:
      aws-account-id: "790543352839"
      aws-region: "eu-central-1"
      ecr-repo: "{{ECR_REPO}}"

      deploy-environment: "QA"
      build-context: "./{{STEP_NAME}}"
```

#### `.github/workflows/{step-name}-prod.yml`

```yaml
name: "🛠️ [PROD] {{DISPLAY_NAME}}"

on:
  push:
    tags:
      - '{{STEP_NAME}}-v*'

permissions:
  id-token: write # This is required for requesting the JWT
  contents: read  # This is required for actions/checkout
  actions: write # This is required for trigger other GitHub Actions

jobs:
  build:
    name: "Build and Push"
    secrets: inherit

    uses: StackGuardian/sg-internal-github-actions/.github/workflows/_build.yml@main
    with:
      aws-account-id: "476299211833"
      aws-region: "eu-central-1"
      ecr-repo: "{{ECR_REPO}}"

      deploy-environment: "PROD"
      build-context: "./{{STEP_NAME}}"
```

**Template notes:**
- `{{DISPLAY_NAME}}` — the human-readable description (e.g., "DNS Scanner")
- `{{STEP_NAME}}` — the directory name (e.g., `dns-scanner`)
- `{{ECR_REPO}}` — the ECR repo path (e.g., `workflow-steps/dns-scanner`)

---

### Step 4: Delegate Makefile Generation

After generating all files above, invoke the `/sg-makefile` skill to generate a Makefile inside `{step-name}/`. Provide it with:

- **Service name**: the step description
- **DASH configuration**:
  - Account ID: `790543352839`
  - AWS profile: `default`
  - ECR image: `{{ECR_REPO}}`
  - Lambda name: (ask user, or skip if not applicable)
- **PROD configuration**:
  - Account ID: `476299211833`
  - AWS profile: `sg-prod`
  - ECR image: `{{ECR_REPO}}`
  - Lambda name: (ask user, or skip if not applicable)
- **Platform**: `linux/amd64` (workflow steps run on amd64)
- **No git_token secret** unless user specifies otherwise

---

## Important Conventions

- The Dockerfile must NOT include any hardening blocks (no crontab removal, no suid cleanup, no admin command removal, etc.). Keep it minimal.
- The `main.sh` logging functions are canonical — copy them exactly from this skill template.
- CI/CD workflows must reference `StackGuardian/sg-internal-github-actions/.github/workflows/_build.yml@main` — not a pinned SHA.
- QA account: `790543352839`, Prod account: `476299211833`
- The non-root user is always `stackguardian` with UID/GID `911`.
- File indentation: 2 spaces for YAML, JSON, Dockerfile. Tabs for Makefile recipes only.
