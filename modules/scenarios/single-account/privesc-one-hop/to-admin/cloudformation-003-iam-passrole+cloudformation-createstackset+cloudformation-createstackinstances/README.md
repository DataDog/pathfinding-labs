# Privilege Escalation via iam:PassRole + cloudformation:CreateStackSet + cloudformation:CreateStackInstances

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Passing administrative execution role to CloudFormation StackSet to create escalated IAM resources
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_cloudformation_003_iam_passrole_cloudformation_createstackset_cloudformation_createstackinstances`
* **Schema Version:** 3.0.0
* **Pathfinding.cloud ID:** cloudformation-003
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-cloudformation-003-to-admin-starting-user` IAM user to the `pl-prod-cloudformation-003-to-admin-escalated-role` administrative role by passing an administrative execution role to a CloudFormation StackSet that creates an escalated IAM role you can then assume.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-cloudformation-003-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-cloudformation-003-to-admin-escalated-role`

### Starting Permissions

**Required:**
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-cloudformation-003-to-admin-execution-role` -- pass the privileged execution role to CloudFormation
- `cloudformation:CreateStackSet` on `*` -- create a new StackSet configured with the execution role
- `cloudformation:CreateStackInstances` on `*` -- deploy a stack instance to trigger resource creation

**Helpful:**
- `cloudformation:DescribeStackSet` -- monitor StackSet creation progress
- `cloudformation:DescribeStackSetOperation` -- check StackSet operation status
- `cloudformation:ListStackInstances` -- list stack instances for cleanup
- `cloudformation:DeleteStackInstances` -- delete stack instances during cleanup
- `cloudformation:DeleteStackSet` -- clean up attack artifacts
- `iam:ListRoles` -- discover available privileged roles to pass
- `iam:GetRole` -- verify the escalated role was created
- `sts:AssumeRole` -- assume the escalated role for admin access

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_admin_cloudformation_003_iam_passrole_cloudformation_createstackset_cloudformation_createstackinstances
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
| `arn:aws:iam::{account_id}:user/pl-prod-cloudformation-003-to-admin-starting-user` | Scenario-specific starting user with access keys, iam:PassRole, and cloudformation:CreateStackSet permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-cloudformation-003-to-admin-execution-role` | Privileged execution role with AdministratorAccess policy that can be passed to StackSets |
| `arn:aws:iam::{account_id}:role/pl-prod-cloudformation-003-to-admin-escalated-role` | Escalated admin role created by the StackSet with full administrative permissions |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Create a CloudFormation template defining an escalated IAM role
4. Create a StackSet and deploy a stack instance with the execution role
5. Wait for the StackSet operation to complete
6. Assume the escalated role and verify administrative access
7. Output standardized test results for automation

#### Resources Created by Attack Script

- A CloudFormation StackSet with the privileged execution role passed via `iam:PassRole`
- A stack instance deployed into the current account and region
- An escalated IAM role (`pl-prod-cloudformation-003-to-admin-escalated-role`) with full administrative permissions and a trust policy allowing the starting user to assume it

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo cloudformation-003-iam-passrole+cloudformation-createstackset+cloudformation-createstackinstances
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup cloudformation-003-iam-passrole+cloudformation-createstackset+cloudformation-createstackinstances
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_cloudformation_003_iam_passrole_cloudformation_createstackset_cloudformation_createstackinstances
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

- IAM principal has `iam:PassRole` permission on a role with `AdministratorAccess` or equivalent administrative policy attached
- IAM principal has both `iam:PassRole` and `cloudformation:CreateStackSet` permissions, enabling indirect privilege escalation via StackSet execution roles
- IAM principal has `cloudformation:CreateStackInstances` permission, completing the StackSet-based escalation chain
- CloudFormation execution role has `AdministratorAccess` or broad `iam:*` permissions, making it a high-risk target for PassRole abuse

#### Prevention Recommendations

- Implement strict least privilege for `iam:PassRole` permissions - use resource-based conditions to limit which roles can be passed: `"Resource": "arn:aws:iam::*:role/approved-stackset-roles/*"`
- Restrict `cloudformation:CreateStackSet` permissions to only authorized infrastructure automation principals
- Apply permission boundaries to StackSet execution roles to limit what resources they can create, even with administrative policies attached
- Use Service Control Policies (SCPs) to prevent StackSet execution roles from creating IAM resources: `"Effect": "Deny", "Action": ["iam:CreateRole", "iam:PutRolePolicy"], "Resource": "*"`
- Implement CloudFormation stack policies and StackSet operation preferences to require approval workflows for IAM resource creation
- Use AWS IAM Access Analyzer to identify roles with overly permissive PassRole capabilities
- Consider using CloudFormation service-managed StackSets with Organizations, which provide more controlled permission models than self-managed StackSets
- Enable MFA requirements for sensitive CloudFormation operations using condition keys like `aws:MultiFactorAuthPresent`
- Regularly audit StackSet execution roles to ensure they follow least privilege principles and have appropriate permission boundaries

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: PassRole` -- Starting user passes the privileged execution role to CloudFormation; critical when the target role has administrative permissions
- `CloudFormation: CreateStackSet` -- A new StackSet is created; high severity when accompanied by a PassRole event for an admin-level execution role
- `CloudFormation: CreateStackInstances` -- Stack instances are deployed; triggers actual resource creation in the target account and region
- `IAM: CreateRole` -- A new IAM role is created by the StackSet execution role; indicates potential privilege escalation via CloudFormation
- `STS: AssumeRole` -- Attacker assumes the newly created escalated role to gain admin access

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
