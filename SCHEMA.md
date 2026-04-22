# Pathfinding Labs Scenario Schema Documentation

## Table of Contents

- [Overview](#overview)
- [Schema Version](#schema-version)
- [Complete Field Reference](#complete-field-reference)
  - [Core Metadata](#core-metadata)
  - [Classification](#classification)
  - [Attack Path](#attack-path)
  - [Permissions](#permissions)
  - [MITRE ATT&CK](#mitre-attck)
  - [Terraform Integration](#terraform-integration)
- [Complete Examples](#complete-examples)
- [Guidelines and Best Practices](#guidelines-and-best-practices)
- [Validation](#validation)

---

## Overview

Each Pathfinding Labs scenario includes a `scenario.yaml` file that provides structured metadata about the attack path, required permissions, classification, and integration details. This file serves multiple purposes:

- **Documentation**: Human-readable description of the scenario
- **Automation**: Machine-parsable data for CLI tools and orchestration
- **Discovery**: Enables grouping, filtering, and searching scenarios
- **Integration**: Maps scenarios to Terraform variables and modules

### File Location

Every scenario directory should contain a `scenario.yaml` file:

```
modules/scenarios/single-account/privesc-one-hop/to-admin/iam-putuserpolicy/
├── scenario.yaml          # ← Scenario metadata
├── main.tf
├── variables.tf
├── outputs.tf
├── README.md
├── demo_attack.sh
└── cleanup_attack.sh
```

---

## Schema Version

### Current Version: `1.7.0`

The schema follows semantic versioning:

- **Major** (`x.0.0`): Breaking changes (e.g., removing required fields, changing field types)
- **Minor** (`1.x.0`): Backward-compatible additions (e.g., new optional fields)
- **Patch** (`1.0.x`): Clarifications, documentation updates, no schema changes

### Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.7.0 | 2026-04-21 | Added `demo_timeout_seconds` and `cleanup_timeout_seconds` optional integer fields: per-scenario overrides of the default harness timeouts in `scripts/run_demos.py` (300s demo, 120s cleanup). Required for any scenario whose demo creates a resource that takes > 2 min to provision (Glue dev endpoints, SageMaker notebooks/processing jobs, CodeBuild projects, EC2 instances, etc.), because the harness uses SIGKILL on timeout — which bash traps cannot catch — leaving the resource orphaned. See "When to Set Timeout Overrides" in Core Metadata for the reference table. Motivated by the glue-001 orphan incident (2026-04-17 to 2026-04-21) that bled ~$55 on an abandoned dev endpoint. |
| 1.6.0 | 2026-04-18 | Added `supports_online_mode` optional boolean field: indicates whether this lab is available to play in the browser via the pathfinding.cloud online lab runner. Defaults to `false` (absent = false). Only set to `true` for labs that have been validated and provisioned for online play. |
| 1.5.0 | 2026-04-10 | Added `cost_estimate_when_demo_executed` required field: estimated monthly cost while a demo script is actively running (e.g., EC2/Lambda instances provisioned by the attack). Initialized to same value as `cost_estimate` for existing scenarios. |
| 1.4.0 | 2026-04-09 | Added `modifications` optional list field for Attack Simulation scenarios, documenting changes made from the original real-world attack. |
| 1.3.0 | 2026-04-08 | Added `"CTF"` and `"Attack Simulation"` categories, `"ctf"` and `"attack-simulation"` path_types, `title` and `interactive_demo` core fields, `ctf` optional block, `source` optional block. Fixed `sub_category` requiredness (conditional, not always required). |
| 1.2.1 | 2026-02-05 | Standardized `cost_estimate` format to `"$X/mo"` (e.g., `"$0/mo"`, `"$9/mo"`). Replaced `"free"` and other formats. |
| 1.2.0 | 2025-11-03 | Added `pathfinding-cloud-id` to help map scenarios with Pathfinding.cloud paths when applicable. |
| 1.1.0 | 2025-10-21 | Added `cross-account` path_type; Changed `no-hop` to `self-escalation`; Added `privilege-chaining` and `cross-account-escalation` sub_categories; Added principal counting rules |
| 1.0.0 | 2025-10-21 | Initial schema release |


---

## Complete Field Reference

### Core Metadata

Fundamental information about the scenario.

```yaml
schema_version: "1.7.0"
name: "iam-putuserpolicy"
title: "IAM PutUserPolicy Self-Escalation to Admin"
description: "Principal with iam:PutUserPolicy can attach inline admin policy to escalate privileges"
cost_estimate: "$0/mo"
cost_estimate_when_demo_executed: "$0/mo"
pathfinding-cloud-id: IAM-005
interactive_demo: false
supports_online_mode: false
# demo_timeout_seconds: 1200      # uncomment + set for slow-provisioning demos
# cleanup_timeout_seconds: 180    # uncomment + set for slow-provisioning demos
```

#### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `schema_version` | string | ✅ Yes | Schema version this file conforms to. Format: `"X.Y.Z"` |
| `name` | string | ✅ Yes | Unique identifier for the scenario. Should match directory name. Use kebab-case. |
| `title` | string | No | Human-readable scenario title. Used as the README H1 heading. If omitted, agents derive a title from the name and technique. |
| `description` | string | ✅ Yes | One-line description of the scenario. Should be concise (< 150 chars). |
| `cost_estimate` | string | ✅ Yes | Estimated monthly AWS cost while the lab is enabled and idle (no demo running). Always use `"$X/mo"` format rounded to nearest dollar (e.g., `"$0/mo"`, `"$9/mo"`, `"$321/mo"`) |
| `cost_estimate_when_demo_executed` | string | ✅ Yes | Estimated monthly AWS cost while a demo script is actively running (e.g., EC2/Lambda/GPU instances provisioned during the attack). Same format as `cost_estimate`. If the demo creates no additional resources, set equal to `cost_estimate`. |
| `pathfinding-cloud-id` | string | No | ID of Pathfinding.cloud path ID if one exists. |
| `interactive_demo` | bool | No | If `true`, the demo script requires terminal input (e.g., SSM session). Defaults to `false`. |
| `supports_online_mode` | bool | No | If `true`, this lab is available to play in the browser via the pathfinding.cloud online lab runner. Defaults to `false`. Only set to `true` after the lab has been validated and provisioned for online play by the Pathfinding team. |
| `demo_timeout_seconds` | int | No | Override the default 300s demo timeout in `scripts/run_demos.py`. Set when the demo creates a resource that takes > 2 min to provision. See "When to Set Timeout Overrides" below. |
| `cleanup_timeout_seconds` | int | No | Override the default 120s cleanup timeout in `scripts/run_demos.py`. Set when cleanup needs to verify deletion of a resource that takes noticeable time to tear down. See "When to Set Timeout Overrides" below. |

#### Cost Estimate Examples

`cost_estimate` represents the idle cost (lab enabled, no demo running). `cost_estimate_when_demo_executed` represents the cost while a demo script is actively running. For labs where the demo creates temporary resources (EC2 instances, Lambda functions, GPU instances), `cost_estimate_when_demo_executed` will be higher. For IAM-only labs, both values are identical.

Always use `"$X/mo"` format with rounding to the nearest dollar:

| Cost Range | Format |
|------------|--------|
| No AWS charges (IAM-only) | `"$0/mo"` |
| $0.50 - $1.49 | `"$1/mo"` |
| $5.00 - $5.49 | `"$5/mo"` |
| $9.01 | `"$9/mo"` |
| $321.44 | `"$321/mo"` |

**Rules:**
- Always use `"$X/mo"` format (not "free", not "$5/month", not "$0.01/hour")
- Round to nearest whole dollar (standard rounding: 0.5 rounds up)
- No cents, no hourly/daily rates
- No vague terms ("low", "minimal", "cheap")

#### When to Set Timeout Overrides

`scripts/run_demos.py` runs every demo with a default 300s timeout and every cleanup with a default 120s timeout. On timeout, Python sends **SIGKILL** — which bash cannot trap — so the demo dies mid-run and any resource it created (Glue dev endpoint, SageMaker notebook, EC2 instance, etc.) is left orphaned and continues billing. This is exactly what bled ~$55 on `pl-glue-001-demo-endpoint` between 2026-04-17 and 2026-04-21.

**Rule of thumb: if the demo creates any AWS resource that takes longer than 2 minutes to reach a usable state, set `demo_timeout_seconds` explicitly.**

Reference table — pick the row that matches the slowest resource your demo creates, then add headroom:

| Resource created by demo                    | Typical provision time | Recommended `demo_timeout_seconds` | Recommended `cleanup_timeout_seconds` |
|---------------------------------------------|------------------------|------------------------------------|---------------------------------------|
| IAM only, STS assume-role, S3 object ops    | < 30s                  | default (omit field)               | default (omit field)                  |
| Lambda invoke, Step Functions start         | < 1 min                | default (omit field)               | default (omit field)                  |
| Glue Python shell / Spark ETL job run       | 1–3 min                | default (omit field)               | default (omit field)                  |
| CodeBuild project build                     | 2–6 min                | `600`                              | `180`                                 |
| SageMaker Processing Job                    | 5–10 min               | `900`                              | `180`                                 |
| SageMaker Notebook Instance                 | 5–10 min               | `900`                              | `300`                                 |
| Glue Dev Endpoint                           | 10–15 min              | `1200`                             | `180`                                 |
| EC2 instance + userdata bootstrap           | 2–5 min                | `600`                              | `180`                                 |
| ECS task on Fargate                         | 1–3 min                | default (omit field)               | default (omit field)                  |

When a scenario uses multiple resources, pick the override for the slowest one.

**Companion requirement for slow-provisioning demos:** the `demo_attack.sh` must register an `EXIT`/`INT`/`TERM` trap that best-effort deletes the provisioned resource on abnormal exit — this catches every failure mode except SIGKILL. See `modules/scenarios/single-account/privesc-one-hop/to-admin/glue-001-iam-passrole+glue-createdevendpoint/demo_attack.sh` for the canonical implementation (search for `_glue_demo_exit_handler`). The `cleanup_attack.sh` must initiate deletion and verify the API accepted the request, but MUST NOT block waiting for full deletion (AWS finishes asynchronously and billing stops at accept time).

---

### Classification

Taxonomy and categorization for discovery and filtering.

```yaml
category: "Privilege Escalation"
sub_category: "self-escalation"
path_type: "self-escalation"
target: "to-admin"
environments:
  - "prod"
```

#### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `category` | string | ✅ Yes | High-level scenario category |
| `sub_category` | string | Conditional | Required for `self-escalation` and `one-hop` path_types only. Not used for multi-hop, cross-account, CTF, Attack Simulation, CSPM, or Tool Testing. |
| `path_type` | string | ✅ Yes | Number of privilege escalation hops |
| `target` | string | ✅ Yes | Ultimate goal of the attack |
| `environments` | array | ✅ Yes | List of AWS accounts involved |

#### Allowed Values

##### `category`

| Value | Description | Use Case |
|-------|-------------|----------|
| `"Privilege Escalation"` | IAM privilege escalation (single or cross-account) | Most privilege escalation scenarios |
| `"CSPM: Misconfig"` | Single-condition security misconfiguration | EC2 with admin role, S3 bucket public, etc. |
| `"CSPM: Toxic Combination"` | Multiple compounding misconfigurations | Public Lambda + Admin Role, etc. |
| `"Tool Testing"` | Detection engine edge cases and testing scenarios | Test CSPM/detection tools for false positives/negatives, edge cases in policy parsing |
| `"CTF"` | Capture-the-flag challenge with real application infrastructure | AI chatbot with prompt injection, web API with SSRF, etc. |
| `"Attack Simulation"` | Real-world breach recreation as a lab environment | Sysdig "8 Minutes to Admin", Unit42 reports, etc. |

##### `sub_category`

**Required only for single-technique privilege escalation (`self-escalation`, `one-hop` path_types):**

These values align with [pathfinding.cloud](https://pathfinding.cloud) categories:

| Value | Description | Example Techniques |
|-------|-------------|-------------------|
| `"self-escalation"` | Principal modifies its own permissions | `iam:PutUserPolicy`, `iam:AttachUserPolicy` on self |
| `"principal-access"` | One principal accesses another principal | `sts:AssumeRole`, `iam:CreateAccessKey`, `iam:PutRolePolicy` + `sts:AssumeRole` on another role |
| `"new-passrole"` | Pass privileged role to AWS service (create new resource) | `iam:PassRole` + `lambda:CreateFunction`, `iam:PassRole` + `ec2:RunInstances` |
| `"existing-passrole"` | Access/modify existing resources with privileged roles | `lambda:UpdateFunctionCode`, `ssm:StartSession` to EC2 with admin role |
| `"credential-access"` | Access to hardcoded credentials within a resource | `ssm:StartSession` to EC2 with hardcoded creds, `lambda:GetFunction` with creds in environment |

**Not used for:**
- `multi-hop` path_type - chains multiple techniques (e.g., self-escalation + new-passrole)
- `cross-account` path_type - spans accounts, often multiple techniques
- `ctf` path_type - CTF scenarios
- `attack-simulation` path_type - attack simulation scenarios
- `CSPM: Misconfig` category - the category name is descriptive enough
- `CSPM: Toxic Combination` category - the category name is descriptive enough
- `Tool Testing` category - the category name is descriptive enough
- `CTF` category - the category name is descriptive enough
- `Attack Simulation` category - the category name is descriptive enough

**For `category: "CSPM: Misconfig"` or `"CSPM: Toxic Combination"` (optional):**

| Value | Description | Example |
|-------|-------------|---------|
| `"Publicly-accessible"` | Resource exposed to internet | Public S3 bucket, public Lambda URL |
| `"sensitive-data"` | Resource contains sensitive information | S3 bucket with PII, PHI, credentials, secrets |
| `"contains-vulnerability"` | Resource has known CVE or misconfiguration | Unpatched instance, vulnerable container |
| `"overly-permissive"` | Permissions broader than necessary | Wildcards in policies, `*:*` permissions |

**For `category: "Tool Testing"` (optional):**

| Value | Description | Example |
|-------|-------------|---------|
| `"edge-case-detection"` | Tests detection engine's ability to handle edge cases | Resource policies that bypass IAM, complex condition keys |
| `"false-positive-test"` | Scenarios that may trigger false positive alerts | Legitimate configurations that appear vulnerable |
| `"policy-parsing-edge-case"` | Complex policy structures that test parsing engines | Nested conditions, complex NotAction statements |

##### `path_type`

**For Privilege Escalation scenarios:**

| Value | Has sub_category? | Description | When to Use |
|-------|-------------------|-------------|-------------|
| `"self-escalation"` | Yes | Principal modifies its own permissions | 1 principal total (the principal modifies itself) |
| `"one-hop"` | Yes | Single privilege escalation step | 2 principals total (Principal A → Principal B) |
| `"multi-hop"` | No | Multiple privilege escalation steps | 3+ principals total (Principal A → B → C → ...) |
| `"cross-account"` | No | Attack spans multiple AWS accounts | Escalation crosses account boundaries (takes precedence over hop count) |

**For CSPM scenarios:**

| Value | Has sub_category? | Description | When to Use |
|-------|-------------------|-------------|-------------|
| `"single-condition"` | No | Single security misconfiguration | CSPM: Misconfig category |
| `"toxic-combination"` | No | Multiple compounding misconfigurations | CSPM: Toxic Combination category |

**For CTF scenarios:**

| Value | Has sub_category? | Description | When to Use |
|-------|-------------------|-------------|-------------|
| `"ctf"` | No | Capture-the-flag challenge | CTF category |

**For Attack Simulation scenarios:**

| Value | Has sub_category? | Description | When to Use |
|-------|-------------------|-------------|-------------|
| `"attack-simulation"` | No | Real-world breach recreation | Attack Simulation category |

**Principal Counting Rules (for Privilege Escalation):**
- Count only the IAM principals involved in the escalation path (users, roles)
- Don't count setup hops (e.g., `starting_user → AssumeRole → starting_role`)
- Don't count AWS services (EC2, Lambda) unless they hold credentials
- Don't count resources (S3 buckets) unless they're an intermediate credential store
- For cross-account: Use `"cross-account"` as path_type regardless of hop count

##### `target`

| Value | Description |
|-------|-------------|
| `"to-admin"` | Goal is full administrative access |
| `"to-bucket"` | Goal is access to sensitive S3 bucket |

**Note**: Additional targets may be added in future schema versions (e.g., `"to-secrets"`, `"to-database"`).

##### `environments`

List of AWS account environments involved in the attack path. Valid values:

- `"prod"` - Production account
- `"dev"` - Development account
- `"ops"` - Operations account

Examples:
```yaml
# Single-account scenario
environments:
  - "prod"

# Cross-account scenario
environments:
  - "dev"
  - "prod"
```

---

### Attack Path

Defines the principals involved and the attack flow.

```yaml
attack_path:
  principals:
    - "arn:aws:iam::{account_id}:user/pl-pup-user"
    - "arn:aws:iam::{account_id}:role/pl-pup-admin-role"

  summary: "starting_user → (iam:PutUserPolicy) → inline admin policy → admin access"
```

#### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `principals` | array | ✅ Yes | Ordered list of all AWS principals (ARNs) involved in the attack path |
| `summary` | string | ✅ Yes | Human-readable visual representation of the attack flow |

#### Principals

List all AWS resources and principals involved in the attack, in order:

- IAM users
- IAM roles
- S3 buckets
- EC2 instances
- Lambda functions
- Other AWS resources

**ARN Format Guidelines:**

- Use `{account_id}` for account ID placeholder: `arn:aws:iam::{account_id}:user/...`
- Use `{region}` for region placeholder: `arn:aws:ec2:{region}:{account_id}:instance/...`
- Use actual resource IDs when known, or `i-xxxxxxxxx` as placeholder for generated IDs
- For S3 buckets with random suffixes: `arn:aws:s3:::pl-bucket-{account_id}-{suffix}`

**Examples:**

```yaml
# User-only scenario
principals:
  - "arn:aws:iam::{account_id}:user/pl-cak-starting-user"
  - "arn:aws:iam::{account_id}:user/pl-cak-admin-victim"

# Role-based scenario with setup hop
principals:
  - "arn:aws:iam::{account_id}:user/pl-per-starting-user"
  - "arn:aws:iam::{account_id}:role/pl-prod-per-starting-role"
  - "arn:aws:iam::{account_id}:role/pl-EC2Admin"

# Scenario with EC2 instance
principals:
  - "arn:aws:iam::{account_id}:user/pl-pathfinding-starting-user-prod"
  - "arn:aws:ec2:{region}:{account_id}:instance/i-xxxxxxxxx"
  - "arn:aws:iam::{account_id}:user/pl-admin-hardcoded-victim"

# Multi-hop with S3 bucket
principals:
  - "arn:aws:iam::{account_id}:user/pl-pathfinding-starting-user-prod"
  - "arn:aws:iam::{account_id}:role/pl-prod-role-a"
  - "arn:aws:iam::{account_id}:role/pl-prod-role-b"
  - "arn:aws:s3:::pl-prod-admin-demo-bucket-{account_id}"
```

#### Summary

Visual representation of the attack flow using arrow notation `→` and parentheses for actions.

**Format Guidelines:**

- Use `→` (arrow) to show progression through the attack path
- Use `(action)` in parentheses to show AWS actions or permissions used
- Keep it concise but complete
- Show all major steps and principals
- End with the final access level achieved

**Examples:**

```yaml
# One-hop user-based
summary: "starting_user → (iam:PutUserPolicy) → inline admin policy → admin access"

# One-hop with setup
summary: "starting_user → (AssumeRole) → starting_role → (PassRole + RunInstances) → EC2 with admin profile → admin access"

# Multi-hop
summary: "starting_user → (AssumeRole) → role_a → (PutRolePolicy) → role_b → (AssumeRole) → role_b (now admin) → admin access"

# Credential access
summary: "starting_user → (ssm:StartSession) → EC2 instance → (cat credentials file) → admin credentials → admin access"

# Direct access
summary: "starting_user → (iam:CreateAccessKey) → admin_user credentials → admin access"
```

---

### Permissions

Required and helpful AWS IAM permissions for executing the attack, grouped by principal.

Both `required` and `helpful` are arrays of **principal entries**. Each principal entry associates a named IAM principal with its permissions. This structure supports multi-hop scenarios where different principals in the chain have different permissions.

```yaml
permissions:
  required:
    - principal: "pl-prod-scenario-starting-user"
      principal_type: "user"
      permissions:
        - permission: "iam:PutUserPolicy"
          resource: "*"

  helpful:
    - principal: "pl-prod-scenario-starting-user"
      principal_type: "user"
      permissions:
        - permission: "iam:GetUser"
          purpose: "View user details and verify policy attachment"
```

#### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `required` | array of principal entries | ✅ Yes | Permissions absolutely required to execute the attack, grouped by principal |
| `helpful` | array of principal entries | ❌ No | Permissions that aid in discovery, verification, or cleanup, grouped by principal |

#### Principal Entry

Each entry in `required` or `helpful` is a principal entry:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `principal` | string | ✅ Yes | IAM principal name (e.g., `"pl-prod-iam-002-to-admin-starting-user"`) |
| `principal_type` | string | ✅ Yes | Either `"user"` or `"role"` |
| `permissions` | array | ✅ Yes | List of permission entries for this principal |

#### Required Permission Entry

Each permission within a required principal entry:

```yaml
- permission: "iam:PutUserPolicy"    # AWS IAM action
  resource: "*"                       # Resource ARN or wildcard
```

**Fields:**
- `permission` (required): AWS IAM action (e.g., `"iam:PutUserPolicy"`)
- `resource` (optional): Resource constraint (ARN pattern or `"*"`)

**Examples:**

```yaml
required:
  # One-hop: single principal with all required permissions
  - principal: "pl-prod-iam-002-to-admin-starting-user"
    principal_type: "user"
    permissions:
      - permission: "iam:CreateAccessKey"
        resource: "arn:aws:iam::*:user/pl-prod-iam-002-to-admin-target-user"

  # Multi-hop: multiple principals each with their required permissions
  # - principal: "pl-prod-scenario-starting-user"
  #   principal_type: "user"
  #   permissions:
  #     - permission: "sts:AssumeRole"
  #       resource: "arn:aws:iam::*:role/pl-prod-scenario-intermediate-role"
  # - principal: "pl-prod-scenario-intermediate-role"
  #   principal_type: "role"
  #   permissions:
  #     - permission: "iam:PassRole"
  #       resource: "arn:aws:iam::*:role/pl-prod-scenario-admin-role"
  #     - permission: "ec2:RunInstances"
  #       resource: "*"
```

#### Helpful Permission Entry

Each permission within a helpful principal entry:

```yaml
- permission: "iam:ListUsers"
  purpose: "Discover privileged users to target"
```

**Fields:**
- `permission` (required): AWS IAM action
- `purpose` (required): Brief explanation of why this permission is helpful

**Examples:**

```yaml
helpful:
  - principal: "pl-prod-scenario-starting-user"
    principal_type: "user"
    permissions:
      - permission: "iam:ListRoles"
        purpose: "Discover available privileged roles"

      - permission: "iam:GetRole"
        purpose: "View role permissions and trust policies"

      - permission: "ec2:DescribeInstances"
        purpose: "Verify instance launch and get connection details"

      - permission: "s3:ListBuckets"
        purpose: "Discover target buckets after escalation"
```

---

### MITRE ATT&CK

Mapping to MITRE ATT&CK framework for threat modeling and detection.

```yaml
mitre_attack:
  tactics:
    - "TA0004 - Privilege Escalation"
    - "TA0003 - Persistence"
  techniques:
    - "T1098 - Account Manipulation"
    - "T1098.001 - Additional Cloud Credentials"
```

#### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `tactics` | array | ✅ Yes | MITRE ATT&CK tactics (high-level objectives) |
| `techniques` | array | ✅ Yes | MITRE ATT&CK techniques and sub-techniques |

#### Format

Use the format: `"TXXXX - Technique Name"`

**Common Tactics:**

```yaml
tactics:
  - "TA0001 - Initial Access"
  - "TA0002 - Execution"
  - "TA0003 - Persistence"
  - "TA0004 - Privilege Escalation"
  - "TA0005 - Defense Evasion"
  - "TA0006 - Credential Access"
  - "TA0007 - Discovery"
  - "TA0008 - Lateral Movement"
  - "TA0009 - Collection"
  - "TA0010 - Exfiltration"
  - "TA0011 - Impact"
```

**Common Techniques for AWS Scenarios:**

```yaml
techniques:
  # Account Manipulation
  - "T1098 - Account Manipulation"
  - "T1098.001 - Additional Cloud Credentials"

  # Valid Accounts
  - "T1078 - Valid Accounts"
  - "T1078.004 - Cloud Accounts"

  # Credential Access
  - "T1552 - Unsecured Credentials"
  - "T1552.001 - Credentials In Files"
  - "T1552.005 - Cloud Instance Metadata API"

  # Cloud Admin Command
  - "T1651 - Cloud Administration Command"

  # Modify Cloud Compute Infrastructure
  - "T1578 - Modify Cloud Compute Infrastructure"
```

**Reference:** [MITRE ATT&CK Cloud Matrix](https://attack.mitre.org/matrices/enterprise/cloud/)

---

### Terraform Integration

Maps the scenario to Terraform variables and modules.

```yaml
terraform:
  variable_name: "enable_single_account_privesc_self_escalation_to_admin_iam_putuserpolicy"
  module_path: "modules/scenarios/single-account/privesc-self-escalation/to-admin/iam-putuserpolicy"
```

#### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `variable_name` | string | ✅ Yes | Terraform boolean variable name that enables/disables this scenario |
| `module_path` | string | ✅ Yes | Relative path from project root to the scenario's Terraform module |

#### Variable Naming Convention

**Privilege Escalation Format**: `enable_single_account_privesc_{path_type}_{target}_{path_id}_{technique}`

**CSPM Misconfig Format**: `enable_single_account_cspm_misconfig_{id}_{name}`

**CSPM Toxic Combo Format**: `enable_single_account_cspm_toxic_combo_{name}`

**Tool Testing Format**: `enable_tool_testing_{technique}`

**Cross-Account Format**: `enable_cross_account_{source_to_dest}_{name}`

**CTF Format**: `enable_ctf_{scenario_name}`

**Attack Simulation Format**: `enable_attack_simulation_{scenario_name}`

**Examples:**

```yaml
# Self-escalation (single-account)
variable_name: "enable_single_account_privesc_self_escalation_to_admin_iam_005_iam_putrolepolicy"
variable_name: "enable_single_account_privesc_self_escalation_to_bucket_iam_005_iam_putrolepolicy"

# One-hop (single-account)
variable_name: "enable_single_account_privesc_one_hop_to_admin_iam_002_iam_createaccesskey"
variable_name: "enable_single_account_privesc_one_hop_to_bucket_sts_001_sts_assumerole"

# Multi-hop (single-account)
variable_name: "enable_single_account_privesc_multi_hop_to_admin_putrolepolicy_on_other"
variable_name: "enable_single_account_privesc_multi_hop_to_bucket_role_chain_to_s3"

# CSPM Misconfig (single-account)
variable_name: "enable_single_account_cspm_misconfig_cspm_ec2_001_instance_with_privileged_role"

# CSPM Toxic Combo (single-account)
variable_name: "enable_single_account_cspm_toxic_combo_public_lambda_with_admin"

# Tool testing
variable_name: "enable_tool_testing_resource_policy_bypass"
variable_name: "enable_tool_testing_exclusive_resource_policy"

# Cross-account (no target in variable name)
variable_name: "enable_cross_account_dev_to_prod_simple_role_assumption"
variable_name: "enable_cross_account_dev_to_prod_passrole_lambda_admin"
variable_name: "enable_cross_account_ops_to_prod_simple_role_assumption"

# CTF
variable_name: "enable_ctf_ai_chatbot_to_admin"

# Attack Simulation
variable_name: "enable_attack_simulation_sysdig_8_minutes_to_admin"
```

#### Module Path

Path from project root to the scenario directory (without trailing slash).

**Examples:**

```yaml
# Privilege Escalation - self-escalation (with path ID)
module_path: "modules/scenarios/single-account/privesc-self-escalation/to-admin/iam-005-iam-putrolepolicy"

# Privilege Escalation - one-hop (with path ID)
module_path: "modules/scenarios/single-account/privesc-one-hop/to-admin/iam-002-iam-createaccesskey"

# Privilege Escalation - multi-hop (no path ID)
module_path: "modules/scenarios/single-account/privesc-multi-hop/to-admin/putrolepolicy-on-other"

# CSPM Misconfig
module_path: "modules/scenarios/single-account/cspm-misconfig/cspm-ec2-001-instance-with-privileged-role"

# CSPM Toxic Combo
module_path: "modules/scenarios/single-account/cspm-toxic-combo/public-lambda-with-admin"

# Tool testing
module_path: "modules/scenarios/tool-testing/resource-policy-bypass"
module_path: "modules/scenarios/tool-testing/exclusive-resource-policy"

# Cross-account
module_path: "modules/scenarios/cross-account/dev-to-prod/simple-role-assumption"

# CTF
module_path: "modules/scenarios/ctf/ai-chatbot-to-admin"

# Attack Simulation
module_path: "modules/scenarios/attack-simulation/sysdig-8-minutes-to-admin"
```

---

### CTF Metadata

Optional block for CTF scenarios. Required when `category` is `"CTF"`.

```yaml
ctf:
  difficulty: "beginner"
  flag_location: "SSM Parameter Store at /ctf/ctf-001/flag (requires admin credentials)"
  variant: "ctf-001"
```

#### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `ctf.difficulty` | string | Yes (if ctf block) | `"beginner"`, `"intermediate"`, or `"advanced"` |
| `ctf.flag_location` | string | Yes (if ctf block) | Where the flag is stored and what access is needed to retrieve it |
| `ctf.variant` | string | No | CTF variant identifier |

---

### Source Metadata

Optional block for Attack Simulation scenarios. Required when `category` is `"Attack Simulation"`.

```yaml
source:
  url: "https://www.sysdig.com/blog/ai-assisted-cloud-intrusion-achieves-admin-access-in-8-minutes"
  title: "AI-Assisted Cloud Intrusion Achieves Admin Access in 8 Minutes"
  author: "Sysdig Threat Research Team"
  date: "2025-06-12"
```

#### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `source.url` | string | Yes (if source block) | URL of the blog post or report |
| `source.title` | string | Yes (if source block) | Title of the source material |
| `source.author` | string | Yes (if source block) | Author or organization that published the report |
| `source.date` | string | Yes (if source block) | Publication date in `YYYY-MM-DD` format |

---

### Lab Modifications

Optional list field for Attack Simulation scenarios. Documents changes made from the original real-world attack, such as replacing expensive resources, simplifying entry points, or removing destructive actions. This list is the source data for the `### Modifications from Original Attack` section in the README — it is not rendered in the README metadata block.

```yaml
modifications:
  - "In the original attack, the entry point was a publicly accessible S3 bucket containing embedded IAM credentials. In this lab, the bucket is private — a starting IAM user is pre-provisioned with read access to avoid publicly exposing real credentials."
  - "In the original attack, the attacker launched GPU instances for unauthorized cryptomining. The lab demo replicates this step using the same p3.2xlarge instance type, but the instance auto-terminates after 2 hours as a cost safeguard."
```

#### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `modifications` | list of strings | No | Each string describes one change from the original attack in natural language. Use the pattern: "In the original attack, {what happened}. In this lab, {what we changed and why}." |

**Rules:**
- Only used for `category: "Attack Simulation"` scenarios
- Each item should describe exactly one change, using plain language
- Explain both what the original attack did AND what the lab does instead, with brief rationale (cost, safety, or practicality)
- Omit if the lab faithfully replicates the original attack with no meaningful changes

---

## Complete Examples

### Example 1: Simple One-Hop User-Based Escalation

```yaml
# =============================================================================
# CORE METADATA
# =============================================================================
schema_version: "1.0.0"
name: "iam-createaccesskey"
description: "User with iam:CreateAccessKey can create credentials for admin user to gain admin access"
cost_estimate: "$0/mo"
pathfinding-cloud-id: "IAM-002"

# =============================================================================
# CLASSIFICATION
# =============================================================================
category: "Privilege Escalation"
sub_category: "credential-access"
path_type: "one-hop"
target: "to-admin"
environments:
  - "prod"

# =============================================================================
# ATTACK PATH
# =============================================================================
attack_path:
  principals:
    - "arn:aws:iam::{account_id}:user/pl-cak-starting-user"
    - "arn:aws:iam::{account_id}:user/pl-cak-admin"

  summary: "starting_user → (iam:CreateAccessKey) → admin_user credentials → admin access"

# =============================================================================
# PERMISSIONS
# =============================================================================
permissions:
  required:
    - principal: "pl-cak-starting-user"
      principal_type: "user"
      permissions:
        - permission: "iam:CreateAccessKey"
          resource: "arn:aws:iam::*:user/pl-cak-admin"

  helpful:
    - principal: "pl-cak-starting-user"
      principal_type: "user"
      permissions:
        - permission: "iam:ListUsers"
          purpose: "Discover privileged users to target"

        - permission: "iam:GetUser"
          purpose: "View user details and attached policies"

# =============================================================================
# MITRE ATT&CK
# =============================================================================
mitre_attack:
  tactics:
    - "TA0004 - Privilege Escalation"
    - "TA0003 - Persistence"
  techniques:
    - "T1098.001 - Account Manipulation: Additional Cloud Credentials"

# =============================================================================
# TERRAFORM
# =============================================================================
terraform:
  variable_name: "enable_single_account_privesc_one_hop_to_admin_iam_createaccesskey"
  module_path: "modules/scenarios/single-account/privesc-one-hop/to-admin/iam-createaccesskey"
```

---

### Example 2: One-Hop with Setup (Role-Based)

```yaml
# =============================================================================
# CORE METADATA
# =============================================================================
schema_version: "1.0.0"
name: "iam-passrole-ec2-runinstances"
description: "Role with PassRole and EC2 RunInstances can escalate to admin by launching instance with privileged instance profile"
cost_estimate: "$0/mo"

# =============================================================================
# CLASSIFICATION
# =============================================================================
category: "Privilege Escalation"
sub_category: "new-passrole"
path_type: "one-hop"
target: "to-admin"
environments:
  - "prod"

# =============================================================================
# ATTACK PATH
# =============================================================================
attack_path:
  principals:
    - "arn:aws:iam::{account_id}:user/pl-per-starting-user"
    - "arn:aws:iam::{account_id}:role/pl-prod-per-starting-role"
    - "arn:aws:iam::{account_id}:role/pl-EC2Admin"

  summary: "starting_user → (AssumeRole) → starting_role → (PassRole + RunInstances) → EC2 with admin profile → admin access"

# =============================================================================
# PERMISSIONS
# =============================================================================
permissions:
  required:
    - principal: "pl-prod-per-starting-role"
      principal_type: "role"
      permissions:
        - permission: "iam:PassRole"
          resource: "arn:aws:iam::*:role/pl-EC2Admin"

        - permission: "ec2:RunInstances"
          resource: "*"

  helpful:
    - principal: "pl-prod-per-starting-role"
      principal_type: "role"
      permissions:
        - permission: "iam:ListRoles"
          purpose: "Discover available privileged roles"

        - permission: "ec2:DescribeInstances"
          purpose: "Verify instance launch and get connection details"

# =============================================================================
# MITRE ATT&CK
# =============================================================================
mitre_attack:
  tactics:
    - "TA0004 - Privilege Escalation"
  techniques:
    - "T1098.001 - Account Manipulation: Additional Cloud Credentials"
    - "T1578 - Modify Cloud Compute Infrastructure"

# =============================================================================
# TERRAFORM
# =============================================================================
terraform:
  variable_name: "enable_single_account_privesc_one_hop_to_admin_iam_passrole_ec2_runinstances"
  module_path: "modules/scenarios/single-account/privesc-one-hop/to-admin/iam-passrole+ec2-runinstances"
```

---

### Example 3: Multi-Hop Escalation

```yaml
# =============================================================================
# CORE METADATA
# =============================================================================
schema_version: "1.0.0"
name: "putrolepolicy-on-other"
description: "RoleA with iam:PutRolePolicy on RoleB can inject admin policy, then assume RoleB for admin access"
cost_estimate: "$0/mo"


# =============================================================================
# CLASSIFICATION
# =============================================================================
category: "Privilege Escalation"
sub_category: "principal-access"
path_type: "multi-hop"
target: "to-admin"
environments:
  - "prod"

# =============================================================================
# ATTACK PATH
# =============================================================================
attack_path:
  principals:
    - "arn:aws:iam::{account_id}:user/pl-pathfinding-starting-user-prod"
    - "arn:aws:iam::{account_id}:role/pl-prod-role-a-non-admin"
    - "arn:aws:iam::{account_id}:role/pl-prod-role-b-admin"
    - "arn:aws:s3:::pl-prod-admin-demo-bucket-{account_id}"

  summary: "starting_user → (AssumeRole) → role_a → (PutRolePolicy) → role_b → (AssumeRole) → role_b (now admin) → admin access"

# =============================================================================
# PERMISSIONS
# =============================================================================
permissions:
  required:
    - principal: "pl-prod-role-a-non-admin"
      principal_type: "role"
      permissions:
        - permission: "iam:PutRolePolicy"
          resource: "arn:aws:iam::*:role/pl-prod-role-b-admin"

        - permission: "sts:AssumeRole"
          resource: "arn:aws:iam::*:role/pl-prod-role-b-admin"

  helpful:
    - principal: "pl-prod-role-a-non-admin"
      principal_type: "role"
      permissions:
        - permission: "iam:GetRolePolicy"
          purpose: "View existing policies on RoleB"

        - permission: "iam:DeleteRolePolicy"
          purpose: "Clean up injected policies after demo"

        - permission: "s3:ListBuckets"
          purpose: "Discover demo bucket after escalation"

# =============================================================================
# MITRE ATT&CK
# =============================================================================
mitre_attack:
  tactics:
    - "TA0004 - Privilege Escalation"
    - "TA0008 - Lateral Movement"
  techniques:
    - "T1098 - Account Manipulation"
    - "T1078.004 - Cloud Accounts"

# =============================================================================
# TERRAFORM
# =============================================================================
terraform:
  variable_name: "enable_single_account_privesc_multi_hop_to_admin_putrolepolicy_on_other"
  module_path: "modules/scenarios/single-account/privesc-multi-hop/to-admin/putrolepolicy-on-other"
```

---

### Example 4: Credential Access via EC2

```yaml
# =============================================================================
# CORE METADATA
# =============================================================================
schema_version: "1.0.0"
name: "ec2-hardcoded-credentials"
description: "EC2 instance with hardcoded AWS credentials accessible via SSM"
cost_estimate: "$5/mo"


# =============================================================================
# CLASSIFICATION
# =============================================================================
category: "Privilege Escalation"
sub_category: "credential-access"
path_type: "one-hop"
target: "to-admin"
environments:
  - "prod"

# =============================================================================
# ATTACK PATH
# =============================================================================
attack_path:
  principals:
    - "arn:aws:iam::{account_id}:user/pl-pathfinding-starting-user-prod"
    - "arn:aws:ec2:{region}:{account_id}:instance/i-xxxxxxxxx"
    - "arn:aws:iam::{account_id}:user/pl-admin-hardcoded-victim"

  summary: "starting_user → (ssm:StartSession) → EC2 instance → (cat credentials file) → admin credentials → admin access"

# =============================================================================
# PERMISSIONS
# =============================================================================
permissions:
  required:
    - principal: "pl-pathfinding-starting-user-prod"
      principal_type: "user"
      permissions:
        - permission: "ssm:StartSession"
          resource: "arn:aws:ec2:*:*:instance/i-*"

  helpful:
    - principal: "pl-pathfinding-starting-user-prod"
      principal_type: "user"
      permissions:
        - permission: "ec2:DescribeInstances"
          purpose: "Discover target instances"

        - permission: "ssm:DescribeInstanceInformation"
          purpose: "Identify SSM-enabled instances"

# =============================================================================
# MITRE ATT&CK
# =============================================================================
mitre_attack:
  tactics:
    - "TA0006 - Credential Access"
    - "TA0008 - Lateral Movement"
  techniques:
    - "T1552.001 - Unsecured Credentials: Credentials In Files"
    - "T1078.004 - Valid Accounts: Cloud Accounts"

# =============================================================================
# TERRAFORM
# =============================================================================
terraform:
  variable_name: "enable_single_account_privesc_one_hop_to_admin_ec2_hardcoded_credentials"
  module_path: "modules/scenarios/single-account/privesc-one-hop/to-admin/ec2-hardcoded-credentials"
```

---

### Example 5: CTF Scenario

```yaml
# =============================================================================
# CORE METADATA
# =============================================================================
schema_version: "1.3.0"
name: "ai-chatbot-to-admin"
pathfinding-cloud-id: "ctf-001"
title: "AcmeBot"
description: "Acme Corp has deployed an AI-powered customer assistant at a public Lambda endpoint. Escalate to administrative access and retrieve the flag."
cost_estimate: "$1/mo"

# =============================================================================
# CLASSIFICATION
# =============================================================================
category: "CTF"
path_type: "ctf"
target: "to-admin"
environments:
  - "prod"

# =============================================================================
# CTF METADATA
# =============================================================================
ctf:
  difficulty: "beginner"
  flag_location: "SSM Parameter Store at /ctf/ctf-001/flag (requires admin credentials)"
  variant: "ctf-001"

# =============================================================================
# ATTACK PATH
# =============================================================================
attack_path:
  principals:
    - "https://{function_url_id}.lambda-url.{region}.on.aws/ (public chatbot)"
    - "arn:aws:lambda:{region}:{account_id}:function/pl-prod-ctf-001-acmebot"
    - "arn:aws:iam::{account_id}:role/pl-prod-ctf-001-chatbot-role"

  summary: "Browser → AcmeBot chatbot (public URL) → prompt injection → run_command tool (shell exec) → process.env (AWS creds) → chatbot role (AdministratorAccess) → SSM GetParameter → flag"

# =============================================================================
# PERMISSIONS
# =============================================================================
permissions:
  required:
    - principal: "anonymous (public URL)"
      principal_type: "public"
      permissions:
        - permission: "lambda:InvokeFunctionUrl"
          resource: "arn:aws:lambda:*:*:function/pl-prod-ctf-001-acmebot"

  helpful:
    - principal: "pl-prod-ctf-001-starting-user"
      principal_type: "user"
      permissions:
        - permission: "lambda:ListFunctions"
          purpose: "Enumerate Lambda functions to discover the chatbot"
        - permission: "lambda:GetFunctionUrlConfig"
          purpose: "Retrieve the public Function URL for the chatbot"

# =============================================================================
# MITRE ATT&CK
# =============================================================================
mitre_attack:
  tactics:
    - "TA0001 - Initial Access"
    - "TA0006 - Credential Access"
    - "TA0004 - Privilege Escalation"
  techniques:
    - "T1190 - Exploit Public-Facing Application"
    - "T1552.005 - Unsecured Credentials: Cloud Instance Metadata API"
    - "T1059 - Command and Scripting Interpreter"

# =============================================================================
# TERRAFORM
# =============================================================================
terraform:
  variable_name: "enable_ctf_ai_chatbot_to_admin"
  module_path: "modules/scenarios/ctf/ai-chatbot-to-admin"
```

---

### Example 6: Attack Simulation

```yaml
# =============================================================================
# CORE METADATA
# =============================================================================
schema_version: "1.4.0"
name: "sysdig-8-minutes-to-admin"
title: "AI-Assisted Cloud Intrusion: 8 Minutes to Admin"
description: "Recreation of a real-world attack where compromised IAM credentials led to admin access via Lambda code injection in under 8 minutes"
cost_estimate: "$0/mo"

# =============================================================================
# SOURCE METADATA
# =============================================================================
source:
  url: "https://www.sysdig.com/blog/ai-assisted-cloud-intrusion-achieves-admin-access-in-8-minutes"
  title: "AI-Assisted Cloud Intrusion Achieves Admin Access in 8 Minutes"
  author: "Sysdig Threat Research Team"
  date: "2025-06-12"

# =============================================================================
# LAB MODIFICATIONS
# =============================================================================
modifications:
  - "In the original attack, the entry point was a publicly accessible S3 bucket containing embedded IAM credentials. In this lab, the RAG data bucket is private — a starting IAM user is pre-provisioned with read access to avoid publicly exposing real credentials."
  - "In the original attack, the attacker launched GPU instances for unauthorized AI model training. The lab demo replicates this step using the same p3.2xlarge instance type, but the instance auto-terminates after 2 hours as a cost safeguard."

# =============================================================================
# CLASSIFICATION
# =============================================================================
category: "Attack Simulation"
path_type: "attack-simulation"
target: "to-admin"
environments:
  - "prod"

# =============================================================================
# ATTACK PATH
# =============================================================================
attack_path:
  principals:
    - "arn:aws:iam::{account_id}:user/pl-prod-sysdig-8min-starting-user"
    - "arn:aws:iam::{account_id}:role/pl-prod-sysdig-8min-lambda-role"
    - "arn:aws:iam::{account_id}:user/pl-prod-sysdig-8min-admin-user"

  summary: "starting_user (ReadOnlyAccess + Lambda write) → recon → (lambda:UpdateFunctionCode) → Lambda role credentials → (iam:CreateAccessKey) → admin_user credentials → admin access"

# =============================================================================
# PERMISSIONS
# =============================================================================
permissions:
  required:
    - principal: "pl-prod-sysdig-8min-starting-user"
      principal_type: "user"
      permissions:
        - permission: "lambda:UpdateFunctionCode"
          resource: "arn:aws:lambda:*:*:function/pl-prod-sysdig-8min-*"
        - permission: "lambda:UpdateFunctionConfiguration"
          resource: "arn:aws:lambda:*:*:function/pl-prod-sysdig-8min-*"
        - permission: "lambda:InvokeFunction"
          resource: "arn:aws:lambda:*:*:function/pl-prod-sysdig-8min-*"
    - principal: "pl-prod-sysdig-8min-lambda-role"
      principal_type: "role"
      permissions:
        - permission: "iam:CreateAccessKey"
          resource: "arn:aws:iam::*:user/pl-prod-sysdig-8min-admin-user"

  helpful:
    - principal: "pl-prod-sysdig-8min-starting-user"
      principal_type: "user"
      permissions:
        - permission: "iam:ListUsers"
          purpose: "Discover IAM users and identify admin targets"
        - permission: "lambda:ListFunctions"
          purpose: "Discover Lambda functions to target for code injection"
        - permission: "sts:AssumeRole"
          purpose: "Attempt to assume various roles during recon"

# =============================================================================
# MITRE ATT&CK
# =============================================================================
mitre_attack:
  tactics:
    - "TA0007 - Discovery"
    - "TA0002 - Execution"
    - "TA0004 - Privilege Escalation"
    - "TA0003 - Persistence"
    - "TA0006 - Credential Access"
  techniques:
    - "T1526 - Cloud Service Discovery"
    - "T1059 - Command and Scripting Interpreter"
    - "T1098.001 - Account Manipulation: Additional Cloud Credentials"
    - "T1078.004 - Valid Accounts: Cloud Accounts"

# =============================================================================
# TERRAFORM
# =============================================================================
terraform:
  variable_name: "enable_attack_simulation_sysdig_8_minutes_to_admin"
  module_path: "modules/scenarios/attack-simulation/sysdig-8-minutes-to-admin"
```

---

## Guidelines and Best Practices

### 1. Naming Conventions

**Scenario Names:**
- Use kebab-case: `iam-putuserpolicy`, `ec2-hardcoded-credentials`
- Be descriptive but concise
- Include the primary technique/permission: `iam-passrole-lambda-createfunction`
- Match the directory name exactly

**Principal Names:**
- Prefix: `pl-` (Pathfinding Labs)
- Include scenario abbreviation: `pl-cak-` (CreateAccessKey)
- Descriptive suffix: `pl-cak-starting-user`, `pl-cak-admin`

### 2. Cost Estimates

Both `cost_estimate` (idle) and `cost_estimate_when_demo_executed` (demo running) must be present. Always use the `"$X/mo"` format with rounding to the nearest dollar.

**Good:**
- `"$0/mo"` - No AWS charges (IAM-only scenarios)
- `"$1/mo"` - Minimal always-on resources
- `"$9/mo"` - ECS Fargate task
- `"$321/mo"` - Glue dev endpoint

**Bad:**
- `"free"` - Use `"$0/mo"` instead
- `"$5/month"` - Use `"$5/mo"` instead
- `"$0.01/hour"` - Convert to monthly and round
- `"low"` - Too vague
- `"minimal"` - Not specific enough

**When the two values differ:** Set `cost_estimate_when_demo_executed` higher when the demo script provisions resources not in the base Terraform (e.g., EC2 instances, Lambda functions, GPU instances launched during the attack demo). If the demo creates no additional infrastructure, both values should be identical.

### 3. Attack Path Summary

**Do:**
- Include all major steps
- Show the actions/permissions used in parentheses
- End with the access level achieved
- Keep it on one line if possible

**Don't:**
- Include too much detail (save that for README)
- Skip important intermediate steps
- Use complex notation

### 4. Principals List

**Do:**
- List principals in the order they're used
- Include all IAM users, roles, and AWS resources
- Use placeholder variables: `{account_id}`, `{region}`

**Don't:**
- Include the same principal multiple times
- Forget to list important resources (S3 buckets, EC2 instances, etc.)
- Use actual account IDs or regions

### 5. Required vs Helpful Permissions

Both required and helpful permissions are grouped by principal. Each principal entry specifies `principal` (the IAM name), `principal_type` (`"user"` or `"role"`), and a `permissions` array.

**Required Permissions:**
- Must be permissions absolutely necessary to complete the attack
- Without these, the attack cannot succeed
- Focus on the escalation permissions
- Associate each permission with the principal that needs it

**Helpful Permissions:**
- Discovery permissions (List*, Describe*, Get*)
- Verification permissions
- Cleanup permissions
- Not strictly required but make the attack easier
- Associate each permission with the principal that uses it (important for multi-hop scenarios)

**Per-principal grouping matters** because during demo validation runs, a deny policy is temporarily attached to each principal to ensure the attack succeeds with only required permissions. The deny policy needs to know which helpful permissions belong to which principal.

### 6. Setup Hops Don't Count

When determining `path_type`, don't count setup hops:

**Example:**
```yaml
# This is still "one-hop" because the setup hop doesn't count
path_type: "one-hop"
summary: "starting_user → (AssumeRole) → starting_role → (PassRole) → admin"
#          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ setup hop
#                                                    ^^^^^^^^^^^^^ escalation hop (1)
```

### 7. Schema Version

Always include the current schema version at the top of every `scenario.yaml` file:

```yaml
schema_version: "1.0.0"
```

### 8. YAML Formatting

- Use 2-space indentation
- Quote all string values
- Use list format with `-` for arrays
- Add section comment headers for readability

---

## Validation

### Required Field Checklist

Before submitting a scenario, verify all required fields are present:

- [ ] `schema_version`
- [ ] `name`
- [ ] `description`
- [ ] `cost_estimate`
- [ ] `cost_estimate_when_demo_executed`
- [ ] `category`
- [ ] `sub_category`
- [ ] `path_type`
- [ ] `target`
- [ ] `environments`
- [ ] `attack_path.principals`
- [ ] `attack_path.summary`
- [ ] `permissions.required` (at least one principal entry with at least one permission)
- [ ] `mitre_attack.tactics` (at least one entry)
- [ ] `mitre_attack.techniques` (at least one entry)
- [ ] `terraform.variable_name`
- [ ] `terraform.module_path`

### Validation Commands

```bash
# Validate YAML syntax
yamllint scenario.yaml

# Check schema version
grep "schema_version:" scenario.yaml

# Verify all required fields exist
# (validation script to be added)
./scripts/validate_scenario.sh scenario.yaml
```

### Common Errors

**1. Missing required fields**
```yaml
# ❌ Bad - missing cost_estimate
schema_version: "1.0.0"
name: "example"
description: "Example scenario"

# ✅ Good
schema_version: "1.3.0"
name: "example"
description: "Example scenario"
cost_estimate: "$0/mo"
```

**2. Invalid category values**
```yaml
# ❌ Bad - not a valid category
category: "IAM Privilege Escalation"

# ✅ Good
category: "Privilege Escalation"
```

**3. Wrong sub_category for category**
```yaml
# ❌ Bad - "new-passrole" doesn't apply to Toxic Combination
category: "Toxic Combination"
sub_category: "new-passrole"

# ✅ Good
category: "Toxic Combination"
sub_category: "Publicly-accessible"
```

**4. Incorrect hop count**
```yaml
# ❌ Bad - setup hop counted as escalation hop
path_type: "multi-hop"
summary: "user → (AssumeRole) → role → (PassRole) → admin"

# ✅ Good - setup hop not counted
path_type: "one-hop"
summary: "user → (AssumeRole) → role → (PassRole) → admin"
```

---

## Future Extensibility

### Adding New Fields

When adding new optional fields to the schema:

1. Increment minor version: `1.0.0` → `1.1.0`
2. Document the new field in this file
3. Provide default values for backward compatibility
4. Update validation scripts

### Adding New Enum Values

When adding new allowed values (e.g., new categories, sub-categories):

1. Document the new value and when to use it
2. Update this SCHEMA.md file
3. Ensure backward compatibility (existing values still valid)

### Breaking Changes

If making breaking changes (removing fields, changing types):

1. Increment major version: `1.0.0` → `2.0.0`
2. Document migration path from v1 to v2
3. Support both versions during transition period
4. Update all existing scenario.yaml files

---

## Questions or Feedback

For questions about the schema or suggestions for improvements:

1. Open an issue in the repository
2. Reference this SCHEMA.md file in your question
3. Provide examples when possible

**Last Updated:** 2026-04-18
**Schema Version:** 1.6.0
