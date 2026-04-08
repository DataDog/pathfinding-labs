# IAM Console Password Update to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** credential-access
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Password reset for admin user to gain console access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_iam_006_iam_updateloginprofile`
* **Schema Version:** 4.1.1
* **Pathfinding.cloud ID:** iam-006
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-006-to-admin-starting-user` IAM user to the `pl-prod-iam-006-to-admin-target-user` administrative user by resetting the target's AWS Console password using the `iam:UpdateLoginProfile` permission.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-006-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:user/pl-prod-iam-006-to-admin-target-user`

### Starting Permissions

**Required** (`pl-prod-iam-006-to-admin-starting-user`):
- `iam:UpdateLoginProfile` on `arn:aws:iam::*:user/pl-prod-iam-006-to-admin-target-user` -- reset the console password for the admin target user

**Helpful** (`pl-prod-iam-006-to-admin-starting-user`):
- `iam:ListUsers` -- discover users with login profiles
- `iam:GetUser` -- view user details
- `iam:GetLoginProfile` -- verify user has a login profile configured

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable iam-006-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-006-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-006-to-admin-starting-user` | Scenario-specific starting user with access keys and UpdateLoginProfile permission |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-006-to-admin-target-user` | Target admin user with AdministratorAccess and existing login profile |
| `arn:aws:iam::{account_id}:policy/pl-prod-iam-006-to-admin-starting-user-policy` | Inline policy allowing `iam:UpdateLoginProfile` on the target user |

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

- Updated console password (login profile) on `pl-prod-iam-006-to-admin-target-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-006-iam-updateloginprofile
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-006-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-006-iam-updateloginprofile
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-006-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable iam-006-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-006-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user `pl-prod-iam-006-to-admin-starting-user` has `iam:UpdateLoginProfile` permission scoped to an administrator user, creating a privilege escalation path
- Privilege escalation path detected: non-privileged user can reset console password of admin user
- IAM policy allows password reset on privileged users without resource-level restrictions

#### Prevention Recommendations

- Avoid granting `iam:UpdateLoginProfile` permissions on privileged users - use resource-based conditions to restrict which users can have their passwords updated
- Implement Service Control Policies (SCPs) to prevent password updates on administrator accounts
- Require MFA for the `iam:UpdateLoginProfile` action using condition keys like `aws:MultiFactorAuthPresent`
- Monitor CloudTrail for `UpdateLoginProfile` API calls, especially on privileged accounts, and alert on unexpected password changes
- Use IAM Access Analyzer to identify privilege escalation paths involving login profile manipulation
- Implement separate break-glass accounts for emergency access rather than allowing password resets on production admin accounts
- Enable AWS CloudTrail Insights to detect unusual patterns of IAM user credential modifications
- Consider using AWS IAM Identity Center (formerly SSO) for console access instead of long-lived IAM user passwords

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: UpdateLoginProfile` -- Console password reset on an IAM user; critical when the target account has elevated permissions, as it enables console login as that user

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
