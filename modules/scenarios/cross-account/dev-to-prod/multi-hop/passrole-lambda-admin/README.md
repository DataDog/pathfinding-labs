# Dev to Prod via Lambda PassRole to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** privilege-chaining
* **Path Type:** cross-account
* **Target:** to-admin
* **Environments:** dev, prod
* **Cost Estimate:** $0/mo
* **Technique:** Multi-hop cross-account privilege escalation using PassRole to create Lambda with admin role
* **Terraform Variable:** `enable_cross_account_dev_to_prod_multi_hop_passrole_lambda_admin`
* **Schema Version:** 4.0.0
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0008 - Lateral Movement
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1648 - Serverless Execution, T1098 - Account Manipulation

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-pathfinding-starting-user-dev` IAM user in the dev account to the `pl-Lambda-admin` administrative role in the prod account by chaining three role assumptions — including a cross-account hop — and then abusing `iam:PassRole` to create a Lambda function that executes with full admin privileges.

- **Start:** `arn:aws:iam::{dev_account_id}:user/pl-pathfinding-starting-user-dev`
- **Destination resource:** `arn:aws:iam::{prod_account_id}:role/pl-Lambda-admin`

### Starting Permissions

**Required** (`pl-pathfinding-starting-user-dev`):
- `iam:PassRole` on `arn:aws:iam::{prod_account_id}:role/pl-Lambda-admin` -- allows passing the admin role to the Lambda service when creating a function
- `lambda:CreateFunction` on `*` -- allows creating the Lambda function with the passed admin role
- `lambda:InvokeFunction` on `*` -- allows invoking the Lambda function to execute as the admin role

**Helpful** (`pl-pathfinding-starting-user-dev`):
- `iam:ListRoles` -- discover roles that can be passed to Lambda
- `lambda:ListFunctions` -- view existing Lambda functions
- `iam:GetRole` -- view role permissions and trust policies

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_cross_account_dev_to_prod_multi_hop_passrole_lambda_admin
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
|-----|---------|
| `arn:aws:iam::{dev_account_id}:role/pl-lambda-prod-updater` | Dev role assumed by starting user; bridges dev to prod |
| `arn:aws:iam::{prod_account_id}:role/pl-lambda-updater` | Prod role trusted by dev role; holds PassRole + Lambda permissions |
| `arn:aws:iam::{prod_account_id}:role/pl-Lambda-admin` | Admin role passable to Lambda; grants full administrative access |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:

1. **Verification**: Check current identity and permissions of the starting dev user
2. **First Role Assumption**: Assume the dev lambda-prod-updater role
3. **Cross-Account Role Assumption**: Assume the prod lambda-updater role cross-account
4. **PassRole Abuse**: Create a Lambda function using the admin role
5. **Admin Verification**: Invoke the Lambda function to confirm admin access
6. **Cleanup**: Remove the created Lambda function

#### Resources Created by Attack Script

- A temporary Lambda function in the prod account using the `pl-Lambda-admin` role

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo passrole-lambda-admin
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup passrole-lambda-admin
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_cross_account_dev_to_prod_multi_hop_passrole_lambda_admin
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

- IAM role `pl-lambda-updater` in the prod account holds `iam:PassRole` on a role with `AdministratorAccess`, creating a privilege escalation path from the dev account
- Cross-account trust relationship allows a dev account role (`pl-lambda-prod-updater`) to assume a prod account role (`pl-lambda-updater`) that holds sensitive PassRole permissions
- The `pl-Lambda-admin` role has a trust policy permitting the Lambda service to assume it with full administrative privileges, and that role is passable by a non-admin principal
- Multi-hop role assumption chain (dev user → dev role → prod role → Lambda admin) is detectable as a privilege escalation path via graph-based IAM analysis

#### Prevention Recommendations

1. **Principle of Least Privilege**: Avoid granting `iam:PassRole` permissions unless absolutely necessary; scope PassRole with `iam:PassedToService` and `iam:ResourceTag` conditions
2. **Cross-Account Restrictions**: Limit cross-account role assumptions to specific use cases; require `aws:PrincipalOrgID` or explicit account conditions in trust policies
3. **Multi-Hop Prevention**: Avoid creating long chains of role assumptions; use direct access where possible and enforce SCP controls on cross-account assumptions
4. **Role Trust Policies**: Use more restrictive trust policies for service roles; require `iam:AssociatedResourceArn` conditions where supported
5. **PassRole Monitoring**: Monitor and alert on `iam:PassRole` usage, especially when the passed role has elevated permissions
6. **Regular Audits**: Regularly audit cross-account permissions and PassRole usage using IAM Access Analyzer cross-account findings
7. **Service Role Restrictions**: Limit which roles can be passed to which services using `iam:PassedToService` conditions in PassRole policies

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `STS: AssumeRole` — Role assumption from the dev starting user into `pl-lambda-prod-updater`; alert when a cross-account assumption chain originates from a dev account principal
- `STS: AssumeRole` — Cross-account role assumption from `pl-lambda-prod-updater` (dev) into `pl-lambda-updater` (prod); high severity when the source account is a non-prod account
- `IAM: PassRole` — `pl-Lambda-admin` (admin role) passed to the Lambda service by `pl-lambda-updater`; critical when the passed role has administrative permissions
- `Lambda: CreateFunction20150331` — New Lambda function created with an admin execution role; high severity when the role ARN resolves to a privileged role
- `Lambda: Invoke` — Invocation of the newly created Lambda function; correlate with the preceding `CreateFunction` to detect execution-after-creation patterns

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
