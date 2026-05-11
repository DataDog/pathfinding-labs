# IAM Access Key Creation to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** credential-access
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Creating access keys for privileged users to gain administrative access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_iam_002_iam_createaccesskey`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** iam-002
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-002-to-admin-starting-user` IAM user to the `pl-prod-iam-002-to-admin-target-user` administrative user by creating new programmatic credentials for the admin user using `iam:CreateAccessKey`.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-002-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:user/pl-prod-iam-002-to-admin-target-user`

### Starting Permissions

**Required** (`pl-prod-iam-002-to-admin-starting-user`):
- `iam:CreateAccessKey` on `arn:aws:iam::*:user/pl-prod-iam-002-to-admin-target-user` -- create new programmatic credentials for the target admin user

**Helpful** (`pl-prod-iam-002-to-admin-starting-user`):
- `iam:ListUsers` -- discover privileged users to target
- `iam:GetUser` -- view user details and attached policies
- `iam:ListAttachedUserPolicies` -- identify users with admin permissions

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
plabs enable iam-002-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-002-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-002-to-admin-starting-user` | Scenario-specific starting user with access keys and iam:CreateAccessKey permission |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-002-to-admin-target-user` | Target admin user with AdministratorAccess managed policy attached |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/iam-002-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

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

- Access keys for `pl-prod-iam-002-to-admin-target-user` (permanent IAM access key pair)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-002-iam-createaccesskey
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-002-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-002-iam-createaccesskey
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-002-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable iam-002-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-002-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user (`pl-prod-iam-002-to-admin-starting-user`) has `iam:CreateAccessKey` permission scoped to a privileged IAM user
- IAM user (`pl-prod-iam-002-to-admin-target-user`) with `AdministratorAccess` is targetable for credential creation by a less-privileged principal
- Privilege escalation path exists: non-admin user can generate persistent credentials for an admin user without modifying any policies

#### Prevention Recommendations

- Implement least privilege principles - avoid granting `iam:CreateAccessKey` permissions unless absolutely necessary
- Use resource-based conditions to restrict which users can have access keys created: `"Condition": {"StringNotEquals": {"aws:username": ["admin-user"]}}`
- Implement Service Control Policies (SCPs) at the organization level to prevent access key creation on privileged accounts
- Monitor CloudTrail for `CreateAccessKey` API calls, especially on users with elevated permissions
- Enable MFA requirements for sensitive IAM operations using condition keys like `aws:MultiFactorAuthPresent`
- Use IAM Access Analyzer to identify and remediate privilege escalation paths involving `iam:CreateAccessKey`
- Consider using IAM roles instead of IAM users for administrative access, as roles cannot have access keys created by other principals
- Implement automated alerting on access key creation events for admin accounts using CloudWatch Events or EventBridge

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `iam:CreateAccessKey` -- New access keys were created for an IAM user; critical when the target user has elevated permissions

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
