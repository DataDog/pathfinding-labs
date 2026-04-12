# Lambda Function Creation + Invocation to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Creating Lambda function with admin role and invoking it to extract temporary credentials
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_lambda_001_iam_passrole_lambda_createfunction_lambda_invokefunction`
* **Schema Version:** 4.1.1
* **Pathfinding.cloud ID:** lambda-001
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1648 - Serverless Execution

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-lambda-001-to-admin-starting-user` IAM user to the `pl-prod-lambda-001-to-admin-target-role` administrative role by creating a Lambda function with the admin execution role and invoking it to extract temporary credentials.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-lambda-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-lambda-001-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-lambda-001-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-lambda-001-to-admin-target-role` -- allows associating the admin role as the Lambda execution role
- `lambda:CreateFunction` on `*` -- allows creating a new Lambda function
- `lambda:InvokeFunction` on `*` -- allows invoking the Lambda function to extract credentials

**Helpful** (`pl-prod-lambda-001-to-admin-starting-user`):
- `iam:ListRoles` -- discover available privileged roles that can be passed to Lambda
- `lambda:GetFunction` -- verify function creation succeeded before invoking
- `lambda:DeleteFunction` -- clean up attack artifacts after credential extraction

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable lambda-001-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-001-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-lambda-001-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-lambda-001-to-admin-target-role` | Admin role that can be passed to Lambda functions |
| Policy attached to starting user | Grants `iam:PassRole` on target role, `lambda:CreateFunction`, and `lambda:InvokeFunction` |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Verify successful privilege escalation


#### Resources Created by Attack Script

- A temporary Lambda function (`pl-lambda-001-credential-extractor`) created with the admin execution role to extract credentials

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo lambda-001-iam-passrole+lambda-createfunction+lambda-invokefunction
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-001-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup lambda-001-iam-passrole+lambda-createfunction+lambda-invokefunction
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-001-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable lambda-001-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-001-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user has `iam:PassRole` permission allowing it to pass an administrative role to Lambda
- IAM user has `lambda:CreateFunction` permission enabling creation of functions with privileged execution roles
- IAM user has `lambda:InvokeFunction` permission enabling execution of functions that can exfiltrate credentials
- Privilege escalation path exists: starting user can gain admin privileges via Lambda execution role

#### Prevention Recommendations

- Restrict `iam:PassRole` permissions using strict resource conditions to limit which roles can be passed
- Implement condition keys like `iam:PassedToService` to restrict PassRole to specific AWS services only when necessary
- Avoid granting broad `lambda:CreateFunction` permissions; use resource tags or naming patterns to limit function creation
- Implement Service Control Policies (SCPs) that prevent passing roles with administrative permissions to Lambda
- Use IAM Access Analyzer to identify privilege escalation paths involving PassRole
- Enable AWS Config rules to detect Lambda functions with overly permissive execution roles

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: PassRole` -- Starting user passes an administrative role to a Lambda function; critical when the target role has elevated permissions
- `Lambda: CreateFunction20150331` -- New Lambda function created with a privileged execution role; high severity when the execution role has admin access
- `Lambda: Invoke` -- Lambda function invoked; high severity when preceded by CreateFunction with a privileged role

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
