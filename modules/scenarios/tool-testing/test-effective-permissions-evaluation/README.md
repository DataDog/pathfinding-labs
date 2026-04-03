# Comprehensive Effective Permissions Evaluation Testing

* **Category:** Tool Testing
* **Sub-Category:** edge-case-detection
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Testing security tool accuracy in evaluating effective permissions across 40 principals with admin patterns, denies, boundaries, multi-policy scenarios, and edge cases
* **Terraform Variable:** `enable_tool_testing_test_effective_permissions_evaluation`
* **Schema Version:** 4.0.0
* **MITRE Tactics:** TA0009 - Collection, TA0004 - Privilege Escalation
* **MITRE Techniques:** T1530 - Data from Cloud Storage Object, T1078.004 - Valid Accounts: Cloud Accounts

## Objective

Your objective is to learn how to validate security tool accuracy by deploying 40 carefully crafted IAM principals — 15 with effective admin access and 24 restricted by denies or permissions boundaries — and measuring whether your CSPM or IAM analyzer correctly classifies every principal against the `pl-sensitive-data-epe-{account_id}-{suffix}` S3 bucket.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-epe-starting-user`
- **Destination resource:** `arn:aws:s3:::pl-sensitive-data-epe-{account_id}-{suffix}`

### Starting Permissions

**Required** (`pl-prod-epe-starting-user`):
- `*` on `*` -- 15 isAdmin principals have effective `*` on `*` via various policy mechanisms (AWS managed, customer managed, inline, group membership, split policies)
- `*` on `*` (blocked) -- 24 notAdmin principals hold `AdministratorAccess` but are restricted by explicit denies or permissions boundaries

**Helpful** (`pl-prod-epe-starting-user`):
- `sts:GetCallerIdentity` -- verify assumed identity
- `sts:AssumeRole` -- starting user assumes test roles to validate effective permissions at runtime

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_tool_testing_test_effective_permissions_evaluation
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `space` to enable it
4. Press `d` to deploy

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
|-----|---------|
| `arn:aws:iam::{account_id}:user/pl-prod-epe-starting-user` | Starting user; can assume all 39 test principals |
| `arn:aws:iam::{account_id}:user/pl-prod-epe-user-isAdmin-awsmanaged` | AWS managed AdministratorAccess |
| `arn:aws:iam::{account_id}:user/pl-prod-epe-user-isAdmin-customermanaged` | Customer managed admin policy |
| `arn:aws:iam::{account_id}:user/pl-prod-epe-user-isAdmin-inline` | Inline admin policy |
| `arn:aws:iam::{account_id}:user/pl-prod-epe-user-isAdmin-via-group-awsmanaged` | Group with AWS managed admin |
| `arn:aws:iam::{account_id}:user/pl-prod-epe-user-isAdmin-via-group-customermanaged` | Group with customer managed admin |
| `arn:aws:iam::{account_id}:user/pl-prod-epe-user-isAdmin-via-group-inline` | Group with inline admin |
| `arn:aws:iam::{account_id}:user/pl-prod-epe-user-isAdmin-split-iam-and-notiam` | Split policies: `iam:*` + `NotAction iam:*` |
| `arn:aws:iam::{account_id}:user/pl-prod-epe-user-isAdmin-split-s3-and-nots3` | Split policies: `s3:*` + `NotAction s3:*` |
| `arn:aws:iam::{account_id}:user/pl-prod-epe-user-isAdmin-many-services-combined` | Many service wildcards = `*` |
| `arn:aws:iam::{account_id}:role/pl-prod-epe-role-isAdmin-awsmanaged` | Role: AWS managed AdministratorAccess |
| `arn:aws:iam::{account_id}:role/pl-prod-epe-role-isAdmin-customermanaged` | Role: customer managed admin policy |
| `arn:aws:iam::{account_id}:role/pl-prod-epe-role-isAdmin-inline` | Role: inline admin policy |
| `arn:aws:iam::{account_id}:role/pl-prod-epe-role-isAdmin-split-iam-and-notiam` | Role: split policies `iam:*` + `NotAction iam:*` |
| `arn:aws:iam::{account_id}:role/pl-prod-epe-role-isAdmin-split-s3-and-nots3` | Role: split policies `s3:*` + `NotAction s3:*` |
| `arn:aws:iam::{account_id}:role/pl-prod-epe-role-isAdmin-many-services-combined` | Role: many service wildcards = `*` |
| `arn:aws:iam::{account_id}:user/pl-prod-epe-user-notAdmin-adminpolicy-plus-denyall` | Admin + Deny `*` on `*` |
| `arn:aws:iam::{account_id}:user/pl-prod-epe-user-notAdmin-adminpolicy-plus-denynotaction` | Admin + Deny `*` on `*` (NotAction variant) |
| `arn:aws:iam::{account_id}:user/pl-prod-epe-user-notAdmin-admin-plus-denynotaction-ec2only` | Admin + Deny NotAction `[ec2:DescribeInstances]` |
| `arn:aws:iam::{account_id}:user/pl-prod-epe-user-notAdmin-adminpolicy-plus-deny-split-iam-notiam` | Admin + split denies |
| `arn:aws:iam::{account_id}:user/pl-prod-epe-user-notAdmin-adminpolicy-plus-deny-incremental` | Admin + many incremental service denies |
| `arn:aws:iam::{account_id}:user/pl-prod-epe-user-notAdmin-split-allow-plus-denyall` | Split allows + Deny all |
| `arn:aws:iam::{account_id}:user/pl-prod-epe-user-notAdmin-admin-plus-boundary-allows-nothing` | Admin + deny-all boundary |
| `arn:aws:iam::{account_id}:user/pl-prod-epe-user-notAdmin-adminpolicy-plus-boundary-ec2only` | Admin + EC2-only boundary |
| `arn:aws:iam::{account_id}:user/pl-prod-epe-user-notAdmin-admin-plus-boundary-na-ec2only` | Admin + boundary NotAction |
| `arn:aws:iam::{account_id}:user/pl-prod-epe-user-notAdmin-split-allow-boundary-allows-nothing` | Split allows + deny-all boundary |
| `arn:aws:iam::{account_id}:user/pl-prod-epe-user-notAdmin-split-allow-boundary-ec2only` | Split allows + EC2 boundary |
| `arn:aws:iam::{account_id}:user/pl-prod-epe-user-notAdmin-split-boundary-mismatch` | Policy-boundary no intersection |
| `arn:aws:iam::{account_id}:role/pl-prod-epe-role-notAdmin-adminpolicy-plus-denyall` | Role: Admin + Deny `*` on `*` |
| `arn:aws:iam::{account_id}:role/pl-prod-epe-role-notAdmin-adminpolicy-plus-denynotaction` | Role: Admin + Deny `*` on `*` (NotAction variant) |
| `arn:aws:iam::{account_id}:role/pl-prod-epe-role-notAdmin-adminpolicy-plus-denynotaction-ec2only` | Role: Admin + Deny NotAction `[ec2:DescribeInstances]` |
| `arn:aws:iam::{account_id}:role/pl-prod-epe-role-notAdmin-adminpolicy-plus-deny-split-iam-notiam` | Role: Admin + split denies |
| `arn:aws:iam::{account_id}:role/pl-prod-epe-role-notAdmin-adminpolicy-plus-deny-incremental` | Role: Admin + many incremental service denies |
| `arn:aws:iam::{account_id}:role/pl-prod-epe-role-notAdmin-split-allow-plus-denyall` | Role: Split allows + Deny all |
| `arn:aws:iam::{account_id}:role/pl-prod-epe-role-notAdmin-admin-plus-boundary-allows-nothing` | Role: Admin + deny-all boundary |
| `arn:aws:iam::{account_id}:role/pl-prod-epe-role-notAdmin-adminpolicy-plus-boundary-ec2only` | Role: Admin + EC2-only boundary |
| `arn:aws:iam::{account_id}:role/pl-prod-epe-role-notAdmin-admin-plus-boundary-na-ec2only` | Role: Admin + boundary NotAction |
| `arn:aws:iam::{account_id}:role/pl-prod-epe-role-notAdmin-split-allow-boundary-allows-nothing` | Role: Split allows + deny-all boundary |
| `arn:aws:iam::{account_id}:role/pl-prod-epe-role-notAdmin-split-allow-boundary-ec2only` | Role: Split allows + EC2 boundary |
| `arn:aws:iam::{account_id}:role/pl-prod-epe-role-notAdmin-split-boundary-mismatch` | Role: Policy-boundary no intersection |
| `arn:aws:s3:::pl-sensitive-data-epe-{account_id}-{suffix}` | Target resource for access validation |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

This scenario focuses on CSPM detection validation. The demo script tests all 39 principals (excluding starting user).

The script will:
1. Retrieve credentials for all principals from Terraform outputs
2. Test each principal's ability to access S3 (list bucket) and IAM (list users)
3. Determine effective admin status based on both S3 and IAM access
4. Compare actual results with expected results (admin vs not-admin)
5. Generate a comprehensive test report with pass/fail counts
6. Output summary statistics for isAdmin and notAdmin categories

**Expected Results:**
- **15 isAdmin principals**: Should have both S3 and IAM access (admin)
- **24 notAdmin principals**: Should have neither S3 nor IAM access (not-admin)
- **Total tests**: 39 principals tested

#### Resources Created by Attack Script

- No persistent attack artifacts are created; the script only reads credentials and tests access against existing resources

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo test-effective-permissions-evaluation
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

This scenario creates no persistent attack artifacts. All resources are managed by Terraform.

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup test-effective-permissions-evaluation
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_tool_testing_test_effective_permissions_evaluation
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

A comprehensive CSPM or IAM analysis tool should correctly identify:

**Must Detect as Admin (15 principals)**

Single Policy (6):
- All principals with AdministratorAccess (AWS managed, customer managed, or inline)

Group Membership (3):
- All users whose groups have admin policies (AWS managed, customer managed, inline)

Multi-Policy (6):
- Principals with split policies that together equal `*` on `*`:
  - `iam:*` + `NotAction iam:*` = `*`
  - `s3:*` + `NotAction s3:*` = `*`
  - Many service wildcards that collectively cover all AWS services

**Must Detect as Not Admin (24 principals)**

Single Deny (6):
- Admin policy + Deny `*` on `*`
- Admin policy + Deny `*` on `*` (alternative implementation)
- Admin policy + Deny NotAction `[ec2:DescribeInstances]` (denies everything except one action)

Multi-Deny (6):
- Admin policy + Deny `iam:*` + Deny NotAction `iam:*` (split denies = deny all)
- Admin policy + many incremental service denies (together = deny all)
- Split allow policies + Deny `*` on `*`

Single Boundary (6):
- Admin policy + boundary with deny-all statement (allows nothing)
- Admin policy + boundary allowing only `ec2:DescribeInstances` (too restrictive)
- Admin policy + boundary NotAction `[ec2:DescribeInstances]` (allows only one action)

Multi-Policy with Boundary (6):
- Split allow policies + boundary allowing nothing (boundary blocks all)
- Split allow policies + EC2-only boundary (boundary too restrictive)
- Policy allows S3/EC2 + boundary allows IAM/Lambda (no intersection = no permissions)

**Critical Test Cases for Tool Validation**

These scenarios are particularly important for distinguishing excellent tools from mediocre ones:

1. **Split Policy Aggregation**: Does your tool correctly aggregate `iam:*` + `NotAction iam:*` to recognize this equals full admin?
2. **Many Services Combined**: Does your tool aggregate multiple service wildcards (e.g., iam:*, s3:*, ec2:*, lambda:*, ...) to determine they collectively equal `*`?
3. **Explicit Deny All**: Does your tool correctly identify that `Deny * on *` blocks all access regardless of allow statements?
4. **Split Denies**: Does your tool recognize that `Deny iam:*` + `Deny NotAction iam:*` together deny everything?
5. **Boundary Intersection**: Does your tool correctly calculate effective permissions as the intersection of identity policies and boundaries?
6. **Deny-Only Boundary**: Does your tool recognize that a boundary with only deny statements allows nothing, regardless of identity policies?
7. **Boundary Mismatch**: Does your tool detect when identity policies and boundaries have zero overlap, resulting in no effective permissions?
8. **Group Inheritance**: Does your tool correctly evaluate permissions inherited through group memberships?

**Tool Testing Goals**

This scenario helps answer critical questions about your security tooling:

1. **Policy Aggregation**: Does your tool correctly aggregate multiple policies from different sources?
2. **NotAction Logic**: Does your tool properly evaluate NotAction statements in both allows and denies?
3. **Deny Precedence**: Does your tool correctly apply deny-always-wins logic?
4. **Boundary Evaluation**: Does your tool understand permissions boundaries and calculate intersection correctly?
5. **Group Membership**: Does your tool follow group membership chains to evaluate inherited permissions?
6. **False Positive Rate**: How many notAdmin principals does your tool incorrectly flag as admin?
7. **False Negative Rate**: How many isAdmin principals does your tool miss?
8. **Edge Case Handling**: Does your tool handle empty boundaries, split policies, and mismatch scenarios?

**Expected Results Summary**

| Category | Total | Expected Admin | Expected Not-Admin |
|----------|-------|----------------|-------------------|
| isAdmin: Single Policy | 6 | 6 | 0 |
| isAdmin: Group Membership | 3 | 3 | 0 |
| isAdmin: Multi-Policy | 6 | 6 | 0 |
| notAdmin: Single Deny | 6 | 0 | 6 |
| notAdmin: Multi-Deny | 6 | 0 | 6 |
| notAdmin: Single Boundary | 6 | 0 | 6 |
| notAdmin: Multi-Policy + Boundary | 6 | 0 | 6 |
| **Total (excluding starting user)** | **39** | **15** | **24** |

#### Prevention Recommendations

While this is a tool-testing scenario rather than a vulnerability demonstration, the configurations illustrate important security principles:

- **Principle of Least Privilege**: Grant only the minimum permissions necessary. Avoid broad administrative access unless absolutely required.
- **Avoid Complex Multi-Policy Scenarios**: While `iam:*` + `NotAction iam:*` technically equals `*`, this complexity makes security reviews difficult. Use explicit `*` on `*` if admin is needed.
- **Use Permissions Boundaries Carefully**: Boundaries are powerful but complex. Ensure clear documentation of intended intersection between identity policies and boundaries.
- **Explicit Denies for Guardrails**: Use deny statements to create hard boundaries, but avoid overly complex NotAction denies that are difficult to audit.
- **Group Membership Auditing**: Regularly audit group memberships, as users inherit all group permissions. A seemingly restricted user may have admin through group membership.
- **Test Before Deploying**: Use IAM Policy Simulator or Access Analyzer to validate complex policies before deployment. Ensure effective permissions match intent.
- **Document Admin Definitions**: Clearly define what "admin" means in your organization. Is it `*` on `*`? Is it specific privilege escalation paths? Document and test against this definition.
- **Regular Access Reviews**: Periodically review all principals with administrative access. Check identity policies, group memberships, boundaries, and denies.
- **Validate Your CSPM**: Use scenarios like this to validate your security tooling can accurately detect all admin access patterns, including complex multi-policy scenarios.
- **Monitor Policy Changes**: Use CloudTrail to monitor changes to IAM policies, group memberships, permissions boundaries, and role trust policies. Alert on unexpected modifications.
- **Use IAM Access Analyzer**: Leverage AWS IAM Access Analyzer to identify resources shared with external entities and validate IAM policies before deployment (Policy Validation feature).

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `STS: AssumeRole` — Starting user assumes test roles during evaluation; monitor for unexpected role assumption patterns
- `S3: GetObject` — Access to the test S3 bucket; isAdmin principals should succeed, notAdmin should be blocked
- `S3: ListBucket` — Listing the test S3 bucket contents during access validation
- `IAM: ListUsers` — IAM read access used to validate effective permissions for admin principals

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
