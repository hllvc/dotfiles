# Terraform to JSON Schema Mapping

This reference documents how to convert Terraform variable definitions to JSON Schema for StackGuardian no-code forms.

## Basic Types

### String
```hcl
variable "name" {
  type    = string
  default = "default-value"
}
```
```json
"name": {
  "type": "string",
  "default": "default-value"
}
```

### Number
```hcl
variable "count" {
  type    = number
  default = 10
}
```
```json
"count": {
  "type": "number",
  "default": 10
}
```

For integers specifically (whole numbers):
```json
"count": {
  "type": "integer",
  "default": 10
}
```

### Boolean
```hcl
variable "enabled" {
  type    = bool
  default = true
}
```
```json
"enabled": {
  "type": "boolean",
  "default": true
}
```

## Collection Types

### List
```hcl
variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}
```
```json
"availability_zones": {
  "type": "array",
  "items": {
    "type": "string"
  },
  "default": ["us-east-1a", "us-east-1b"]
}
```

### Map
```hcl
variable "tags" {
  type    = map(string)
  default = {}
}
```
```json
"tags": {
  "type": "object",
  "additionalProperties": {
    "type": "string"
  },
  "default": {}
}
```

### Set
Sets are converted to arrays with `uniqueItems: true`:
```hcl
variable "allowed_ips" {
  type = set(string)
}
```
```json
"allowed_ips": {
  "type": "array",
  "items": { "type": "string" },
  "uniqueItems": true
}
```

## Object Types

### Simple Object
```hcl
variable "network" {
  type = object({
    vpc_id    = string
    subnet_id = string
  })
}
```
```json
"network": {
  "type": "object",
  "properties": {
    "vpc_id": { "type": "string" },
    "subnet_id": { "type": "string" }
  },
  "required": ["vpc_id", "subnet_id"],
  "additionalProperties": false
}
```

### Object with Optional Fields
```hcl
variable "config" {
  type = object({
    name     = string
    port     = optional(number, 8080)
    enabled  = optional(bool, true)
  })
}
```
```json
"config": {
  "type": "object",
  "properties": {
    "name": { "type": "string" },
    "port": { "type": "integer", "default": 8080 },
    "enabled": { "type": "boolean", "default": true }
  },
  "required": ["name"],
  "additionalProperties": false
}
```

### Nested Objects
```hcl
variable "database" {
  type = object({
    instance = object({
      class = string
      size  = number
    })
    backup = object({
      enabled   = bool
      retention = optional(number, 7)
    })
  })
}
```
```json
"database": {
  "type": "object",
  "properties": {
    "instance": {
      "type": "object",
      "properties": {
        "class": { "type": "string" },
        "size": { "type": "number" }
      },
      "required": ["class", "size"],
      "additionalProperties": false
    },
    "backup": {
      "type": "object",
      "properties": {
        "enabled": { "type": "boolean" },
        "retention": { "type": "integer", "default": 7 }
      },
      "required": ["enabled"],
      "additionalProperties": false
    }
  },
  "required": ["instance", "backup"],
  "additionalProperties": false
}
```

## Validation Patterns

### Regex Pattern
```hcl
variable "ami_id" {
  type = string
  validation {
    condition     = can(regex("^ami-[a-z0-9]+$", var.ami_id))
    error_message = "Must be a valid AMI ID."
  }
}
```
```json
"ami_id": {
  "type": "string",
  "pattern": "^ami-[a-z0-9]+$"
}
```

### Optional Field with Pattern
For optional fields with a default of `""`, the pattern must allow empty strings:
```hcl
variable "subnet_id" {
  type    = string
  default = ""  # Optional, can be empty
  validation {
    condition     = var.subnet_id == "" || can(regex("^subnet-.*$", var.subnet_id))
    error_message = "Must be a valid subnet ID or empty."
  }
}
```
```json
"subnet_id": {
  "type": "string",
  "pattern": "^(|subnet-.*)$",
  "default": ""
}
```

