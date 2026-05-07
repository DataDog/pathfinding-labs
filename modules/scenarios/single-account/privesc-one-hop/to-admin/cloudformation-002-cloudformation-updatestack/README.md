# CloudFormation Stack Update to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Modifying existing CloudFormation stack to create admin role using stack's elevated service role
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_cloudformation_002_cloudformation_updatestack`
* **Schema Version:** 4.6.0
* **CTF Flag Location:** ssm-parameter
* **Pathfinding.cloud ID:** cloudformation-002
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098 - Account Manipulation, T1098.001 - Account Manipulation: Additional Cloud Credentials

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-cloudformation-002-to-admin-starting-user` IAM user to the `pl-prod-cloudformation-002-to-admin-escalated-role` administrative role by modifying an existing CloudFormation stack whose attached service role has `AdministratorAccess`, causing the stack to create a new IAM role that you can then assume.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-cloudformation-002-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-cloudformation-002-to-admin-escalated-role`

### Starting Permissions

**Required** (`pl-prod-cloudformation-002-to-admin-starting-user`):
- `cloudformation:UpdateStack` on `arn:aws:cloudformation:*:*:stack/pl-prod-cloudformation-002-to-admin-stack/*` -- allows modifying the stack template, which executes under the stack's administrative service role

**Helpful** (`pl-prod-cloudformation-002-to-admin-starting-user`):
- `cloudformation:DescribeStacks` -- view stack details and verify stack configuration
- `cloudformation:GetTemplate` -- retrieve the current stack template for modification
- `iam:GetRole` -- verify the escalated role was created by the stack update

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable cloudformation-002-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `cloudformation-002-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-cloudformation-002-to-admin-starting-user` | Scenario-specific starting user with access keys and cloudformation:UpdateStack permission |
| `arn:aws:iam::{account_id}:role/pl-prod-cloudformation-002-to-admin-stack-role` | CloudFormation service role with AdministratorAccess used by the stack |
| `arn:aws:cloudformation:{region}:{account_id}:stack/pl-prod-cloudformation-002-to-admin-stack/*` | CloudFormation stack that can be updated by the starting user |
| `arn:aws:iam::{account_id}:role/pl-prod-cloudformation-002-to-admin-escalated-role` | Admin role created during stack update (created by demo script) |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve scenario credentials from Terraform outputs
2. Verify the starting user identity and confirm no admin access yet
3. Inspect the existing CloudFormation stack and its current (benign) template
4. Construct a malicious CloudFormation template that adds an IAM role with `AdministratorAccess` and a trust policy allowing the starting user to assume it
5. Call `cloudformation:UpdateStack` with the malicious template and `CAPABILITY_NAMED_IAM`
6. Wait for the stack update to complete, then wait 15 seconds for IAM propagation
7. Assume the newly created escalated role using `sts:AssumeRole`
8. Verify administrator access by listing IAM users

#### Resources Created by Attack Script

- New IAM role (`pl-prod-cloudformation-002-to-admin-escalated-role`) with `AdministratorAccess` policy, created via CloudFormation stack update
- Modified CloudFormation stack (`pl-prod-cloudformation-002-to-admin-stack`) with the malicious template applied
- Temporary template file at `/tmp/malicious-stack-template.json`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo cloudformation-002-cloudformation-updatestack
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `cloudformation-002-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup cloudformation-002-cloudformation-updatestack
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `cloudformation-002-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable cloudformation-002-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `cloudformation-002-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM principal has `cloudformation:UpdateStack` permission on a stack with an administrative service role attached
- CloudFormation stack service role has `AdministratorAccess` or equivalent IAM write permissions, creating a privilege escalation path for any user who can update the stack
- Privilege escalation path detected: starting user can create IAM roles and policies indirectly via CloudFormation stack update

#### Prevention Recommendations

- Implement least privilege principles for CloudFormation service roles -- avoid granting `AdministratorAccess` when more granular permissions suffice
- Restrict `cloudformation:UpdateStack` permissions to specific users/roles who require infrastructure management capabilities
- Use CloudFormation stack policies to prevent modifications to sensitive resources: `"Effect": "Deny", "Principal": "*", "Action": "Update:*", "Resource": "LogicalResourceId/SensitiveRole"`
- Implement Service Control Policies (SCPs) to restrict CloudFormation stack updates that create or modify IAM resources
- Use resource-based conditions to limit `UpdateStack` permissions to specific stacks: `"Condition": {"StringEquals": {"cloudformation:StackId": "arn:aws:cloudformation:*:*:stack/approved-stack/*"}}`
- Enable CloudFormation drift detection and implement change approval workflows for stack updates that modify IAM resources
- Require MFA for CloudFormation updates using the `aws:MultiFactorAuthPresent` condition key
- Use IAM Access Analyzer to identify and remediate privilege escalation paths involving CloudFormation permissions

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `cloudformation:UpdateStack` -- CloudFormation stack update executed; high severity when the stack has an elevated service role and the update modifies IAM resources
- `iam:CreateRole` -- New IAM role created; critical when triggered by a CloudFormation stack execution with an administrative service role
- `iam:AttachRolePolicy` -- Managed policy attached to a role; critical when `AdministratorAccess` or other high-privilege policies are attached via CloudFormation
- `sts:AssumeRole` -- Role assumption; investigate when the assumed role was recently created by a CloudFormation stack update

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
