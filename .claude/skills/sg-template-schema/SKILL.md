---
name: sg-template-schema
description: This skill should be used when the user asks to "create template schema", "create nocode form", "nocode form", "sg nocode", "generate schema from variables.tf", "convert terraform to schema", or needs help creating input_schema.json and ui_schema.json for StackGuardian templates.
version: 0.1.0
---

# StackGuardian Template Schema Generator

This skill helps create JSON Schema files (`input_schema.json` and `ui_schema.json`) for StackGuardian no-code forms. The primary use case is converting Terraform `variables.tf` to JSON Schema, but it also supports generic workflow step templates.

## Overview

StackGuardian uses two schema files to generate no-code forms:

1. **input_schema.json** - JSON Schema defining the data structure, types, validation, and defaults
2. **ui_schema.json** - UI configuration defining widgets, placeholders, descriptions, and layout

## Quick Reference: Terraform to JSON Schema

| Terraform Type | JSON Schema |
|----------------|-------------|
| `string` | `"type": "string"` |
| `number` | `"type": "number"` |
| `bool` | `"type": "boolean"` |
| `list(T)` | `"type": "array", "items": {...}` |
| `map(T)` | `"type": "object", "additionalProperties": {...}` |
| `object({...})` | `"type": "object", "properties": {...}` |
| `optional(T, default)` | Field with `"default"` (not in `required`) |

## Required vs Optional Fields

- **Required**: Variables without `default` or `optional()` wrapper
- **Optional**: Variables with `default = value` or using `optional(type, default)`

In JSON Schema:
- Required fields go in the `"required": [...]` array
- Optional fields get a `"default"` value

## Validation Mapping

| Terraform Validation | JSON Schema |
|---------------------|-------------|
| `can(regex("pattern", var.x))` | `"pattern": "pattern"` |
| `contains(["a", "b"], var.x)` | `"enum": ["a", "b"]` |
| `var.x >= N` | `"minimum": N` |
| `var.x <= N` | `"maximum": N` |
| `length(var.x) >= N` | `"minLength": N` |

## Enhanced Input Schema Features

### Title Field
Add `"title"` directly in properties for cleaner display:
```json
"aws_region": {
  "title": "AWS Region",
  "type": "string",
  "enum": ["us-east-1", "eu-central-1"]
}
```

### Enum with Display Names
Use `enumNames` for user-friendly labels while keeping real values:
```json
"api_uri": {
  "type": "string",
  "enum": ["https://api.app.stackguardian.io", "https://api.us.stackguardian.io"],
  "enumNames": ["EU1 - Europe", "US1 - United States"]
}
```

### Conditional Dependencies
Show/hide fields based on boolean toggle:
```json
"dependencies": {
  "create_storage": {
    "oneOf": [
      {
        "properties": {
          "create_storage": { "enum": [true] },
          "storage_size": { "type": "integer" }
        }
      },
      {
        "properties": {
          "create_storage": { "enum": [false] },
          "existing_bucket": { "type": "string" }
        },
        "required": ["existing_bucket"]
      }
    ]
  }
}
```

### Conditional Fields with allOf/if-then
Show/hide fields based on enum selection (e.g., OS family):
```json
"os": {
  "type": "object",
  "required": ["family"],
  "allOf": [
    {
      "if": { "properties": { "family": { "const": "amazon" } } },
      "then": {
        "properties": {
          "family": { "type": "string", "enum": ["amazon", "ubuntu"] },
          "update_os": { "type": "boolean", "default": true }
        }
      }
    },
    {
      "if": { "properties": { "family": { "not": { "const": "amazon" } } } },
      "then": {
        "properties": {
          "family": { "type": "string", "enum": ["amazon", "ubuntu"] },
          "version": { "type": "string", "minLength": 1 }
        },
        "required": ["version"]
      }
    }
  ]
}
```

**IMPORTANT**: Do NOT set `"additionalProperties": false` at:
- the **top-level (root) of `input_schema.json`** — it triggers `undefined: must NOT have additional properties NO_CODE_ERROR` in the SG no-code form renderer
- any object using `allOf` with `if/then` — it breaks form rendering

## UI Schema Quick Reference