**Note**: Use `^(|pattern.*)$` to allow empty string OR the pattern. Without this, empty defaults will fail validation.

### Enum (contains)
```hcl
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Must be dev, staging, or prod."
  }
}
```
```json
"environment": {
  "type": "string",
  "enum": ["dev", "staging", "prod"]
}
```

### Minimum/Maximum
```hcl
variable "instance_count" {
  type = number
  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 10
    error_message = "Must be between 1 and 10."
  }
}
```
```json
"instance_count": {
  "type": "integer",
  "minimum": 1,
  "maximum": 10
}
```

### String Length
```hcl
variable "name" {
  type = string
  validation {
    condition     = length(var.name) >= 3 && length(var.name) <= 64
    error_message = "Name must be 3-64 characters."
  }
}
```
```json
"name": {
  "type": "string",
  "minLength": 3,
  "maxLength": 64
}
```

### Array Length
```hcl
variable "subnets" {
  type = list(string)
  validation {
    condition     = length(var.subnets) >= 1
    error_message = "At least one subnet required."
  }
}
```
```json
"subnets": {
  "type": "array",
  "items": { "type": "string" },
  "minItems": 1
}
```

## Complex Map Types

### Map of Objects
```hcl
variable "ingress_rules" {
  type = map(object({
    port        = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = {}
}
```
```json
"ingress_rules": {
  "type": "object",
  "additionalProperties": {
    "type": "object",
    "properties": {
      "port": {
        "type": "integer",
        "minimum": 1,
        "maximum": 65535
      },
      "protocol": {
        "type": "string",
        "enum": ["tcp", "udp", "icmp"]
      },
      "cidr_blocks": {
        "type": "array",
        "items": { "type": "string" },
        "minItems": 1
      }
    },
    "required": ["port", "protocol", "cidr_blocks"],
    "additionalProperties": false
  },
  "default": {}
}
```

## Required Fields Detection

**Required** (no default, not optional):
```hcl
variable "vpc_id" {
  type = string  # Required - no default
}
```

**Optional** (has default):
```hcl
variable "region" {
  type    = string
  default = "us-east-1"  # Optional - has default
}
```

**Optional in object** (uses optional()):
```hcl
variable "config" {
  type = object({
    required_field = string              # Required
    optional_field = optional(string, "")  # Optional
  })
}
```

## Root Schema Structure

```json
{
  "type": "object",
  "properties": {
    // ... all variables as properties
  },
  "required": [
    // ... variables without defaults
  ]
}
```

**Note**: Do NOT include `"$schema"` key - StackGuardian forms don't require it.

## Title Field

Add `"title"` directly in properties for cleaner UI display:
```hcl
variable "aws_region" {
  description = "The target AWS Region"
  type        = string
  default     = "eu-central-1"
}
```
```json
"aws_region": {
  "title": "AWS Region",
  "type": "string",
  "default": "eu-central-1"
}
```

## Enum with Display Names (enumNames)

Use `enumNames` to show user-friendly labels while keeping real values:
```json
"api_uri": {
  "title": "API Region",
  "type": "string",
  "enum": [
    "https://api.app.stackguardian.io",
    "https://api.us.stackguardian.io"
  ],
  "enumNames": [
    "EU1 - Europe",
    "US1 - United States"
  ],
  "default": "https://api.app.stackguardian.io"
}
```

The `enum` array contains the actual values stored, while `enumNames` provides display labels.

## Conditional Dependencies

Use `dependencies` with `oneOf` to show/hide fields based on a boolean toggle:

**Terraform:**
```hcl
variable "create_storage_backend" {
  type    = bool
  default = true
}

variable "existing_s3_bucket_name" {
  description = "Required when create_storage_backend = false"
  type        = string
  default     = ""
}

variable "force_destroy_storage_backend" {
  description = "Only relevant when create_storage_backend = true"
  type        = bool
  default     = false
}
```

