# Lambda Function Creation + Permission Grant to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Creating Lambda function with admin role and granting self-invocation permission to execute malicious code
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_lambda_006_iam_passrole_lambda_createfunction_lambda_addpermission`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** lambda-006
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1648 - Serverless Execution

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-lambda-006-to-admin-starting-user` IAM user to the `pl-prod-lambda-006-to-admin-target-role` administrative role by creating a malicious Lambda function with the admin role as its execution role, granting yourself invocation rights via `lambda:AddPermission`, and invoking the function to attach `AdministratorAccess` to your starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-lambda-006-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-lambda-006-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-lambda-006-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-lambda-006-to-admin-target-role` -- allows assigning the admin role as the Lambda execution role
- `lambda:CreateFunction` on `*` -- allows creating a new Lambda function
- `lambda:AddPermission` on `*` -- allows adding a resource-based policy granting invocation rights
- `lambda:InvokeFunction` on `*` -- allows invoking the Lambda function once permissions are set

**Helpful** (`pl-prod-lambda-006-to-admin-starting-user`):
- `iam:ListRoles` -- discover available privileged roles
- `lambda:GetFunction` -- verify function creation and retrieve details
- `lambda:GetPolicy` -- verify resource-based policy was added
- `lambda:DeleteFunction` -- clean up attack artifacts

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew tap DataDog/pathfinding-labs https://github.com/DataDog/pathfinding-labs
   brew install DataDog/pathfinding-labs/plabs
   ```
   Or with Go 1.25+ installed:
   ```bash
   go install github.com/DataDog/pathfinding-labs/cmd/plabs@latest
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable lambda-006-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-006-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-lambda-006-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-lambda-006-to-admin-target-role` | Admin role that can be passed to Lambda functions |
| Policy attached to starting user | Grants `iam:PassRole` on target role, `lambda:CreateFunction`, `lambda:AddPermission`, and `lambda:InvokeFunction` |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/lambda-006-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Verify successful privilege escalation
4. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions


#### Resources Created by Attack Script

- A malicious Lambda function with the admin target role as its execution role
- A resource-based policy statement on the Lambda function granting the starting user invocation rights
- `AdministratorAccess` policy attached to the starting user

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo lambda-006-iam-passrole+lambda-createfunction+lambda-addpermission
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-006-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup lambda-006-iam-passrole+lambda-createfunction+lambda-addpermission
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-006-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable lambda-006-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-006-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user has `iam:PassRole` permission targeting a role with administrative privileges
- IAM user has `lambda:CreateFunction` permission allowing creation of functions with privileged roles
- IAM user has `lambda:AddPermission` allowing modification of Lambda resource-based policies
- Privilege escalation path detected: user can combine PassRole + CreateFunction + AddPermission + InvokeFunction to achieve admin access
- Lambda execution role `pl-prod-lambda-006-to-admin-target-role` has administrative permissions and is passable by a non-admin principal

#### Prevention Recommendations

- Restrict `iam:PassRole` permissions using strict resource conditions to limit which roles can be passed to Lambda
- Implement condition keys like `iam:PassedToService` to restrict PassRole specifically to `lambda.amazonaws.com` only when necessary
- Avoid granting broad `lambda:CreateFunction` permissions; use resource tags or naming patterns to limit function creation scope
- Implement Service Control Policies (SCPs) that prevent passing roles with administrative permissions to Lambda functions
- Use IAM Access Analyzer to identify privilege escalation paths involving PassRole and Lambda permissions
- Enable AWS Config rules to detect Lambda functions with overly permissive execution roles or resource-based policies

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `lambda:CreateFunction20150331` -- new Lambda function created; inspect the `role` field in request parameters to identify the role being passed — a privileged role ARN here is the CloudTrail signal for PassRole; high severity when the role has administrative privileges
- `lambda:AddPermission20150331v2` -- resource-based policy added to a Lambda function; suspicious when the principal granting rights is the same as the function creator
- `lambda:Invoke` -- Lambda function invoked; correlate with preceding CreateFunction and AddPermission events for full attack chain

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
