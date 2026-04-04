# App Runner Service Creation to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Pass privileged role to App Runner service with command override
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_apprunner_001_iam_passrole_apprunner_createservice`
* **Schema Version:** 4.0.0
* **Pathfinding.cloud ID:** apprunner-001
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1651 - Cloud Administration Command

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-apprunner-001-to-admin-starting-user` IAM user to the `pl-prod-apprunner-001-to-admin-target-role` administrative role by creating an AWS App Runner service that passes the privileged role as its instance role and uses a `StartCommand` override to attach `AdministratorAccess` to your starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-apprunner-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-apprunner-001-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-apprunner-001-to-admin-starting-user`):
- `apprunner:CreateService` on `*` -- create an App Runner service to serve as the execution proxy
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-apprunner-001-to-admin-target-role` -- pass the privileged role to the App Runner service as its instance role
- `iam:CreateServiceLinkedRole` on `arn:aws:iam::*:role/aws-service-role/apprunner.amazonaws.com/AWSServiceRoleForAppRunner` -- required only for the first App Runner service in the account

**Helpful** (`pl-prod-apprunner-001-to-admin-starting-user`):
- `apprunner:ListServices` -- list App Runner services to verify service creation
- `apprunner:DescribeService` -- check service status and configuration
- `iam:ListUsers` -- verify admin access after escalation

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_admin_apprunner_001_iam_passrole_apprunner_createservice
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
| `arn:aws:iam::{account_id}:user/pl-prod-apprunner-001-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-apprunner-001-to-admin-target-role` | Privileged role with `iam:AttachUserPolicy` permission, trusted by App Runner service |
| `arn:aws:iam::{account_id}:policy/pl-prod-apprunner-001-to-admin-passrole-policy` | Allows `iam:PassRole` on target role and `apprunner:CreateService` |
| `arn:aws:iam::{account_id}:policy/pl-prod-apprunner-001-to-admin-admin-attach-policy` | Grants target role permission to attach policies to the starting user |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Create an App Runner service with the StartCommand override
4. Wait for the service to execute the privilege escalation command
5. Verify successful privilege escalation to administrator
6. Output standardized test results for automation

#### Resources Created by Attack Script

- App Runner service using the public AWS CLI container image (`public.ecr.aws/aws-cli/aws-cli:latest`)
- `AdministratorAccess` policy attached to the starting user

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo apprunner-001-iam-passrole+apprunner-createservice
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup apprunner-001-iam-passrole+apprunner-createservice
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_apprunner_001_iam_passrole_apprunner_createservice
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

- **High-Risk Permission Combination**: User/role with both `apprunner:CreateService` and `iam:PassRole` permissions
- **Overly Permissive Instance Role**: App Runner service role with IAM modification permissions (`iam:AttachUserPolicy`, `iam:PutUserPolicy`, `iam:AttachRolePolicy`)
- **Service Principal Trust**: IAM roles trusting `tasks.apprunner.amazonaws.com` with sensitive permissions
- **Privilege Escalation Path**: Detection of the one-hop path from starting user through App Runner to admin access
- **Command Override Risk**: App Runner services with `StartCommand` overrides that could execute arbitrary code

#### Prevention Recommendations

- **Restrict PassRole Permissions**: Limit `iam:PassRole` to specific, well-defined roles with minimal permissions. Use resource-based conditions to prevent passing privileged roles to compute services.
  ```json
  {
    "Effect": "Deny",
    "Action": "iam:PassRole",
    "Resource": "*",
    "Condition": {
      "StringEquals": {
        "iam:PassedToService": "apprunner.amazonaws.com"
      }
    }
  }
  ```

- **Minimize App Runner Service Role Permissions**: Instance roles for App Runner services should follow the principle of least privilege. Avoid granting IAM modification permissions unless absolutely necessary.

- **Implement Service Control Policies (SCPs)**: Use SCPs to prevent App Runner service creation in sensitive accounts or prevent passing privileged roles to App Runner:
  ```json
  {
    "Effect": "Deny",
    "Action": "apprunner:CreateService",
    "Resource": "*",
    "Condition": {
      "StringLike": {
        "apprunner:InstanceRole": "*admin*"
      }
    }
  }
  ```

- **Monitor CloudTrail for App Runner Activity**: Set up alerts for `AppRunner: CreateService` and `AppRunner: UpdateService` API calls, especially those that specify instance roles with sensitive permissions. Pay special attention to services using `StartCommand` overrides.

- **Use IAM Access Analyzer**: Leverage IAM Access Analyzer to identify privilege escalation paths involving `iam:PassRole` and compute service permissions.

- **Implement Resource Tags and Conditions**: Require specific resource tags on roles that can be passed to App Runner services and enforce tag-based conditions in IAM policies.

- **Regular Permission Audits**: Periodically review which principals have `apprunner:CreateService` and `iam:PassRole` permissions, and ensure they are necessary for legitimate business functions.

- **Separate Environments**: Use different AWS accounts for development and production, limiting App Runner deployment capabilities to non-production environments where possible.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: PassRole` -- role passed to App Runner service; high risk when the passed role has IAM modification permissions
- `AppRunner: CreateService` -- new App Runner service created; critical when combined with a privileged instance role and a `StartCommand` override
- `IAM: AttachUserPolicy` -- policy attached to a user; critical when the policy is `AdministratorAccess` and follows App Runner service creation

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
