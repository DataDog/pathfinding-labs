# CloudFormation Stack Set Update to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Modifying existing CloudFormation StackSet to create admin role using StackSet's elevated execution role
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_cloudformation_004_iam_passrole_cloudformation_updatestackset`
* **Schema Version:** 4.0.0
* **Pathfinding.cloud ID:** cloudformation-004
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098 - Account Manipulation, T1098.001 - Account Manipulation: Additional Cloud Credentials

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-cloudformation-004-to-admin-starting-user` IAM user to the `pl-prod-cloudformation-004-to-admin-escalated-role` administrative role by updating an existing CloudFormation StackSet with a malicious template that causes the StackSet's administrative execution role to create a new IAM role with AdministratorAccess that you can assume.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-cloudformation-004-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-cloudformation-004-to-admin-escalated-role`

### Starting Permissions

**Required** (`pl-prod-cloudformation-004-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-cloudformation-004-to-admin-stackset-admin-role` -- allows the user to specify the StackSet administration role when calling UpdateStackSet
- `cloudformation:UpdateStackSet` on `arn:aws:cloudformation:*:*:stackset/pl-prod-cloudformation-004-to-admin-stackset:*` -- allows modifying the StackSet template, which the elevated execution role then applies

**Helpful** (`pl-prod-cloudformation-004-to-admin-starting-user`):
- `cloudformation:DescribeStackSet` -- view StackSet details and verify configuration
- `cloudformation:DescribeStackSetOperation` -- monitor StackSet update operation progress
- `cloudformation:GetTemplate` -- retrieve current StackSet template for modification
- `cloudformation:CreateStackInstances` -- create new stack instances if needed
- `cloudformation:DeleteStackInstances` -- remove stack instances if needed
- `iam:GetRole` -- verify the escalated role was created by the StackSet update
- `sts:AssumeRole` -- assume the escalated role created by StackSet update

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_admin_cloudformation_004_iam_passrole_cloudformation_updatestackset
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
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-cloudformation-004-to-admin-starting-user` | Scenario-specific starting user with access keys and cloudformation:UpdateStackSet permission |
| `arn:aws:cloudformation:{region}:{account_id}:stackset/pl-prod-cloudformation-004-to-admin-stackset:*` | CloudFormation StackSet with administrative execution role |
| `arn:aws:iam::{account_id}:role/pl-prod-cloudformation-004-to-admin-stackset-execution-role` | StackSet execution role with AdministratorAccess policy |
| `arn:aws:iam::{account_id}:role/pl-prod-cloudformation-004-to-admin-escalated-role` | Admin role created during StackSet update (created by demo script) |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve scenario credentials from Terraform outputs
2. Verify the starting user identity and confirm no admin access exists yet
3. Inspect the existing CloudFormation StackSet and its benign template
4. Create a malicious CloudFormation template that adds an IAM role with AdministratorAccess
5. Use `cloudformation:UpdateStackSet` (with `iam:PassRole`) to deploy the modified template
6. Poll until the StackSet update operation completes
7. Assume the newly created escalated admin role
8. Verify administrator access by listing IAM users

#### Resources Created by Attack Script

- New IAM role (`pl-prod-cloudformation-004-to-admin-escalated-role`) with AdministratorAccess policy, created via the StackSet update

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo cloudformation-004-iam-passrole+cloudformation-updatestackset
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup cloudformation-004-iam-passrole+cloudformation-updatestackset
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_cloudformation_004_iam_passrole_cloudformation_updatestackset
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

- IAM user (`pl-prod-cloudformation-004-to-admin-starting-user`) has `cloudformation:UpdateStackSet` permission on a StackSet whose execution role holds AdministratorAccess
- StackSet execution role (`pl-prod-cloudformation-004-to-admin-stackset-execution-role`) is granted AdministratorAccess, enabling privilege escalation via template modification
- Privilege escalation path exists: starting user → UpdateStackSet → execution role → IAM role creation → admin access

#### Prevention Recommendations

- Implement least privilege for StackSet execution roles - avoid granting AdministratorAccess unless absolutely necessary for the StackSet's intended purpose
- Restrict `cloudformation:UpdateStackSet` permissions to specific trusted users or roles using IAM conditions
- Use resource-based conditions to limit which StackSets can be updated: `"Condition": {"StringEquals": {"aws:RequestedRegion": ["us-east-1"]}}`
- Implement Service Control Policies (SCPs) to prevent StackSet execution roles from creating IAM roles or modifying IAM policies
- Enable CloudFormation drift detection to identify unauthorized changes to StackSet configurations
- Use StackSet permission models appropriately - prefer service-managed StackSets over self-managed when possible
- Implement IAM permission boundaries on StackSet execution roles to limit the maximum permissions they can grant
- Enable MFA requirements for sensitive CloudFormation operations using condition keys like `aws:MultiFactorAuthPresent`
- Use IAM Access Analyzer to identify and remediate privilege escalation paths involving CloudFormation StackSets
- Regularly audit StackSet execution roles and their permissions to ensure they follow least privilege principles

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: PassRole` -- Starting user passes the StackSet admin role; indicates the privilege escalation attempt is underway
- `CloudFormation: UpdateStackSet` -- StackSet template modified; high severity when the new template contains IAM resource definitions
- `CloudFormation: DescribeStackSetOperation` -- Attacker polling for operation completion after submitting the update
- `IAM: CreateRole` -- New IAM role created by the StackSet execution role; critical when the new role has AdministratorAccess
- `STS: AssumeRole` -- Starting user assumes the newly created escalated role

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
