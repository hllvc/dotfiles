# UI Schema Patterns

This reference documents UI schema patterns for StackGuardian no-code forms.

## Structure Overview

The UI schema mirrors the structure of the input schema, adding UI-specific properties at each level.

```json
{
  "ui:title": "Form Title",
  "ui:description": "Form description",
  "field_name": {
    "ui:widget": "...",
    "ui:placeholder": "...",
    "ui:description": "..."
  },
  "nested_object": {
    "ui:title": "Section Title",
    "nested_field": {
      "ui:description": "..."
    }
  }
}
```

## Widget Types

### Text Input (Default)
No widget specification needed for standard text input:
```json
"name": {
  "ui:placeholder": "Enter name",
  "ui:description": "The display name for this resource"
}
```

### Checkbox (Boolean)
```json
"enabled": {
  "ui:widget": "checkbox",
  "ui:description": "Enable this feature"
}
```

### Select Dropdown (Enum)
```json
"region": {
  "ui:widget": "select",
  "ui:placeholder": "Select a region",
  "ui:description": "AWS region for deployment"
}
```

### Radio Buttons (Small Enum)
For 2-4 mutually exclusive options:
```json
"action": {
  "ui:widget": "radio",
  "ui:options": {
    "inline": true
  }
}
```

### Textarea (Multiline)
For SSH keys, certificates, YAML content:
```json
"ssh_public_key": {
  "ui:widget": "textarea",
  "ui:placeholder": "ssh-rsa AAAAB3...",
  "ui:options": {
    "rows": 3,
    "resize": "vertical"
  },
  "ui:description": "Your SSH public key"
}
```

### Hidden Field
```json
"internal_id": {
  "ui:widget": "hidden"
}
```

## Array Fields

For array fields (Terraform `list(T)`), use proper array UI with `items` configuration instead of textarea:

### Array of Strings
**Input Schema:**
```json
"additional_versions": {
  "type": "array",
  "items": {
    "type": "string",
    "pattern": "^[0-9]+\\.[0-9]+\\.[0-9]+$"
  },
  "default": []
}
```

**UI Schema:**
```json
"additional_versions": {
  "ui:description": "Additional versions to install. Click + to add more.",
  "items": {
    "ui:placeholder": "1.5.7"
  }
}
```

This renders as a dynamic list with add/remove buttons, much better UX than a textarea requiring JSON input.

### Array of Objects
**Input Schema:**
```json
"ingress_rules": {
  "type": "array",
  "items": {
    "type": "object",
    "properties": {
      "port": { "type": "integer" },
      "protocol": { "type": "string", "enum": ["tcp", "udp"] }
    }
  }
}
```

**UI Schema:**
```json
"ingress_rules": {
  "ui:description": "Define ingress rules",
  "items": {
    "port": { "ui:placeholder": "80" },
    "protocol": { "ui:widget": "select" }
  }
}
```

### Anti-pattern: Textarea for Arrays
**Do NOT use textarea for arrays:**
```json
// BAD - requires users to type JSON manually
"versions": {
  "ui:widget": "textarea",
  "ui:placeholder": "[\"1.4.6\", \"1.5.7\"]"
}
```

**Use proper array UI instead:**
```json
// GOOD - renders as dynamic list with add/remove buttons
"versions": {
  "items": {
    "ui:placeholder": "1.4.6"
  }
}
```

## Section Grouping

### Object with Title
Use `ui:title` to create visual sections for nested objects:
```json
"network": {
  "ui:title": "Network Configuration",
  "ui:description": "Configure VPC and subnet settings",
  "vpc_id": {
    "ui:placeholder": "vpc-***",
    "ui:description": "Your VPC ID"
  },
  "subnet_id": {
    "ui:placeholder": "subnet-***"
  }
}
```

### Top-Level Title
```json
{
  "ui:title": "AWS Private Runner Setup",
  "ui:description": "Configure and deploy a StackGuardian Private Runner on AWS"
}
```

## Field Ordering

### Top-Level Ordering
For workflow step templates, use `ui:order` to control field sequence:
```json
{
  "ui:order": [
    "action",
    "namespace",
    "resource_type",
    "options",
    "advanced"
  ]
}
```

Fields not in `ui:order` appear after listed fields in their original order.

### Nested Object Ordering
You can also use `ui:order` within nested objects to control field order inside sections:
```json
{
  "ui:order": [
    "stackguardian",
    "aws_region",
    "network",
    "storage"
  ],
  "stackguardian": {
    "ui:title": "StackGuardian Configuration",
    "ui:order": ["api_uri", "api_key", "org_name"],
    "api_uri": {
      "ui:widget": "select",
      "ui:description": "Select your platform region"
    },
    "api_key": {
      "ui:placeholder": "sg(u|o)_***"
    },
    "org_name": {
      "ui:placeholder": "your-org-name (optional)"
    }
  }
}
```

This ensures fields within the `stackguardian` section appear in the order: `api_uri`, then `api_key`, then `org_name`.

