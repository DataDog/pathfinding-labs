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

### Current Version: `1.2.0`

The schema follows semantic versioning:

- **Major** (`x.0.0`): Breaking changes (e.g., removing required fields, changing field types)
- **Minor** (`1.x.0`): Backward-compatible additions (e.g., new optional fields)
- **Patch** (`1.0.x`): Clarifications, documentation updates, no schema changes

### Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.2.0 | 2025-11-03 | Added `pathfinding-cloud-id` to help map scenarios with Pathfinding.cloud paths when applicable. |
| 1.1.0 | 2025-10-21 | Added `cross-account` path_type; Changed `no-hop` to `self-escalation`; Added `privilege-chaining` and `cross-account-escalation` sub_categories; Added principal counting rules |
| 1.0.0 | 2025-10-21 | Initial schema release |


---

## Complete Field Reference

### Core Metadata

Fundamental information about the scenario.

```yaml
schema_version: "1.0.0"
name: "iam-putuserpolicy"
description: "Principal with iam:PutUserPolicy can attach inline admin policy to escalate privileges"
cost_estimate: "free"
pathfinding-cloud-id: IAM-005
```

#### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `schema_version` | string | ✅ Yes | Schema version this file conforms to. Format: `"X.Y.Z"` |
| `name` | string | ✅ Yes | Unique identifier for the scenario. Should match directory name. Use kebab-case. |
| `description` | string | ✅ Yes | One-line description of the scenario. Should be concise (< 150 chars). |
| `cost_estimate` | string | ✅ Yes | Estimated AWS cost to run this scenario on a monthly basis. Use `"free"` or actual cost like `"$5.00/month"` |
| `pathfinding-cloud-id` | string | No | ID of Pathfinding.cloud path ID if one exists. | 

#### Cost Estimate Examples

- `"free"` - No AWS charges (IAM-only scenarios)
- `"$5/month"` - Monthly estimations for anything pay per time unit type resource

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
| `sub_category` | string | ✅ Yes | Specific technique or finding type |
| `path_type` | string | ✅ Yes | Number of privilege escalation hops |
| `target` | string | ✅ Yes | Ultimate goal of the attack |
| `environments` | array | ✅ Yes | List of AWS accounts involved |

#### Allowed Values

##### `category`

| Value | Description | Use Case |
|-------|-------------|----------|
| `"Privilege Escalation"` | Attack leads to elevated permissions | Most privilege escalation scenarios |
| `"Regular Finding"` | Security misconfiguration without direct escalation | Overly permissive policies, exposed resources |
| `"Toxic Combination"` | Multiple misconfigurations that amplify risk | Public Lambda + Admin Role, etc. |
| `"Tool Testing"` | Edge cases and detection engine testing scenarios | Test CSPM/detection tools for false positives/negatives, edge cases in policy parsing |

##### `sub_category`

**For `category: "Privilege Escalation"`:**

| Value | Description | Example Techniques |
|-------|-------------|-------------------|
| `"self-escalation"` | Principal modifies its own permissions (path_type: self-escalation only) | `iam:PutUserPolicy`, `iam:AttachUserPolicy` on self |
| `"principal-lateral-movement"` | One principal accesses another principal (one-hop or multi-hop) | `iam:PutRolePolicy` on another role, single technique used across hops |
| `"service-passrole"` | Pass privileged role to AWS service (one-hop or multi-hop) | `iam:PassRole` + `lambda:CreateFunction`, `iam:PassRole` + `ec2:RunInstances` |
| `"access-resource"` | Access existing resources, mostly workloads (one-hop) | `sts:AssumeRole` to admin role, `ssm:StartSession` to EC2 with admin role |
| `"credential-access"` | Access to hardcoded credentials with a resource (one-hop or multi-hop) | `ssm:StartSession` to EC2 with hardcoded creds, `lambda:GetFunction` with creds in environment |
| `"privilege-chaining"` | Multiple escalation techniques chained together (multi-hop only) | Mixed techniques like PassRole → PutRolePolicy → AssumeRole |
| `"cross-account-escalation"` | Privilege escalation spanning AWS accounts (cross-account only) | Any technique that crosses account boundaries |

**For `category: "Toxic Combination"` or `"Regular Finding"`:**

| Value | Description | Example |
|-------|-------------|---------|
| `"Publicly-accessible"` | Resource exposed to internet | Public S3 bucket, public Lambda URL |
| `"sensitive-data"` | Resource contains sensitive information | S3 bucket with PII, PHI, credentials, secrets |
| `"contains-vulnerability"` | Resource has known CVE or misconfiguration | Unpatched instance, vulnerable container |
| `"overly-permissive"` | Permissions broader than necessary | Wildcards in policies, `*:*` permissions |

**For `category: "Tool Testing"`:**

| Value | Description | Example |
|-------|-------------|---------|
| `"edge-case-detection"` | Tests detection engine's ability to handle edge cases | Resource policies that bypass IAM, complex condition keys |
| `"false-positive-test"` | Scenarios that may trigger false positive alerts | Legitimate configurations that appear vulnerable |
| `"policy-parsing-edge-case"` | Complex policy structures that test parsing engines | Nested conditions, complex NotAction statements |

##### `path_type`

| Value | Description | When to Use |
|-------|-------------|-------------|
| `"self-escalation"` | Principal modifies its own permissions | 1 principal total (the principal modifies itself) |
| `"one-hop"` | Single privilege escalation step | 2 principals total (Principal A → Principal B) |
| `"multi-hop"` | Multiple privilege escalation steps | 3+ principals total (Principal A → B → C → ...) |
| `"cross-account"` | Attack spans multiple AWS accounts | Escalation crosses account boundaries (takes precedence over hop count) |

**Principal Counting Rules:**
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

