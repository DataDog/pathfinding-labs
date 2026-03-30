# Privilege Escalation via iam:PassRole + lambda:CreateFunction + lambda:CreateEventSourceMapping (DynamoDB Stream)

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Pathfinding.cloud ID:** lambda-002
* **Technique:** Pass privileged role to Lambda function, link to DynamoDB stream for passive execution without requiring InvokeFunction permission
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_lambda_002_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb`
* **Schema Version:** 1.0.0
* **Attack Path:** starting_user → (PassRole + CreateFunction) → Lambda with target role → (CreateEventSourceMapping) → DynamoDB stream trigger → Lambda executes → (AttachUserPolicy) → admin access
* **Attack Principals:** `arn:aws:iam::{account_id}:user/pl-prod-lambda-002-to-admin-starting-user`; `arn:aws:iam::{account_id}:role/pl-prod-lambda-002-to-admin-target-role`; `arn:aws:lambda:{region}:{account_id}:function/malicious-escalation-function`; `arn:aws:dynamodb:{region}:{account_id}:table/pl-prod-lambda-002-to-admin-trigger-table`
* **Required Permissions:** `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-lambda-002-to-admin-target-role`; `lambda:CreateFunction` on `*`; `lambda:CreateEventSourceMapping` on `*`
* **Helpful Permissions:** `dynamodb:ListStreams` (Discover available DynamoDB streams to target); `dynamodb:DescribeStream` (Get stream ARN and configuration details); `dynamodb:DescribeTable` (Get table details including stream ARN); `lambda:ListFunctions` (Verify Lambda function creation); `lambda:GetFunction` (Confirm function configuration and role); `lambda:GetEventSourceMapping` (Check event source mapping status and verify activation); `iam:ListRoles` (Discover privileged roles available for PassRole); `dynamodb:PutItem` (Trigger Lambda execution by inserting test record (demo only))
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1578 - Modify Cloud Compute Infrastructure

## Attack Overview

This scenario demonstrates a sophisticated privilege escalation vulnerability where a user has permissions to create Lambda functions and pass privileged roles to them, combined with the ability to create event source mappings to DynamoDB streams. Unlike traditional Lambda-based privilege escalation that requires `lambda:InvokeFunction`, this technique leverages event-driven architecture to trigger execution passively.

The attacker creates a Lambda function with a privileged role attached, then connects it to a DynamoDB stream. When any data is written to the table (either by the attacker inserting a test record or by legitimate application activity), the Lambda function executes automatically with the privileged role's permissions. This makes the attack stealthier as it doesn't require direct function invocation and can piggyback on normal business operations.

This pattern is particularly dangerous in production environments where DynamoDB tables receive frequent updates from applications, microservices, or automated processes. The attacker's malicious Lambda function will execute every time the table is modified, potentially going unnoticed among legitimate Lambda invocations.

### MITRE ATT&CK Mapping

- **Tactic**: Privilege Escalation (TA0004), Persistence (TA0003)
- **Technique**: T1098.001 - Account Manipulation: Additional Cloud Credentials
- **Technique**: T1578 - Modify Cloud Compute Infrastructure
- **Sub-technique**: Creating serverless functions with elevated privileges for passive execution

### Principals in the attack path

- `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-lambda-002-to-admin-starting-user` (Scenario-specific starting user)
- `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-lambda-002-to-admin-target-role` (Privileged role with AdministratorAccess)
- `arn:aws:lambda:REGION:PROD_ACCOUNT:function/malicious-escalation-function` (Attacker-created Lambda function)
- `arn:aws:dynamodb:REGION:PROD_ACCOUNT:table/pl-prod-lambda-002-to-admin-trigger-table` (DynamoDB table with streams enabled)

### Attack Path Diagram

```mermaid
graph LR
    A[pl-prod-lambda-002-to-admin-starting-user] -->|lambda:CreateFunction + iam:PassRole| B[Lambda Function with Target Role]
    B -->|lambda:CreateEventSourceMapping| C[DynamoDB Stream Trigger]
    C -->|Event triggers Lambda execution| D[Lambda executes with admin role]
    D -->|iam:AttachUserPolicy| E[Starting user gains admin access]

    style A fill:#ff9999,stroke:#333,stroke-width:2px
    style B fill:#ffcc99,stroke:#333,stroke-width:2px
    style C fill:#ffcc99,stroke:#333,stroke-width:2px
    style D fill:#ffcc99,stroke:#333,stroke-width:2px
    style E fill:#99ff99,stroke:#333,stroke-width:2px
