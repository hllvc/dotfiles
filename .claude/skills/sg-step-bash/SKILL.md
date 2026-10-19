---
name: sg-step-bash
description: Scaffold a new StackGuardian Workflow Step container with Dockerfile, main.sh, schemas, CI/CD workflows, and Makefile. Use when user asks to "create a new workflow step", "scaffold a workflow step container", "new bash workflow step", "sg step bash", or needs a new SG workflow step template.
version: 1.0.0
---

# StackGuardian Workflow Step Container Scaffolder

Scaffold a complete StackGuardian Workflow Step container following established conventions.

## Workflow

### Step 1: Gather Information

Ask the user for all of the following:

1. **Step name / directory** — lowercase, hyphen-separated (e.g., `dns-scanner`). This becomes the directory name under the repo root.
2. **Human-readable description** — short description for README and workflow names (e.g., "DNS Zone Scanner")
3. **Base Docker image** — default: `python:3.14-alpine3.23`
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

RUN apk update && apk upgrade --no-cache \
  && apk add --no-cache bash jq curl ca-certificates git{{EXTRA_APK_PACKAGES}}{{BUILD_DEPS_BLOCK}}{{PIP_INSTALL_BLOCK}}{{BUILD_DEPS_CLEANUP}} \
  && rm -rf /var/cache/apk/*

COPY main.sh ./

ENTRYPOINT ["/usr/bin/env", "bash"]
CMD ["main.sh"]
```

**Template notes:**

- Everything goes in a **single `RUN` layer** — apk update/upgrade, apk add, optional build-deps, optional pip install, cleanup.
- `{{EXTRA_APK_PACKAGES}}` — if extra apk packages specified, append each on the same line (e.g., ` openssl sshpass`). If none, end at `git`.
- `{{BUILD_DEPS_BLOCK}}` — only when pip packages need native compilation. Insert: ` \` + newline + `  && apk add --no-cache --virtual build-deps build-base gcc openssl-dev libffi-dev`. If not needed, omit entirely.
- `{{PIP_INSTALL_BLOCK}}` — if pip packages specified, insert: ` \` + newline + `  && pip install --no-cache-dir {{PIP_PACKAGES}}`. If none, omit entirely.
- `{{BUILD_DEPS_CLEANUP}}` — if build-deps were added, insert: ` \` + newline + `  && apk del build-deps`. If no build-deps, omit.
- Always end the `RUN` chain with `&& rm -rf /var/cache/apk/*`.
- No `SHELL` directive, no non-root user, no `chmod` on main.sh.

---

#### `{step-name}/main.sh`

Generate this file with the **exact** logging functions below. Do not modify them.

```bash
#!/usr/bin/env bash

set -e
set -o pipefail

# Directory variables
declare CWD=""       # Working directory (where source code is located)
declare ARTIFACTS="" # Directory for outputs/artifacts

# Input variables
declare STEP_INPUTS=""     # Base inputs from the workflow step configuration
declare TEMPLATE_INPUTS="" # Additional inputs from the IaC template configuration

#{{{ LOGGING
declare -A C=( #{{{ Print Colors
  [red]="\u001b[31m"
  [green]="\u001b[32m"
  [yellow]="\u001b[33m"
  [cyan]="\u001b[36m"
  [reset]="\u001b[0m"
)
#}}}

_color_print_prefix() { #{{{
  local color="$1"
  local prefix="${2:-"::"}"

  printf "${C[$color]}%s${C[reset]}" "$prefix"
}
#}}}: _color_print_prefix

_err() { #{{{
  local msg="$1"
  local prefix=""
  local color="red"

  prefix="$(_color_print_prefix "$color")"
  printf "%s %s\n" "$prefix" "$msg" >&2
}
#}}}: _err

_info() { #{{{
  local msg="$1"
  local prefix=""
  local color="green"

  prefix="$(_color_print_prefix "$color")"
  printf "%s %s\n" "$prefix" "$msg"
}
#}}}: _info

_warn() { #{{{
  local msg="$1"
  local prefix=""
  local color="yellow"

  prefix="$(_color_print_prefix "$color" "WARNING:")"
  printf "%s %s\n" "$prefix" "$msg"
}
#}}}: _warn

_debug() { #{{{
  local msg="$1"
  local prefix=""
  local color="cyan"

  prefix="$(_color_print_prefix "$color" "[SG_DEBUG]")"
  printf "%s %s\n" "$prefix" "$msg"
}
#}}}: _debug

_cmd_info() { #{{{
  local msg="$1"
  local prefix=""
  local prefix_color="cyan"
  local cmd_sign=""
  local cmd_sign_color="green"

  prefix="$(_color_print_prefix "$prefix_color" "Executing:")"
  cmd_sign="$(_color_print_prefix "$cmd_sign_color" "$")"

  printf "%s\n" "$prefix"
  printf "%s %s\n\n" "$cmd_sign" "$msg"
}
#}}}: _cmd_info
#}}}: LOGGING

_parse_variables() { #{{{
  # The .env file is only available during runtime and not lint time.
  # Guard the loading of .env to avoid issues during linting when the file is not present.
  # shellcheck disable=SC1091
  [[ -f .env ]] && . .env

  # Helper function to decode base64 variables
  _decode() { #{{{
    local _var_name="$1"
    local _var_value="${!_var_name}"
    if [[ -n "${_var_value}" ]]; then
      echo "${_var_value}" | base64 -d -i
    fi
  }
  #}}}: _decode

  # Input variables
  STEP_INPUTS="$(_decode "BASE64_WORKFLOW_STEP_INPUT_VARIABLES")"
  TEMPLATE_INPUTS="$(_decode "BASE64_IAC_INPUT_VARIABLES")"

  # Directory variables
  CWD="${LOCAL_IAC_SOURCE_CODE_DIR}"
  ARTIFACTS="${LOCAL_ARTIFACTS_DIR}"
}
#}}}: _parse_variables

_get_input() { #{{{
  local _key="$1"
  local _flag="${2:--r}"

  echo "$STEP_INPUTS" | jq "$_flag" --arg key "$_key" ".[\$key] // empty"
}
#}}}: _get_input

main() { #{{{
  _parse_variables

  _info "Starting {{STEP_DESCRIPTION}}"

  # TODO: Extract step-specific parameters using _get_input
  # Example: local _my_param="$(_get_input "myParam")"

  # TODO: Implement step-specific logic here

  _info "{{STEP_DESCRIPTION}} completed successfully"
}
#}}}: main

main "$@"
```

**Template notes:**

- Replace `{{STEP_DESCRIPTION}}` with the human-readable description the user provided.
- The logging functions, `_parse_variables`, and `_get_input` must be copied **verbatim** from the template above. Do not modify indentation, fold markers, or function signatures.
- `_err()` only prints to stderr — it does **not** exit. Use `_err "message" && exit 1` at call sites when you need to abort.

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

Example (illustrative — the shape follows the existing step schemas in `workflow-step-templates`):

```json
{
  "type": "object",
  "title": "",
  "required": ["action"],
  "properties": {
    "targetPath": { "type": "string", "title": "Target Path", "default": "./" },
    "action": {
      "type": "string",
      "title": "Action",
      "enum": ["plan", "apply"],
      "enumNames": ["Plan only", "Apply"],
      "default": "plan"
    },
    "dryRun": { "type": "boolean", "title": "Dry Run", "default": false },
    "sourceType": { "type": "string", "title": "Source", "enum": ["file", "script"], "default": "file" }
  },
  "dependencies": {
    "sourceType": {
      "oneOf": [
        {
          "properties": {
            "sourceType": { "enum": ["file"] },
            "sourceFile": { "type": "string", "title": "Source File" }
          }
        },
        {
          "properties": {
            "sourceType": { "enum": ["script"] },
            "sourceScript": { "type": "string", "title": "Source Script" }
          },
          "required": ["sourceScript"]
        }
      ]
    }
  }
}
```

Conventions:

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
| --------- | ---- | -------- | ------- | ----------- |

{{PARAMETER_TABLE_ROWS}}

## Environment Variables

| Variable                               | Description                             |
| -------------------------------------- | --------------------------------------- |
| `LOCAL_IAC_SOURCE_CODE_DIR`            | Path to checked out VCS repository      |
| `LOCAL_ARTIFACTS_DIR`                  | Path to artifacts/outputs directory     |
| `BASE64_WORKFLOW_STEP_INPUT_VARIABLES` | Base64-encoded workflow step parameters |
| `BASE64_IAC_INPUT_VARIABLES`           | Base64-encoded IaC input variables      |
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
      - "{{STEP_NAME}}-v*"

permissions:
  id-token: write # This is required for requesting the JWT
  contents: read # This is required for actions/checkout
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

      deploy-environment: "BUILD"
      build-context: "./{{STEP_NAME}}"
      tag-match: "{{STEP_NAME}}-v(.*)"
```

**Template notes:**

- `{{DISPLAY_NAME}}` — the human-readable description (e.g., "DNS Scanner")
- `{{STEP_NAME}}` — the directory name (e.g., `dns-scanner`)
- `{{ECR_REPO}}` — the ECR repo path (e.g., `workflow-steps/dns-scanner`)
- Prod builds run on the ungated `BUILD` environment: approval gates deploys (Lambda/ECS updates), and a step container has none.
- `tag-match` extracts the version from the step-scoped tag (`dns-scanner-v1.2.0` → `1.2.0`); the default `v(.*)` would mis-read step names containing a `v`.

---

### Step 4: Generate Makefile

Create `{step-name}/Makefile` from the sg-makefile skill's container template,
`~/.claude/skills/sg-makefile/references/canonical-container-template.md` (the single source for
container Makefiles). Substitute `{{SERVICE_NAME}}` with the step name and `{{IMAGE_NAME}}` with the
ECR repo path from Step 1 (e.g., `workflow-steps/dns-scanner`). Targets: `make dash`, `make prod`.

- No `git_token` secret by default. If the Dockerfile clones private repos, add the secret line and the `GIT_TOKEN` guard as that template's Notes describe.
- No deploy targets — workflow step containers are only built and pushed to ECR. If the user explicitly requests deploy targets, follow the `/sg-makefile` skill's Lambda/ECS/custom archetype.
- All recipe lines **must** use tabs for indentation (Makefile requirement).

---

## Important Conventions

- The Dockerfile must NOT include any hardening blocks (no crontab removal, no suid cleanup, no admin command removal, etc.). Keep it minimal.
- All apk and pip operations are combined into a **single `RUN` layer**, ending with `rm -rf /var/cache/apk/*`.
- Use `ENTRYPOINT ["/usr/bin/env", "bash"]` with `CMD ["main.sh"]` — not a combined `CMD`.
- The `main.sh` logging functions are canonical — copy them exactly from this skill template.
- CI/CD workflows must reference `StackGuardian/sg-internal-github-actions/.github/workflows/_build.yml@main` — not a pinned SHA.
- QA account: `790543352839`, Prod account: `476299211833`
- File indentation: 2 spaces for YAML, JSON, Dockerfile. Tabs for Makefile recipes only.