## Placeholder Patterns

Use placeholders to show expected format:

```json
// AWS Resource IDs
"vpc_id": { "ui:placeholder": "vpc-***" }
"subnet_id": { "ui:placeholder": "subnet-***" }
"ami_id": { "ui:placeholder": "ami-***" }

// IP/CIDR
"ip_address": { "ui:placeholder": "192.168.1.1" }
"cidr_block": { "ui:placeholder": "10.0.0.0/16" }

// Kubernetes
"namespace": { "ui:placeholder": "default" }
"release_name": { "ui:placeholder": "my-release" }

// Optional with hint
"override_name": { "ui:placeholder": "override name (optional)" }
```

## Description Patterns

### Standard Description
```json
"instance_type": {
  "ui:description": "The EC2 instance type (min 4 vCPU, 8GB RAM recommended)"
}
```

### Warning Description
Use emoji and bold for important warnings:
```json
"force_destroy": {
  "ui:widget": "checkbox",
  "ui:description": "**Warning:** This will permanently delete all data. Cannot be undone."
}
```

### Detailed Description
For complex fields:
```json
"create_network": {
  "ui:widget": "checkbox",
  "ui:description": "Whether to create NAT Gateway and route tables. Defaults to false for enterprise environments with existing infrastructure. Check this box if you need the module to create NAT Gateway and routing."
}
```

## Dynamic Objects (Maps)

For `additionalProperties` (map types):
```json
"tags": {
  "ui:options": {
    "addable": true,
    "removable": true,
    "orderable": false
  },
  "ui:description": "Resource tags as key-value pairs",
  "additionalProperties": {
    "ui:placeholder": "tag value"
  }
}
```

### Complex Map Values
For maps with object values:
```json
"helm_set": {
  "ui:options": {
    "addable": true,
    "removable": true
  },
  "ui:description": "Helm chart value overrides",
  "additionalProperties": {
    "ui:widget": "textarea",
    "ui:options": {
      "rows": 1,
      "resize": "vertical"
    }
  }
}
```

## Conditional Display

For workflow step templates with conditional fields, combine input schema `dependencies` with UI schema:

**Input Schema:**
```json
{
  "dependencies": {
    "action": {
      "oneOf": [
        {
          "properties": {
            "action": { "enum": ["apply"] },
            "dry_run": { "type": "boolean" }
          }
        },
        {
          "properties": {
            "action": { "enum": ["delete"] },
            "force": { "type": "boolean" }
          }
        }
      ]
    }
  }
}
```

**UI Schema:**
```json
{
  "action": {
    "ui:widget": "radio",
    "ui:options": { "inline": true }
  },
  "dry_run": {
    "ui:widget": "checkbox",
    "ui:description": "Simulate without making changes"
  },
  "force": {
    "ui:widget": "checkbox",
    "ui:description": "Force deletion without confirmation"
  }
}
```

## Enum with Display Names

When using `enum` + `enumNames` in input schema:

**Input Schema:**
```json
"version": {
  "type": "string",
  "enum": ["1.28", "1.27", "1.26"],
  "enumNames": ["v1.28 (latest)", "v1.27", "v1.26"]
}
```

**UI Schema:**
```json
"version": {
  "ui:widget": "select",
  "ui:placeholder": "Select version"
}
```

## Complete Terraform Module Example

```json
{
  "ui:title": "AWS EC2 Instance",
  "ui:description": "Deploy an EC2 instance with configurable settings",

  "instance_type": {
    "ui:description": "EC2 instance type"
  },

  "ami_id": {
    "ui:placeholder": "ami-***",
    "ui:description": "Amazon Machine Image ID"
  },

  "network": {
    "ui:title": "Network Settings",
    "ui:description": "Configure networking",
    "vpc_id": {
      "ui:placeholder": "vpc-***",
      "ui:description": "VPC to deploy into"
    },
    "subnet_id": {
      "ui:placeholder": "subnet-***"
    },
    "public_ip": {
      "ui:widget": "checkbox",
      "ui:description": "Assign public IP address"
    }
  },

  "storage": {
    "ui:title": "Storage Configuration",
    "volume_type": {
      "ui:widget": "select",
      "ui:description": "EBS volume type"
    },
    "volume_size": {
      "ui:description": "Volume size in GB (minimum 8)"
    }
  },

  "tags": {
    "ui:title": "Resource Tags",
    "ui:options": {
      "addable": true,
      "removable": true
    }
  }
}
```

## Best Practices

1. Always add `ui:description` from Terraform `description` field
2. Use `ui:placeholder` to show expected format
3. Use `ui:widget: "checkbox"` for all boolean fields
4. Use `ui:widget: "select"` for enum fields with 5+ options
5. Use `ui:widget: "radio"` with `inline: true` for 2-4 options
6. Group related fields in objects with `ui:title`
7. Use markdown in descriptions for emphasis and warnings
8. Add `ui:title` and `ui:description` at object level for sections
9. For array fields, use `items` configuration - never use `textarea` for arrays
