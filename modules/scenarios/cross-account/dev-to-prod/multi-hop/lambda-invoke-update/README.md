# Dev to Prod via Lambda Code Injection to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** privilege-chaining
* **Path Type:** cross-account
* **Target:** to-admin
* **Environments:** dev, prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Cross-account Lambda function code injection to extract admin credentials
* **Terraform Variable:** `enable_cross_account_dev_to_prod_multi_hop_lambda_invoke_update`
* **Schema Version:** 4.6.0
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0006 - Credential Access, TA0008 - Lateral Movement
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1648 - Serverless Execution, T1552.005 - Cloud Instance Metadata API

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-pathfinding-starting-user-dev` IAM user in the dev account to the `pl-prod-lambda-execution-role` administrative role in the prod account by assuming the `pl-dev-lambda-invoke-role`, injecting malicious code into the `pl-prod-hello-world` Lambda function, and extracting the execution role's temporary credentials from the runtime environment.

- **Start:** `arn:aws:iam::{dev_account_id}:user/pl-pathfinding-starting-user-dev`
- **Destination resource:** `arn:aws:iam::{prod_account_id}:role/pl-prod-lambda-execution-role`

### Starting Permissions

**Required** (`pl-pathfinding-starting-user-dev`):
- `lambda:UpdateFunctionCode` on `arn:aws:lambda:*:{prod_account_id}:function/*` -- allows replacing the prod Lambda function's code with a malicious payload
- `lambda:InvokeFunction` on `arn:aws:lambda:*:{prod_account_id}:function/*` -- allows executing the now-malicious function to retrieve the execution role credentials

**Helpful** (`pl-pathfinding-starting-user-dev`):
- `lambda:ListFunctions` -- discover Lambda functions in the prod account
- `lambda:GetFunction` -- view Lambda function configuration and identify its execution role

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable lambda-invoke-update-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-invoke-update-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
|-----|---------|
| `arn:aws:iam::{DEV_ACCOUNT}:role/pl-dev-lambda-invoke-role` | Dev role with cross-account Lambda invoke and update permissions |
| `arn:aws:lambda:{REGION}:{PROD_ACCOUNT}:function:pl-prod-hello-world` | Prod Lambda function vulnerable to code injection |
| `arn:aws:iam::{PROD_ACCOUNT}:role/pl-prod-lambda-execution-role` | Prod Lambda execution role with AdministratorAccess |
| `arn:aws:ssm:{REGION}:{PROD_ACCOUNT}:parameter/pathfinding-labs/flags/lambda-invoke-update-to-admin` | CTF flag stored in SSM Parameter Store (requires admin access to read) |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:

1. Assume the dev Lambda invoke role (`pl-dev-lambda-invoke-role`) in the dev account
2. Discover the prod Lambda function (`pl-prod-hello-world`)
3. Create malicious Python code for credential extraction
4. Update the prod Lambda function with the malicious code using `lambda:UpdateFunctionCode`
5. Invoke the malicious function using `lambda:InvokeFunction`
6. Export the extracted prod Lambda execution role credentials (AdministratorAccess)
7. Capture the CTF flag from SSM Parameter Store using `ssm:GetParameter`

#### Resources Created by Attack Script

- Temporary malicious Lambda deployment package (zip file on disk, removed after upload)
- Modified prod Lambda function code (restored by cleanup script)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo lambda-invoke-update
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-invoke-update-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup lambda-invoke-update
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-invoke-update-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable lambda-invoke-update-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-invoke-update-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- Dev account IAM role (`pl-dev-lambda-invoke-role`) has `lambda:UpdateFunctionCode` permission on prod account Lambda functions — this is a cross-account code injection vector
- Dev account IAM role has `lambda:InvokeFunction` permission on prod account Lambda functions with no condition restricting invocation context
- Prod Lambda function (`pl-prod-hello-world`) has a resource policy granting the entire dev account (`arn:aws:iam::DEV_ACCOUNT:root`) the ability to invoke and update function code
- Prod Lambda execution role (`pl-prod-lambda-execution-role`) has `AdministratorAccess` attached — high-privilege execution role reachable via code injection
- Cross-account Lambda resource policy allows broad principal (`*` or `:root`) rather than a specific role ARN

#### Prevention Recommendations

- **Principle of Least Privilege**: Avoid granting `lambda:UpdateFunctionCode` to cross-account principals; restrict Lambda update permissions to CI/CD pipeline roles with narrow scope conditions
- **Cross-Account Restrictions**: Scope Lambda resource policies to a specific trusted role ARN (e.g., `arn:aws:iam::DEV_ACCOUNT:role/ci-deploy-role`) rather than the entire dev account root
- **Resource Policy Auditing**: Regularly audit Lambda resource policies using `aws lambda get-policy` and alert on policies granting broad cross-account access
- **Execution Role Restrictions**: Limit Lambda execution role permissions to only what the function needs; never attach `AdministratorAccess` to a Lambda execution role
- **Code Review and Signing**: Implement Lambda code signing with AWS Signer to prevent unauthorized code from being deployed
- **Monitoring**: Alert on `Lambda: UpdateFunctionCode20150331v2` events, especially when the caller is from a different account than the function

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `STS: AssumeRole` — Dev user assumes the `pl-dev-lambda-invoke-role`; monitor cross-account role assumptions from dev to roles with Lambda permissions
- `Lambda: UpdateFunctionCode20150331v2` — Lambda function code modified cross-account; high severity when caller account differs from function account
- `Lambda: Invoke` — Lambda function invoked shortly after a code update; correlate with `UpdateFunctionCode` events from the same session
- `STS: GetCallerIdentity` — Often called to confirm identity after credential extraction; monitor for calls using Lambda execution role temporary credentials from unexpected source IPs

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