Required and helpful AWS IAM permissions for executing the attack.

```yaml
permissions:
  required:
    - permission: "iam:PutUserPolicy"
      resource: "*"

  helpful:
    - permission: "iam:GetUser"
      purpose: "View user details and verify policy attachment"
```

#### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `required` | array | ✅ Yes | Permissions absolutely required to execute the attack |
| `helpful` | array | ❌ No | Permissions that aid in discovery, verification, or cleanup |

#### Required Permissions

Each required permission entry:

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
  # Simple permission
  - permission: "iam:CreateAccessKey"
    resource: "*"

  # Permission with specific resource
  - permission: "iam:PassRole"
    resource: "arn:aws:iam::*:role/pl-EC2Admin"

  # Multiple actions on same resource
  - permission: "ec2:RunInstances"
    resource: "*"

  - permission: "iam:PassRole"
    resource: "arn:aws:iam::*:role/*"
```

#### Helpful Permissions

Each helpful permission entry:

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

**Single-Account Format**: `enable_single_account_{category_pathtype}_{target}_{technique}`

**Cross-Account Format**: `enable_cross_account_{source_to_dest}_{hop_type}_{technique}`

**Tool Testing Format**: `enable_tool_testing_{technique}`

**Examples:**

```yaml
# Self-escalation (single-account)
variable_name: "enable_single_account_privesc_self_escalation_to_admin_iam_putrolepolicy"
variable_name: "enable_single_account_privesc_self_escalation_to_bucket_iam_putrolepolicy"

# One-hop (single-account)
variable_name: "enable_single_account_privesc_one_hop_to_admin_iam_createaccesskey"
variable_name: "enable_single_account_privesc_one_hop_to_bucket_sts_assumerole"

# Multi-hop (single-account)
variable_name: "enable_single_account_privesc_multi_hop_to_admin_putrolepolicy_on_other"
variable_name: "enable_single_account_privesc_multi_hop_to_bucket_role_chain_to_s3"

# Toxic combo (single-account)
variable_name: "enable_single_account_toxic_combo_public_lambda_with_admin"

# Tool testing
variable_name: "enable_tool_testing_resource_policy_bypass"
variable_name: "enable_tool_testing_exclusive_resource_policy"

# Cross-account (no target in variable name)
variable_name: "enable_cross_account_dev_to_prod_one_hop_simple_role_assumption"
variable_name: "enable_cross_account_dev_to_prod_multi_hop_passrole_lambda_admin"
variable_name: "enable_cross_account_ops_to_prod_one_hop_simple_role_assumption"
```

#### Module Path

Path from project root to the scenario directory (without trailing slash).

**Examples:**

```yaml
# Standard path
module_path: "modules/scenarios/single-account/privesc-one-hop/to-admin/iam-putuserpolicy"

# Multi-hop
module_path: "modules/scenarios/single-account/privesc-multi-hop/to-admin/putrolepolicy-on-other"

# Tool testing
module_path: "modules/scenarios/tool-testing/resource-policy-bypass"
module_path: "modules/scenarios/tool-testing/exclusive-resource-policy"

# Cross-account
module_path: "modules/scenarios/cross-account/dev-to-prod/one-hop/simple-role-assumption"

# Credential access
module_path: "modules/scenarios/single-account/credential-access/ec2-hardcoded-credentials"
```

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
cost_estimate: "free"
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
    - permission: "iam:CreateAccessKey"
      resource: "arn:aws:iam::*:user/pl-cak-admin"

  helpful:
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
cost_estimate: "free"

# =============================================================================
# CLASSIFICATION
# =============================================================================
category: "Privilege Escalation"
sub_category: "service-passrole"
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
    - permission: "iam:PassRole"
      resource: "arn:aws:iam::*:role/pl-EC2Admin"

    - permission: "ec2:RunInstances"
      resource: "*"

  helpful:
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
cost_estimate: "free"


# =============================================================================
# CLASSIFICATION
# =============================================================================
category: "Privilege Escalation"
sub_category: "principal-lateral-movement"
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
    - permission: "iam:PutRolePolicy"
      resource: "arn:aws:iam::*:role/pl-prod-role-b-admin"

    - permission: "sts:AssumeRole"
      resource: "arn:aws:iam::*:role/pl-prod-role-b-admin"

  helpful:
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
cost_estimate: "$5.00/month"


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
    - permission: "ssm:StartSession"
      resource: "arn:aws:ec2:*:*:instance/i-*"

  helpful:
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

Be realistic and specific:

**Good:**
- `"free"` - No AWS charges
- `"$0.01/hour"` - Single t3.nano instance
- `"$0.50/day"` - Multiple small resources
- `"$5/month"` - Lambda + API Gateway with minimal usage

**Bad:**
- `"low"` - Too vague
- `"minimal"` - Not specific enough
- `"cheap"` - Subjective

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

**Required Permissions:**
- Must be permissions absolutely necessary to complete the attack
- Without these, the attack cannot succeed
- Focus on the escalation permissions

**Helpful Permissions:**
- Discovery permissions (List*, Describe*, Get*)
- Verification permissions
- Cleanup permissions
- Not strictly required but make the attack easier

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
- [ ] `category`
- [ ] `sub_category`
- [ ] `path_type`
- [ ] `target`
- [ ] `environments`
- [ ] `attack_path.principals`
- [ ] `attack_path.summary`
- [ ] `permissions.required` (at least one entry)
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
schema_version: "1.0.0"
name: "example"
description: "Example scenario"
cost_estimate: "free"
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
# ❌ Bad - "service-passrole" doesn't apply to Toxic Combination
category: "Toxic Combination"
sub_category: "service-passrole"

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

**Last Updated:** 2025-01-21
**Schema Version:** 1.1.0
