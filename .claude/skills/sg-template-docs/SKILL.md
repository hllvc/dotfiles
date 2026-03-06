---
name: sg-template-docs
description: Generate README.md and DOCUMENTATION.md for StackGuardian templates. Use when user asks to "generate template docs", "create README and DOCUMENTATION", "sg template docs", or needs documentation for a StackGuardian Terraform template.
version: 1.0.0
---

# StackGuardian Template Documentation Generator

Generate two documentation files for StackGuardian Terraform templates:
- **README.md** - Technical documentation for developers
- **DOCUMENTATION.md** - User-facing documentation for template users

## Workflow

### Step 1: Analyze the Module

Read the following files in the current directory:

**For README.md (technical):**
1. **`variables.tf`** - PRIMARY source for parameters (names, types, descriptions, validations)
2. **All other `*.tf` files** - Resources created, architecture
3. **`outputs.tf`** - Module outputs
4. **`versions.tf`** - Required provider versions

**For DOCUMENTATION.md (user-facing):**
1. **`schemas/input_schema.json`** - PRIMARY source for parameters (types, defaults, validation patterns, required fields)
2. **`schemas/ui_schema.json`** - PRIMARY source for user-friendly descriptions, placeholders, widget types, section groupings
3. **`outputs.tf`** - User-relevant outputs only

### Step 2: Generate README.md

Create a technical README with these sections:

```markdown
# {Module Title} - {Cloud Provider} Module

{One-paragraph overview of what the module does}

## Overview

{2-3 sentences about the module's purpose and key capabilities}

### What Gets Created

- **{Resource Type}**: {Description}
- **{Resource Type}**: {Description}
...

## Prerequisites

{List technical requirements: AMI, API keys, AWS infrastructure, permissions}

## Quick Start

### Step 1: {First Step Title}
{Commands and explanation}

### Step 2: {Second Step Title}
{Commands and explanation}

### Basic Configuration Example

\`\`\`hcl
{Minimal working example}
\`\`\`

## Configuration

### Required Parameters

| Parameter | Description | Type |
|-----------|-------------|------|
{Extract from variables.tf - variables without defaults}

### Optional Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
{Extract from variables.tf - variables with defaults}

### Configuration Examples

#### Basic Configuration

\`\`\`hcl
{Basic module call with required params only}
\`\`\`

#### Advanced Configuration

\`\`\`hcl
{Full module call with optional params}
\`\`\`

## Usage

{Deployment commands: terraform init, validate, plan, apply}

### Auto-scaling

{If applicable, describe auto-scaling behavior}

### Cleanup

{Destruction commands and warnings}

## Architecture

### Resource Organization

{List .tf files and what they contain}

### Resource Naming Convention

{Describe naming patterns}

## Troubleshooting

### Common Issues

1. **{Issue Title}**
   - {Symptoms and solutions}

### Debugging Commands

\`\`\`bash
{Useful debug commands}
\`\`\`

## Outputs

| Output | Description |
|--------|-------------|
{Extract from outputs.tf}

## Security Considerations

{List security features: encryption, IAM, networking}

## Requirements

| Name | Version |
|------|---------|
{Extract from versions.tf}

## Next Steps

{Post-deployment instructions}

## Support

{Support resources and links}
```

### Step 3: Generate DOCUMENTATION.md

Create a user-facing documentation with these sections:

```markdown
# {Module Title} - {Cloud Provider} Template

{One sentence about deploying on StackGuardian platform}

## Overview

{Business-focused description of what users get}

### What This Template Creates

- **{Resource}** {user-friendly description}
- **{Resource}** {user-friendly description}
...

## Prerequisites

{Simplified list: API key, AWS permissions reference, network requirements}

## Template Parameters

### Required Parameters

| Parameter | Description | Type |
|-----------|-------------|------|
{Extract from schemas/input_schema.json required array, use ui_schema.json for descriptions}

### Optional Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
{Extract from schemas/input_schema.json (fields with defaults), use ui_schema.json for descriptions}

## Important Notes

**{Topic}**: {Brief explanation relevant to template users}

## Outputs

| Output | Description |
|--------|-------------|
{Only user-relevant outputs}

## Security Features

{Bullet list of security features in plain language}
```

## Style Guidelines

### README.md (Technical)
- Use HCL code blocks for examples
- Include bash commands for debugging
- Reference file organization and architecture
- Include troubleshooting with specific commands
- Use technical terminology

### DOCUMENTATION.md (User-Facing)
- Use plain language, avoid jargon
- Focus on "what" not "how to build"
- Keep code examples minimal
- Highlight security and business value

## Data Source Rules

**README.md uses `variables.tf` because:**
- Terraform users work with HCL variable definitions
- Contains technical descriptions and validation blocks
- Shows exact variable names and nested object structures

**DOCUMENTATION.md uses `schemas/` because:**
- Template users interact via no-code UI forms
- `ui_schema.json` has user-friendly descriptions, placeholders, and section groupings
- `input_schema.json` has defaults, validation patterns, and required field definitions
- Schemas reflect what users actually see in the StackGuardian platform

## Additional Notes

- Always include both required and optional parameter tables
- Reference sibling modules (e.g., Packer) where applicable
- Overwrite existing files without prompting
