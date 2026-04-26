# Lambda Code Update + Access Key Creation to Admin

* **Category:** Privilege Escalation
* **Path Type:** multi-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Update Lambda function code to exfiltrate execution role credentials, then use those credentials to create access keys for an admin user
* **Terraform Variable:** `enable_single_account_privesc_multi_hop_to_admin_lambda_004_to_iam_002`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** lambda-004 + iam-002
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution, TA0006 - Credential Access
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1059 - Command and Scripting Interpreter

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-lambda-004-to-iam-002-starting-user` IAM user to the `pl-prod-lambda-004-to-iam-002-admin-user` administrative IAM user by injecting credential-exfiltration code into a Lambda function to steal its execution role credentials and then using those credentials to create permanent access keys for the admin user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-lambda-004-to-iam-002-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:user/pl-prod-lambda-004-to-iam-002-admin-user`

### Starting Permissions

**Required** (`pl-prod-lambda-004-to-iam-002-starting-user`):
- `lambda:UpdateFunctionCode` on `arn:aws:lambda:*:*:function:pl-prod-lambda-004-to-iam-002-target-function` -- replace the function's code with a credential exfiltration payload
- `lambda:InvokeFunction` on `arn:aws:lambda:*:*:function:pl-prod-lambda-004-to-iam-002-target-function` -- execute the modified function to receive the execution role's temporary credentials

**Required** (`pl-prod-lambda-004-to-iam-002-lambda-role`):
- `iam:CreateAccessKey` on `arn:aws:iam::*:user/pl-prod-lambda-004-to-iam-002-admin-user` -- used in the second hop to create permanent admin credentials after exfiltrating this role's credentials from the Lambda execution environment

**Helpful** (`pl-prod-lambda-004-to-iam-002-starting-user`):
- `lambda:ListFunctions` -- discover available Lambda functions to target
- `lambda:GetFunction` -- view function details including the execution role ARN
- `lambda:GetFunctionConfiguration` -- view function configuration details

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable lambda-004-to-iam-002-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-004-to-iam-002-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-lambda-004-to-iam-002-starting-user` | Scenario-specific starting user with lambda:UpdateFunctionCode and lambda:InvokeFunction permissions |
| `arn:aws:lambda:{region}:{account_id}:function:pl-prod-lambda-004-to-iam-002-target-function` | Lambda function that will be modified during the attack |
| `arn:aws:iam::{account_id}:role/pl-prod-lambda-004-to-iam-002-lambda-role` | Lambda execution role with iam:CreateAccessKey permission on the admin user |
| `arn:aws:iam::{account_id}:user/pl-prod-lambda-004-to-iam-002-admin-user` | Target admin user with AdministratorAccess managed policy attached |
| `arn:aws:iam::{account_id}:policy/pl-prod-lambda-004-to-iam-002-starting-policy` | Policy granting starting user Lambda permissions |
| `arn:aws:iam::{account_id}:policy/pl-prod-lambda-004-to-iam-002-lambda-policy` | Policy granting Lambda role iam:CreateAccessKey on admin user |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/lambda-004 + iam-002-to-admin` | CTF flag stored in SSM Parameter Store; readable with admin credentials |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Update the Lambda function with credential-exfiltration code
4. Invoke the function and capture the Lambda role credentials
5. Use those credentials to create access keys for the admin user
6. Verify successful privilege escalation to administrator
7. Capture the CTF flag from SSM Parameter Store using the admin credentials


#### Resources Created by Attack Script

- Access keys for `pl-prod-lambda-004-to-iam-002-admin-user` (permanent IAM access key pair)
- Modified Lambda function code (credential exfiltration payload replaces the original handler)
- Temporary zip file at `/tmp/lambda_payload.zip`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo lambda-004-to-iam-002-to-admin
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-004-to-iam-002-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup lambda-004-to-iam-002-to-admin
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-004-to-iam-002-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable lambda-004-to-iam-002-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-004-to-iam-002-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

**High Severity Findings:**
- IAM user has `lambda:UpdateFunctionCode` permission - allows code injection
- IAM user has `lambda:InvokeFunction` permission combined with code update - enables credential exfiltration
- Lambda execution role has `iam:CreateAccessKey` permission - dangerous for automation roles
- Lambda role can create credentials for user with AdministratorAccess
- Multi-hop privilege escalation path from starting user to administrator

**Medium Severity Findings:**
- Lambda function exists that could be modified by non-admin users
- IAM user with administrative access exists (potential target)
- Lambda execution role has IAM permissions beyond its operational needs

**Attack Path Detection:**
- Path: `starting-user` -> `lambda:UpdateFunctionCode` -> `lambda:InvokeFunction` -> `lambda-role` -> `iam:CreateAccessKey` -> `admin-user`
- Risk: Complete environment compromise through chained privilege escalation

#### Prevention Recommendations

- **Restrict Lambda code update permissions**: Implement resource-based conditions to limit which functions can be updated: `"Condition": {"StringNotLike": {"lambda:FunctionArn": "arn:aws:lambda:*:*:function:production-*"}}`

- **Separate Lambda invoke and update permissions**: Avoid granting both `lambda:UpdateFunctionCode` and `lambda:InvokeFunction` to the same principal - this combination enables credential exfiltration

- **Apply least privilege to Lambda execution roles**: Lambda roles should only have permissions required for their specific function, never `iam:CreateAccessKey` or other IAM credential-management permissions

- **Use permission boundaries on Lambda roles**: Apply permission boundaries that explicitly deny sensitive IAM actions like `iam:CreateAccessKey`, `iam:CreateLoginProfile`, and `iam:UpdateAssumeRolePolicy`

- **Implement SCPs for Lambda roles**: Organization-level SCPs can prevent Lambda execution roles from performing IAM credential operations regardless of their attached policies

- **Monitor for Lambda code changes**: Set up CloudWatch Events/EventBridge rules to alert on `UpdateFunctionCode` API calls, especially for sensitive functions

- **Enable Lambda function code signing**: Use AWS Signer to require that Lambda code be signed by trusted publishers, preventing unauthorized code modifications

- **Use IAM roles instead of IAM users for admin access**: Administrative principals should use roles with temporary credentials, not users with permanent access keys that can be created by attackers

- **Implement anomaly detection**: Use GuardDuty and CloudTrail Insights to detect unusual patterns like Lambda code updates followed by immediate invocations

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `Lambda: UpdateFunctionCode20150331v2` -- Lambda function code was modified; high severity when followed by an invocation
- `Lambda: Invoke` -- Lambda function was invoked; correlate with preceding code changes to detect credential exfiltration
- `IAM: CreateAccessKey` -- New access keys created for an IAM user; critical when the target user has elevated permissions

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [pathfinding.cloud - lambda-004](https://pathfinding.cloud/paths/lambda-004) -- Lambda UpdateFunctionCode + InvokeFunction privilege escalation
- [pathfinding.cloud - iam-002](https://pathfinding.cloud/paths/iam-002) -- IAM CreateAccessKey privilege escalation
- [MITRE ATT&CK T1098.001](https://attack.mitre.org/techniques/T1098/001/) -- Account Manipulation: Additional Cloud Credentials
- [MITRE ATT&CK T1059](https://attack.mitre.org/techniques/T1059/) -- Command and Scripting Interpreter
- [AWS Lambda Execution Role](https://docs.aws.amazon.com/lambda/latest/dg/lambda-intro-execution-role.html) -- AWS documentation on Lambda execution roles
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html) -- Least privilege and access management
