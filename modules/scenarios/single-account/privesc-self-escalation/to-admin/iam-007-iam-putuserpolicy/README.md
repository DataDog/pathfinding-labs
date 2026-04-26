# IAM Inline User Policy Modification to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** self-escalation
* **Path Type:** self-escalation
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Self-modification via iam:PutUserPolicy to attach inline admin policy
* **Terraform Variable:** `enable_single_account_privesc_self_escalation_to_admin_iam_007_iam_putuserpolicy`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** iam-007
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098 - Account Manipulation, T1098.001 - Additional Cloud Credentials

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-007-to-admin-starting-user` IAM user to effective administrator access by using `iam:PutUserPolicy` to attach an inline policy granting full administrative permissions to your own user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-007-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:user/pl-prod-iam-007-to-admin-starting-user` (with effective AdministratorAccess via inline policy)

### Starting Permissions

**Required** (`pl-prod-iam-007-to-admin-starting-user`):
- `iam:PutUserPolicy` on `*` -- allows attaching an inline policy to any IAM user, including yourself

**Helpful** (`pl-prod-iam-007-to-admin-starting-user`):
- `iam:GetUser` -- view user details and verify policy attachment
- `iam:ListUserPolicies` -- list existing inline policies on users

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable iam-007-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-007-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-007-to-admin-starting-user` | User with PutUserPolicy permission on itself |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/iam-007-to-admin` | SSM parameter holding the CTF flag |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Verify successful privilege escalation
4. Capture the CTF flag from SSM Parameter Store using the escalated credentials


#### Resources Created by Attack Script

- Inline IAM policy attached to `pl-prod-iam-007-to-admin-starting-user` granting AdministratorAccess

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-007-iam-putuserpolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-007-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-007-iam-putuserpolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-007-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable iam-007-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-007-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user has `iam:PutUserPolicy` permission scoped to `*`, allowing self-modification
- Privilege escalation path exists: user can attach an inline admin policy to themselves
- No resource constraint prevents the user from modifying their own policies

#### Prevention Recommendations

- Never grant `iam:PutUserPolicy` permissions without strict resource constraints
- Use SCPs to prevent inline policy attachments on privileged users
- Implement least privilege - users should not be able to modify their own permissions
- Monitor CloudTrail for `PutUserPolicy` API calls, especially self-modifications
- Use IAM Access Analyzer to identify privilege escalation paths
- Prefer managed policies over inline policies for better visibility and control
- Enable MFA requirements for sensitive IAM operations

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: PutUserPolicy` -- Inline policy added to an IAM user; critical when the target is the calling principal (self-escalation)

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._