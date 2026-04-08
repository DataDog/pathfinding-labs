# Lambda Function Creation + DynamoDB Event Source to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Pass privileged role to Lambda function, link to DynamoDB stream for passive execution without requiring InvokeFunction permission
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_lambda_002_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb`
* **Schema Version:** 4.1.1
* **Pathfinding.cloud ID:** lambda-002
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1578 - Modify Cloud Compute Infrastructure

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-lambda-002-to-admin-starting-user` IAM user to the `pl-prod-lambda-002-to-admin-target-role` administrative role by creating a Lambda function with a privileged execution role and passively triggering it via a DynamoDB stream event source mapping — no `lambda:InvokeFunction` permission required.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-lambda-002-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-lambda-002-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-lambda-002-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-lambda-002-to-admin-target-role` -- pass the privileged target role to a Lambda function
- `lambda:CreateFunction` on `*` -- create a Lambda function with the privileged role as its execution role
- `lambda:CreateEventSourceMapping` on `*` -- link the Lambda function to a DynamoDB stream to trigger it passively

**Helpful** (`pl-prod-lambda-002-to-admin-starting-user`):
- `dynamodb:ListStreams` -- discover available DynamoDB streams to target
- `dynamodb:DescribeStream` -- get stream ARN and configuration details
- `dynamodb:DescribeTable` -- get table details including stream ARN
- `lambda:ListFunctions` -- verify Lambda function creation
- `lambda:GetFunction` -- confirm function configuration and role
- `lambda:GetEventSourceMapping` -- check event source mapping status and verify activation
- `iam:ListRoles` -- discover privileged roles available for PassRole
- `dynamodb:PutItem` -- trigger Lambda execution by inserting test record (demo only)

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable lambda-002-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-002-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-lambda-002-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-lambda-002-to-admin-target-role` | Privileged role with AdministratorAccess policy |
| `arn:aws:iam::{account_id}:policy/pl-prod-lambda-002-to-admin-starting-policy` | Allows PassRole, CreateFunction, CreateEventSourceMapping permissions |
| `arn:aws:dynamodb:{region}:{account_id}:table/pl-prod-lambda-002-to-admin-trigger-table` | DynamoDB table with streams enabled to trigger Lambda execution |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Verify successful privilege escalation
4. Output standardized test results for automation

#### Resources Created by Attack Script

- Malicious Lambda function (`pl-prod-lambda-002-malicious-lambda`) with the privileged target role attached
- Lambda event source mapping linking the function to the DynamoDB stream
- AdministratorAccess policy attachment on the starting user (granted by the Lambda execution)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo lambda-002-iam-passrole+lambda-createfunction+createeventsourcemapping-dynamodb
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-002-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup lambda-002-iam-passrole+lambda-createfunction+createeventsourcemapping-dynamodb
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-002-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable lambda-002-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-002-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user has `iam:PassRole` permission scoped to a role with `AdministratorAccess`, enabling privilege escalation via Lambda
- IAM user has `lambda:CreateFunction` combined with `iam:PassRole` on a privileged role — a known privilege escalation path
- IAM user has `lambda:CreateEventSourceMapping` allowing passive trigger of attacker-controlled Lambda functions
- Role `pl-prod-lambda-002-to-admin-target-role` with `AdministratorAccess` is passable by a non-administrative user
- DynamoDB table has streams enabled and is accessible as an event source for Lambda functions, increasing the attack surface

#### Prevention Recommendations

- **Restrict PassRole permissions**: Use resource-based conditions to limit which roles can be passed to Lambda functions. Implement a condition like `"StringEquals": {"iam:PassedToService": "lambda.amazonaws.com"}` combined with specific role ARN restrictions.
- **Implement Service Control Policies (SCPs)**: Prevent creation of Lambda functions with administrative roles at the organization level using SCPs that deny `lambda:CreateFunction` when PassRole is used with privileged roles.
- **Restrict CreateEventSourceMapping**: Limit which principals can create event source mappings, especially for DynamoDB streams that process sensitive data. Use resource-based policies on DynamoDB tables to control stream access.
- **Enable Lambda function signing**: Require code signing for Lambda functions to prevent unauthorized code deployment.
- **Use IAM Access Analyzer**: Regularly scan for privilege escalation paths involving PassRole and Lambda creation permissions. IAM Access Analyzer can identify these risky permission combinations.
- **Implement least privilege for Lambda roles**: Ensure Lambda execution roles have only the minimum permissions needed. Avoid attaching AdministratorAccess or broad policies to roles that can be passed to Lambda.
- **Monitor DynamoDB stream consumers**: Track which Lambda functions are consuming DynamoDB streams and alert on new or unexpected event source mappings, especially to tables containing sensitive data.
- **Use resource tags and conditions**: Tag Lambda execution roles appropriately and use IAM conditions to prevent high-privilege roles from being passed to Lambda functions (e.g., `"StringNotEquals": {"aws:ResourceTag/Privilege": "High"}`).

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: PassRole` — Starting user passes a privileged role to a Lambda function; high severity when the passed role has admin permissions
- `Lambda: CreateFunction20150331` — New Lambda function created with a privileged execution role; critical when combined with PassRole activity
- `Lambda: CreateEventSourceMapping` — Lambda function linked to a DynamoDB stream trigger; suspicious when the function was recently created by a low-privilege user
- `DynamoDB: PutItem` — Record inserted into the trigger table; may indicate attacker-initiated Lambda execution
- `IAM: AttachUserPolicy` — AdministratorAccess policy attached to a user; confirms successful privilege escalation

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