```

### Attack Steps

1. **Initial Access**: Start as `pl-prod-lambda-002-to-admin-starting-user` (credentials provided via Terraform outputs)
2. **Create Malicious Lambda Code**: Write Lambda function code that attaches AdministratorAccess policy to the starting user
3. **Package Lambda Deployment**: Create deployment package (ZIP file) containing the malicious code
4. **Create Lambda Function**: Use `lambda:CreateFunction` with `iam:PassRole` to create function with privileged target role
5. **Link to DynamoDB Stream**: Use `lambda:CreateEventSourceMapping` to connect Lambda to DynamoDB table stream
6. **Trigger Execution**: Insert a test record into DynamoDB table to trigger Lambda execution (or wait for legitimate activity)
7. **Automatic Privilege Escalation**: Lambda executes with target role permissions and grants admin access to starting user
8. **Verification**: Verify administrator access with starting user credentials

### Scenario specific resources created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-lambda-002-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-lambda-002-to-admin-target-role` | Privileged role with AdministratorAccess policy |
| `arn:aws:iam::PROD_ACCOUNT:policy/pl-prod-lambda-002-to-admin-starting-policy` | Allows PassRole, CreateFunction, CreateEventSourceMapping permissions |
| `arn:aws:dynamodb:REGION:PROD_ACCOUNT:table/pl-prod-lambda-002-to-admin-trigger-table` | DynamoDB table with streams enabled to trigger Lambda execution |

## Attack Lab

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_admin_lambda_002_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `space` to enable it
4. Press `d` to deploy

### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Verify successful privilege escalation
4. Output standardized test results for automation

#### Resources created by attack script

- Malicious Lambda function (`malicious-escalation-function`) with the privileged target role attached
- Lambda event source mapping linking the function to the DynamoDB stream
- AdministratorAccess policy attachment on the starting user (granted by the Lambda execution)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo lambda-002-iam-passrole+lambda-createfunction+createeventsourcemapping-dynamodb
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup lambda-002-iam-passrole+lambda-createfunction+createeventsourcemapping-dynamodb
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_lambda_002_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Detecting Misconfiguration (CSPM)

### What CSPM tools should detect

- IAM user has `iam:PassRole` permission scoped to a role with `AdministratorAccess`, enabling privilege escalation via Lambda
- IAM user has `lambda:CreateFunction` combined with `iam:PassRole` on a privileged role — a known privilege escalation path
- IAM user has `lambda:CreateEventSourceMapping` allowing passive trigger of attacker-controlled Lambda functions
- Role `pl-prod-lambda-002-to-admin-target-role` with `AdministratorAccess` is passable by a non-administrative user
- DynamoDB table has streams enabled and is accessible as an event source for Lambda functions, increasing the attack surface

### Prevention recommendations

- **Restrict PassRole permissions**: Use resource-based conditions to limit which roles can be passed to Lambda functions. Implement a condition like `"StringEquals": {"iam:PassedToService": "lambda.amazonaws.com"}` combined with specific role ARN restrictions.
- **Implement Service Control Policies (SCPs)**: Prevent creation of Lambda functions with administrative roles at the organization level using SCPs that deny `lambda:CreateFunction` when PassRole is used with privileged roles.
- **Restrict CreateEventSourceMapping**: Limit which principals can create event source mappings, especially for DynamoDB streams that process sensitive data. Use resource-based policies on DynamoDB tables to control stream access.
- **Enable Lambda function signing**: Require code signing for Lambda functions to prevent unauthorized code deployment.
- **Use IAM Access Analyzer**: Regularly scan for privilege escalation paths involving PassRole and Lambda creation permissions. IAM Access Analyzer can identify these risky permission combinations.
- **Implement least privilege for Lambda roles**: Ensure Lambda execution roles have only the minimum permissions needed. Avoid attaching AdministratorAccess or broad policies to roles that can be passed to Lambda.
- **Monitor DynamoDB stream consumers**: Track which Lambda functions are consuming DynamoDB streams and alert on new or unexpected event source mappings, especially to tables containing sensitive data.
- **Use resource tags and conditions**: Tag Lambda execution roles appropriately and use IAM conditions to prevent high-privilege roles from being passed to Lambda functions (e.g., `"StringNotEquals": {"aws:ResourceTag/Privilege": "High"}`).

## Detection Abuse (CloudSIEM)

### CloudTrail events to monitor

- `IAM: PassRole` — Starting user passes a privileged role to a Lambda function; high severity when the passed role has admin permissions
- `Lambda: CreateFunction20150331` — New Lambda function created with a privileged execution role; critical when combined with PassRole activity
- `Lambda: CreateEventSourceMapping` — Lambda function linked to a DynamoDB stream trigger; suspicious when the function was recently created by a low-privilege user
- `DynamoDB: PutItem` — Record inserted into the trigger table; may indicate attacker-initiated Lambda execution
- `IAM: AttachUserPolicy` — AdministratorAccess policy attached to a user; confirms successful privilege escalation

### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
