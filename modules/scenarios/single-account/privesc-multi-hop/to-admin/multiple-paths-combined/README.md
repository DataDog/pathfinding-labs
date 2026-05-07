# EC2, Lambda, and CloudFormation Chains to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** privilege-chaining
* **Path Type:** multi-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Multiple privilege escalation techniques combined - EC2, Lambda, and CloudFormation paths to admin
* **Terraform Variable:** `enable_single_account_privesc_multi_hop_to_admin_multiple_paths_combined`
* **Schema Version:** 4.6.0
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1578 - Modify Cloud Compute Infrastructure, T1648 - Serverless Execution

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-pathfinding-starting-user-prod` IAM user to a newly created administrative role by assuming `pl-prod-role-with-multiple-privesc-paths` and using `iam:PassRole` combined with EC2, Lambda, or CloudFormation service creation permissions to run a payload under `AdministratorAccess` that provisions a new admin role trusting your starting identity.

- **Start:** `arn:aws:iam::{account_id}:user/pl-pathfinding-starting-user-prod`
- **Destination resource:** `arn:aws:iam::{account_id}:role/new-admin-role`

### Starting Permissions

**Required** (`pl-pathfinding-starting-user-prod`):
- `sts:AssumeRole` on `arn:aws:iam::{account_id}:role/pl-prod-role-with-multiple-privesc-paths` -- initial hop from starting user into the escalation role

**Required** (`pl-prod-role-with-multiple-privesc-paths`):
- `iam:PassRole` on `arn:aws:iam::*:role/*` -- required to attach admin service roles to EC2, Lambda, or CloudFormation
- `ec2:RunInstances` on `*` -- EC2 path: launch an instance with the admin role
- `lambda:CreateFunction` on `*` -- Lambda path: create a function with the admin role
- `cloudformation:CreateStack` on `*` -- CloudFormation path: deploy a stack with the admin role

**Helpful** (`pl-prod-role-with-multiple-privesc-paths`):
- `iam:ListRoles` -- discover available privileged roles in the environment
- `ec2:DescribeInstances` -- verify the EC2 escalation path
- `lambda:ListFunctions` -- verify the Lambda escalation path

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable multiple-paths-combined-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `multiple-paths-combined-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
|-----|---------|
| `arn:aws:iam::{account_id}:role/pl-prod-role-with-multiple-privesc-paths` | Starting escalation role with PassRole + service creation permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-ec2-admin-role` | EC2 service admin role (trusts ec2.amazonaws.com, has AdministratorAccess) |
| `arn:aws:iam::{account_id}:role/pl-prod-lambda-admin-role` | Lambda service admin role (trusts lambda.amazonaws.com, has AdministratorAccess) |
| `arn:aws:iam::{account_id}:role/pl-prod-cloudformation-admin-role` | CloudFormation service admin role (trusts cloudformation.amazonaws.com, has AdministratorAccess) |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/multiple-paths-combined-to-admin` | CTF flag (retrieved using admin access gained via the attack) |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Assume the privilege escalation role (`pl-prod-role-with-multiple-privesc-paths`)
2. Create an EC2 instance with the admin role and payload
3. Create a Lambda function with the admin role and payload
4. Create a CloudFormation stack with the admin role and payload
5. Verify that new admin roles were created by each service
6. Capture the CTF flag from SSM Parameter Store using the gained admin access
7. Clean up all created resources

#### Resources Created by Attack Script

- EC2 instance with `pl-prod-ec2-admin-role` attached (terminated after verification)
- Lambda function using `pl-prod-lambda-admin-role` (deleted after verification)
- CloudFormation stack using `pl-prod-cloudformation-admin-role` (deleted after verification)
- New admin IAM roles created by each service payload (deleted during cleanup)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo multiple-paths-combined
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `multiple-paths-combined-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup multiple-paths-combined
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `multiple-paths-combined-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable multiple-paths-combined-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `multiple-paths-combined-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- `pl-prod-role-with-multiple-privesc-paths` has `iam:PassRole` combined with `ec2:RunInstances`, `lambda:CreateFunction`, and `cloudformation:CreateStack` -- each pairing independently constitutes a privilege escalation path
- Three service-linked admin roles (`pl-prod-ec2-admin-role`, `pl-prod-lambda-admin-role`, `pl-prod-cloudformation-admin-role`) each carry `AdministratorAccess`, making them high-value targets if any role with `iam:PassRole` can reference them
- The starting role can be assumed by a non-privileged IAM user, creating a multi-hop path from a low-privilege identity to full administrative control via three different compute services

#### Prevention Recommendations

- Remove `iam:PassRole` from any role that also holds compute service creation permissions (`ec2:RunInstances`, `lambda:CreateFunction`, `cloudformation:CreateStack`); these combinations are always privilege escalation paths
- Apply permission boundaries to service execution roles so that even if they carry `AdministratorAccess` in their trust/attached policies, a boundary prevents IAM write operations
- Use SCPs to restrict `iam:PassRole` to specific, approved role ARN patterns (e.g., only roles prefixed with `svc-`) rather than allowing `*`
- Enforce least-privilege on CloudFormation stack creation by requiring a `cloudformation:RoleArn` condition that limits which roles can be assumed by CloudFormation
- Audit all roles holding both `iam:PassRole` and any compute creation permission quarterly; alert on any new grant of this combination
- Tag service admin roles with a sensitivity label and enforce that only approved automation can assume or pass them

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `sts:AssumeRole` -- initial role assumption from starting user into the escalation role; alert when a low-privilege user assumes a role with PassRole + compute creation permissions
- `ec2:RunInstances` -- EC2 instance launched with an IAM instance profile attached; high severity when the profile role carries AdministratorAccess
- `lambda:CreateFunction20150331` -- Lambda function created with an execution role; alert when the role has AdministratorAccess
- `lambda:Invoke` -- Lambda function invoked shortly after creation; escalation payload likely executing
- `cloudformation:CreateStack` -- stack created with an explicit role ARN; alert when the role has AdministratorAccess and `CAPABILITY_NAMED_IAM` is used
- `iam:CreateRole` -- new IAM role created from within an EC2 instance, Lambda function, or CloudFormation stack execution context; strong indicator of payload success
- `iam:AttachRolePolicy` -- AdministratorAccess or similar managed policy attached to a newly created role
- `sts:AssumeRole` -- assumption of the newly created admin role by the original starting user identity; confirms successful escalation

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
