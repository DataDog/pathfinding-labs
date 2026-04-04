# Lambda Code Update + Invocation to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Modifying existing Lambda function code and manually invoking it to execute malicious logic under privileged execution role
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_lambda_004_lambda_updatefunctioncode_lambda_invokefunction`
* **Schema Version:** 4.0.0
* **Pathfinding.cloud ID:** lambda-004
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1525 - Implant Internal Image

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-lambda-004-to-admin-starting-user` IAM user to the `pl-prod-lambda-004-to-admin-target-role` administrative role by modifying existing Lambda function code with a malicious payload and immediately invoking it to execute arbitrary operations under the function's privileged execution role.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-lambda-004-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-lambda-004-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-lambda-004-to-admin-starting-user`):
- `lambda:UpdateFunctionCode` on `arn:aws:lambda:*:*:function/pl-prod-lambda-004-to-admin-target-lambda` -- replace the existing Lambda function code with a malicious payload
- `lambda:InvokeFunction` on `arn:aws:lambda:*:*:function/pl-prod-lambda-004-to-admin-target-lambda` -- immediately trigger execution of the malicious payload under the function's privileged role

**Helpful** (`pl-prod-lambda-004-to-admin-starting-user`):
- `lambda:GetFunction` -- discover Lambda function details including handler name and execution role
- `lambda:ListFunctions` -- discover available Lambda functions to target
- `iam:GetRole` -- view Lambda execution role permissions to identify high-value targets

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_admin_lambda_004_lambda_updatefunctioncode_lambda_invokefunction
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
| `arn:aws:iam::{account_id}:user/pl-prod-lambda-004-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:lambda:{region}:{account_id}:function/pl-prod-lambda-004-to-admin-target-lambda` | Pre-existing Lambda function that runs benign code (victim workload) |
| `arn:aws:iam::{account_id}:role/pl-prod-lambda-004-to-admin-target-role` | Lambda execution role with AdministratorAccess policy attached |
| Inline policy on starting user | Grants starting user lambda:UpdateFunctionCode and lambda:InvokeFunction permissions |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Verify successful privilege escalation
4. Output standardized test results for automation

#### Resources Created by Attack Script

- Malicious Lambda deployment package (zip file) with attacker-controlled code
- `AdministratorAccess` policy attachment on the starting user

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo lambda-004-lambda-updatefunctioncode+lambda-invokefunction
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup lambda-004-lambda-updatefunctioncode+lambda-invokefunction
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_lambda_004_lambda_updatefunctioncode_lambda_invokefunction
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

- Users or roles with `lambda:UpdateFunctionCode` on highly privileged Lambda functions
- Users or roles with `lambda:InvokeFunction` on the same functions they can update
- Lambda functions whose execution roles have administrative or overly broad permissions
- The combination of Lambda code update permissions, invoke permissions, and privileged execution roles creates a high-severity escalation path
- Lambda functions without code signing enforcement, allowing arbitrary code execution
- Lambda policies without resource-specific conditions that limit which functions can be modified and invoked

#### Prevention Recommendations

- **Implement Code Signing**: Require Lambda functions to use code signing to prevent unauthorized code modifications
- **Apply Least Privilege**: Lambda execution roles should only have permissions required for their specific business function, never AdministratorAccess
- **Restrict Update Permissions**: Limit `lambda:UpdateFunctionCode` to dedicated CI/CD roles with strict condition keys
- **Separate Update and Invoke Permissions**: Never grant both `lambda:UpdateFunctionCode` and `lambda:InvokeFunction` to the same principal for high-privilege functions
- **Use Resource Conditions**: Apply resource-based IAM conditions to restrict which Lambda functions can be modified and invoked by which principals
- **Enable CloudTrail Monitoring**: Alert on `UpdateFunctionCode` and `InvokeFunction` API calls, especially for high-privilege functions, and correlate them to detect suspicious sequences
- **Implement SCPs**: Use Service Control Policies to prevent attachment of administrative policies to Lambda execution roles
- **Separate Deployment and Execution**: Use separate AWS accounts or strict boundaries between deployment infrastructure and production workloads
- **IAM Access Analyzer**: Use AWS IAM Access Analyzer to identify external access and privilege escalation paths involving Lambda functions
- **Version Control Integration**: Implement deployment pipelines that enforce code review and approval before Lambda updates

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `Lambda: UpdateFunctionCode20150331v2` -- Lambda function code modified; high severity when followed by an invocation, especially for functions with privileged execution roles
- `Lambda: Invoke` -- Lambda function invoked; correlate with recent UpdateFunctionCode events to detect attacker-controlled execution
- `IAM: AttachUserPolicy` -- Managed policy attached to an IAM user; critical when the policy grants elevated or administrative access

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
