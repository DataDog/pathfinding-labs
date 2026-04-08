# App Runner Service Update to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $10/mo
* **Technique:** Update existing App Runner service to execute privilege escalation commands
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_apprunner_002_apprunner_updateservice`
* **Schema Version:** 4.1.1
* **Pathfinding.cloud ID:** apprunner-002
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1651 - Cloud Administration Command

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-apprunner-002-to-admin-starting-user` IAM user to the `pl-prod-apprunner-002-to-admin-target-role` administrative role by updating an existing App Runner service to swap its container image for the AWS CLI image and injecting a `StartCommand` that attaches `AdministratorAccess` to the starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-apprunner-002-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-apprunner-002-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-apprunner-002-to-admin-starting-user`):
- `apprunner:UpdateService` on `arn:aws:apprunner:{region}:{account_id}:service/pl-prod-apprunner-002-to-admin-target-service/*` -- modify the existing service configuration to inject a malicious StartCommand

**Helpful** (`pl-prod-apprunner-002-to-admin-starting-user`):
- `apprunner:DescribeService` -- view service configuration and verify the privileged role attached
- `apprunner:ListServices` -- discover existing App Runner services to exploit
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
plabs enable apprunner-002-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `apprunner-002-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-apprunner-002-to-admin-starting-user` | Scenario-specific starting user with access keys and inline policy for App Runner |
| `arn:aws:apprunner:{region}:{account_id}:service/pl-prod-apprunner-002-to-admin-target-service` | Existing App Runner service running a benign nginx container |
| `arn:aws:iam::{account_id}:role/pl-prod-apprunner-002-to-admin-target-role` | Privileged role attached to the App Runner service with administrator access (`Action: "*"`) |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Backup the original service configuration (image and StartCommand)
4. Update the App Runner service with malicious configuration
5. Wait for the service to execute the privilege escalation command
6. Verify successful privilege escalation to administrator
7. Output standardized test results for automation

#### Resources Created by Attack Script

- `AdministratorAccess` managed policy attached to `pl-prod-apprunner-002-to-admin-starting-user`
- Modified App Runner service configuration (image and StartCommand overridden)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo apprunner-002-apprunner-updateservice
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `apprunner-002-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup apprunner-002-apprunner-updateservice
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `apprunner-002-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable apprunner-002-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `apprunner-002-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- **Overly Permissive Update Permissions**: User/role with `apprunner:UpdateService` permission on services with privileged roles
- **Service with Privileged Role**: App Runner service running with a role that has IAM modification permissions (`iam:AttachUserPolicy`, `iam:PutUserPolicy`, `iam:AttachRolePolicy`)
- **Privilege Escalation Path**: Detection of the one-hop path from starting user through existing App Runner infrastructure to admin access
- **Lack of Resource-Based Restrictions**: `apprunner:UpdateService` permission without conditions limiting which services can be updated
- **Service Role Risk**: IAM roles with both App Runner trust relationships and sensitive permissions like IAM policy manipulation
- **Command Override Capability**: App Runner services that can be updated with `StartCommand` overrides by non-administrative users

#### Prevention Recommendations

- **Restrict UpdateService Permissions**: Limit `apprunner:UpdateService` to specific services using resource-based conditions. Never grant blanket update permissions across all services:
  ```json
  {
    "Effect": "Allow",
    "Action": "apprunner:UpdateService",
    "Resource": "arn:aws:apprunner:*:*:service/approved-service-name/*",
    "Condition": {
      "StringEquals": {
        "aws:ResourceTag/UpdateAllowed": "true"
      }
    }
  }
  ```

- **Minimize App Runner Service Role Permissions**: Instance roles for App Runner services should follow the principle of least privilege. Avoid granting IAM modification permissions unless absolutely necessary. Use IAM policy conditions to further restrict what a service role can do:
  ```json
  {
    "Effect": "Deny",
    "Action": [
      "iam:AttachUserPolicy",
      "iam:AttachRolePolicy",
      "iam:PutUserPolicy",
      "iam:PutRolePolicy"
    ],
    "Resource": "*"
  }
  ```

- **Implement Service Control Policies (SCPs)**: Use SCPs to prevent updating App Runner services that have privileged roles or to block service updates entirely in sensitive accounts:
  ```json
  {
    "Effect": "Deny",
    "Action": "apprunner:UpdateService",
    "Resource": "*",
    "Condition": {
      "StringLike": {
        "aws:ResourceTag/Sensitivity": "high"
      }
    }
  }
  ```

- **Use IAM Access Analyzer**: Leverage IAM Access Analyzer to identify privilege escalation paths involving App Runner service update permissions and roles with IAM modification capabilities.

- **Implement Resource Tags and ABAC**: Tag App Runner services based on their sensitivity level and the permissions of their instance roles. Use Attribute-Based Access Control (ABAC) to restrict who can update high-privilege services:
  ```json
  {
    "Effect": "Deny",
    "Action": "apprunner:UpdateService",
    "Resource": "*",
    "Condition": {
      "StringEquals": {
        "aws:ResourceTag/InstanceRolePrivilege": "admin"
      },
      "StringNotEquals": {
        "aws:PrincipalTag/AppRunnerAdmin": "true"
      }
    }
  }
  ```

- **Regular Permission Audits**: Periodically review which principals have `apprunner:UpdateService` permissions and which services have privileged instance roles. Ensure this combination is necessary for legitimate business functions.

- **Separate Environments and Accounts**: Use different AWS accounts for development and production. Limit App Runner deployment and update capabilities to non-production environments where possible. Use cross-account roles with strict conditions for production service management.

- **Implement Change Control**: Require approval workflows for App Runner service updates in production environments. Use AWS Systems Manager Change Manager or third-party tools to gate service configuration changes.

- **Enable AWS Config Rules**: Configure AWS Config to monitor App Runner service configurations and alert on changes to image sources or command overrides:
  - Rule: Detect when service instance roles have IAM permissions
  - Rule: Alert on image changes from approved registries
  - Rule: Monitor StartCommand modifications

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `AppRunner: UpdateService` -- App Runner service configuration modified; critical when `ImageConfiguration.StartCommand` is changed on a service with a privileged instance role
- `IAM: AttachUserPolicy` -- Managed policy attached to an IAM user; high severity when the policy is `AdministratorAccess` and the caller is an App Runner service role
- `AppRunner: DescribeService` -- Service details retrieved; may indicate reconnaissance to identify services with privileged roles

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
