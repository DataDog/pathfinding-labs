# Pathfinding Labs Scenario Reference

## Scenario Taxonomy

### Categories

| Category | Description |
|----------|-------------|
| `privilege-escalation` | IAM privilege escalation attack paths |
| `cspm-misconfig` | Single-condition security misconfigurations for CSPM detection |
| `cspm-toxic-combo` | Multiple compounding misconfigurations |
| `tool-testing` | Edge cases for testing detection engine capabilities |

### Subcategories (within privilege-escalation)

| Subcategory | Description |
|-------------|-------------|
| `self-escalation` | Principal escalates its own permissions |
| `one-hop` | Single principal traversal to reach target |
| `multi-hop` | Multiple principal traversals chained together |
| `cross-account` | Attack paths spanning multiple AWS accounts |

### Targets

| Target | Description |
|--------|-------------|
| `to-admin` | Escalation to full admin privileges |
| `to-bucket` | Escalation to sensitive S3 bucket access |

---

## Scenario ID System

Every scenario has a **pathfinding-cloud-id** (e.g., `iam-002`) defined in its `scenario.yaml`.

When a scenario exists in both `to-admin` and `to-bucket` variants, use the **unique ID**:
- `iam-002-to-admin`
- `iam-002-to-bucket`

The `plabs` CLI accepts both base IDs and unique IDs. If you provide a base ID that matches
multiple variants, the CLI will prompt — use the unique ID to be explicit.

---

## Available Scenarios (Summary)

### Self-Escalation to Admin (8 scenarios)
- `iam-001` — iam:CreatePolicyVersion
- `iam-005` — iam:PutRolePolicy (also has to-bucket variant)
- `iam-007` — iam:PutUserPolicy
- `iam-008` — iam:AttachUserPolicy
- `iam-009` — iam:AttachRolePolicy (also has to-bucket variant)
- `iam-010` — iam:AttachGroupPolicy
- `iam-011` — iam:PutGroupPolicy
- `iam-013` — iam:AddUserToGroup

### One-Hop to Admin (57+ scenarios)
- `iam-002` — iam:CreateAccessKey for admin user
- `iam-003` — iam:DeleteAccessKey + iam:CreateAccessKey
- `iam-004` — iam:CreateLoginProfile
- `iam-006` — iam:UpdateLoginProfile
- `iam-012` — iam:UpdateAssumeRolePolicy
- `sts-001` — sts:AssumeRole directly
- Plus many covering Lambda, EC2, ECS, Glue, CodeBuild, CloudFormation, SageMaker, SSM, AppRunner, Bedrock

### One-Hop to Bucket (11 scenarios)
Variants of iam-002, iam-012, sts-001, and others targeting S3 access.

### Multi-Hop to Admin (1 scenario)
- `multiple-paths-combined` — EC2, Lambda, CloudFormation paths

### Multi-Hop to Bucket (1 scenario)
- `role-chain-to-s3` — Three-hop role chain to S3

### Toxic Combo (1 scenario)
- `public-lambda-with-admin` — Public Lambda + admin role

### Tool Testing (5 scenarios)
- `resource-policy-bypass`
- `exclusive-resource-policy`
- `test-effective-permissions-evaluation`
- `test-reverse-blast-radius-direct-and-indirect-through-admin`
- `test-reverse-blast-radius-direct-and-indirect-to-bucket`

### Cross-Account (6 scenarios)
- `dev-to-prod/simple-role-assumption`
- `dev-to-prod/root-trust-role-assumption`
- `dev-to-prod/passrole-lambda-admin`
- `dev-to-prod/multi-hop-both-sides`
- `dev-to-prod/lambda-invoke-update`
- `ops-to-prod/simple-role-assumption`

---

## Scenario Directory Layout

Each scenario lives under `modules/scenarios/` within the pathfinding-labs repo:

```
modules/scenarios/
├── single-account/
│   ├── privesc-self-escalation/
│   │   ├── to-admin/
│   │   │   └── iam-005-iam-putrolepolicy/
│   │   │       ├── main.tf
│   │   │       ├── variables.tf
│   │   │       ├── outputs.tf
│   │   │       ├── scenario.yaml        ← metadata
│   │   │       ├── README.md
│   │   │       ├── demo_attack.sh
│   │   │       └── cleanup_attack.sh
│   │   └── to-bucket/ ...
│   ├── privesc-one-hop/
│   │   ├── to-admin/ ...
│   │   └── to-bucket/ ...
│   ├── privesc-multi-hop/ ...
│   ├── cspm-misconfig/ ...
│   └── cspm-toxic-combo/ ...
├── tool-testing/ ...
└── cross-account/
    ├── dev-to-prod/ ...
    └── ops-to-prod/ ...
```

---

## scenario.yaml Schema

```yaml
schema_version: "1.0"
name: "Human-readable name"
description: "What this scenario demonstrates"
cost_estimate: "$5/mo"
pathfinding-cloud-id: "iam-002"          # the base ID
category: "privilege-escalation"
sub_category: "one-hop"
target: "to-admin"                       # or "to-bucket"
environments:
  - "prod"                               # accounts required
attack_path:
  principals:
    - "attacker"
  summary: "Description of the attack path"
permissions:
  required:
    - permission: "iam:CreateAccessKey"
      resource: "arn:aws:iam::*:user/*"
  helpful: []
mitre_attack:
  tactics:
    - "Privilege Escalation"
  techniques:
    - "T1098.001 - Account Manipulation: Additional Cloud Credentials"
terraform:
  variable_name: "enable_iam_002_to_admin"
  module_path: "modules/scenarios/single-account/privesc-one-hop/to-admin/iam-002-iam-createaccesskey"
interactive_demo: false
```

---

## Resource Naming Convention

All Pathfinding Labs AWS resources use the `pl-` prefix:

- Standard: `pl-{description}-{context}` → `pl-cak-admin`
- Globally unique (S3): `pl-{resource}-{account-id}-{random-6}` → `pl-sensitive-data-123456789012-a3f9x2`

Starting users per environment:
- `pl-pathfinding-starting-user-prod`
- `pl-pathfinding-starting-user-dev`
- `pl-pathfinding-starting-user-operations`