**JSON Schema:**
```json
{
  "properties": {
    "create_storage_backend": {
      "title": "Create Storage Backend",
      "type": "boolean",
      "default": true
    }
  },
  "dependencies": {
    "create_storage_backend": {
      "oneOf": [
        {
          "properties": {
            "create_storage_backend": { "enum": [true] },
            "force_destroy_storage_backend": {
              "title": "Force Destroy Storage Backend",
              "type": "boolean",
              "default": false
            }
          }
        },
        {
          "properties": {
            "create_storage_backend": { "enum": [false] },
            "existing_s3_bucket_name": {
              "title": "Existing S3 Bucket Name",
              "type": "string"
            }
          },
          "required": ["existing_s3_bucket_name"]
        }
      ]
    }
  }
}
```

When `create_storage_backend` is `true`, shows `force_destroy_storage_backend`.
When `create_storage_backend` is `false`, shows and requires `existing_s3_bucket_name`.

## AWS Regions Enum

Standard AWS regions list for region selection fields:
```json
"aws_region": {
  "title": "AWS Region",
  "type": "string",
  "enum": [
    "us-east-1",
    "us-east-2",
    "us-west-1",
    "us-west-2",
    "af-south-1",
    "ap-east-1",
    "ap-south-1",
    "ap-south-2",
    "ap-southeast-1",
    "ap-southeast-2",
    "ap-southeast-3",
    "ap-southeast-4",
    "ap-southeast-5",
    "ap-northeast-1",
    "ap-northeast-2",
    "ap-northeast-3",
    "ca-central-1",
    "ca-west-1",
    "eu-central-1",
    "eu-central-2",
    "eu-west-1",
    "eu-west-2",
    "eu-west-3",
    "eu-south-1",
    "eu-south-2",
    "eu-north-1",
    "il-central-1",
    "me-south-1",
    "me-central-1",
    "sa-east-1"
  ],
  "default": "eu-central-1"
}
```

## Conditional Fields with allOf/if-then

Use `allOf` with `if/then` to show/hide fields based on enum selection:

```hcl
variable "os" {
  type = object({
    family                   = string
    version                  = optional(string, "")
    update_os_before_install = bool
  })
  validation {
    condition     = contains(["amazon", "ubuntu", "rhel"], var.os.family)
    error_message = "Must be amazon, ubuntu, or rhel."
  }
}
```

```json
"os": {
  "type": "object",
  "required": ["family"],
  "allOf": [
    {
      "if": {
        "properties": {
          "family": { "const": "amazon" }
        }
      },
      "then": {
        "properties": {
          "family": {
            "type": "string",
            "enum": ["amazon", "ubuntu", "rhel"],
            "default": "amazon"
          },
          "update_os_before_install": {
            "type": "boolean",
            "default": true
          }
        }
      }
    },
    {
      "if": {
        "properties": {
          "family": {
            "not": { "const": "amazon" }
          }
        }
      },
      "then": {
        "properties": {
          "family": {
            "type": "string",
            "enum": ["amazon", "ubuntu", "rhel"],
            "default": "amazon"
          },
          "version": {
            "type": "string",
            "minLength": 1
          },
          "update_os_before_install": {
            "type": "boolean",
            "default": true
          }
        },
        "required": ["version"]
      }
    }
  ]
}
```

**CRITICAL**: Do NOT use `additionalProperties: false` at the parent object level when using `allOf`/`if-then` - it breaks form rendering.

## Best Practices

1. Do NOT include `"$schema"` key - StackGuardian forms don't require it
2. Use `"additionalProperties": false` for object types to prevent typos
   - **Exception**: Do NOT use on objects with `allOf`/`if-then` conditional logic
3. Use `"integer"` for whole numbers, `"number"` for decimals
4. Extract regex patterns from Terraform validation conditions
5. Convert `contains()` validations to `"enum"`
6. Preserve default values from Terraform
7. Mark variables without defaults as required
8. Add `"title"` for cleaner field labels in the UI
9. Use `enumNames` when enum values are technical (URLs, IDs) but need friendly display
10. Use `dependencies` with `oneOf` for conditional field visibility based on boolean toggle
11. Use `allOf` with `if/then` for conditional fields based on enum selection