| Use Case | UI Schema |
|----------|-----------|
| Boolean toggle | `"ui:widget": "checkbox"` |
| Dropdown select | `"ui:widget": "select"` |
| Inline radio | `"ui:widget": "radio", "ui:options": {"inline": true}` |
| Multiline text | `"ui:widget": "textarea", "ui:options": {"rows": 3}` |
| Array of strings | `"items": { "ui:placeholder": "value" }` |
| Section title | `"ui:title": "Section Name"` |
| Help text | `"ui:description": "Helpful text..."` |
| Input hint | `"ui:placeholder": "example value"` |

## Field Ordering Guidelines

Follow these ordering rules for consistent schemas:

1. **Top-level field order:**
   - If `stackguardian` config exists: place it first, then `aws_region`
   - If no `stackguardian` config: place `aws_region` at the top
   - Then other configuration objects in logical order

2. **Inside `stackguardian` object:**
   - `api_uri` (API Region) first
   - `api_key` second
   - `org_name` third

3. **Network subnet ordering:**
   - `private_subnet_id` before `public_subnet_id` (private takes precedence)

4. **Sensitive fields:**
   - Do NOT use `"ui:widget": "password"` for API keys or tokens
   - Use plain text input - the platform handles masking

## StackGuardian API Key Pattern

API keys in StackGuardian templates must accept both direct keys and secret references:

- **Direct API keys**: `sgo_*` (organization) or `sgu_*` (user)
- **Secret references**: `${secret::SECRET_NAME}` where SECRET_NAME contains alphanumeric characters, underscores, or hyphens

### Input Schema
```json
"api_key": {
  "title": "API Key",
  "type": "string",
  "pattern": "^(sg[uo]_.*|\\$\\{secret::[a-zA-Z0-9_-]+\\})$",
  "minLength": 1
}
```

### UI Schema
```json
"api_key": {
  "ui:placeholder": "sgu_*** or ${secret::SECRET_NAME}",
  "ui:description": "Your organization's API key (sgo_*/sgu_*) or a secret reference (${secret::SECRET_NAME})"
}
```

## Workflow

To create schemas from Terraform variables.tf:

1. Read the variables.tf file to understand all variables
2. Create input_schema.json:
   - Do NOT include `"$schema"` key - StackGuardian forms don't require it
   - Map each variable to JSON Schema type
   - Convert nested objects recursively
   - Add validation constraints (pattern, enum, minimum, etc.)
   - List required fields (those without defaults)
   - Use `"additionalProperties": false` for strict validation on **nested** objects only
   - **Never** set `additionalProperties: false` at the schema root — breaks SG form rendering with `NO_CODE_ERROR`
   - Also do NOT set it on objects using `allOf`/`if-then` conditional logic
   - Follow field ordering guidelines above
3. Create ui_schema.json:
   - Mirror the structure of input_schema.json for nested objects
   - Add `ui:title` and `ui:description` for object sections
   - Use `ui:description` from Terraform `description` field
   - Add `ui:placeholder` hints based on expected format
   - Select appropriate widgets for each field type
   - Add warnings for destructive options (using markdown)
   - Do NOT use `"ui:widget": "password"` for sensitive inputs

## Two Schema Styles

### Terraform Module Style (nested objects)
Use `ui:title` on object properties to create visual sections:
```json
{
  "network": {
    "ui:title": "Network Configuration",
    "ui:description": "Configure VPC and subnet settings",
    "vpc_id": { "ui:placeholder": "vpc-***" }
  }
}
```

### Workflow Step Template Style (flat with dependencies)
Use `ui:order` and JSON Schema `dependencies` for conditional fields:
```json
{
  "ui:order": ["action", "option1", "option2"],
  "action": { "ui:widget": "radio" }
}
```

## Reference Documentation

For detailed patterns and examples, see:
- `references/terraform-to-schema-mapping.md` - Complete type conversion rules
- `references/ui-schema-patterns.md` - UI widget patterns and examples
- `examples/private-runner/` - Terraform module style with nested objects
- `examples/runner-group/` - Conditional dependencies with oneOf
- `examples/kubernetes/` - Workflow step template style schemas
