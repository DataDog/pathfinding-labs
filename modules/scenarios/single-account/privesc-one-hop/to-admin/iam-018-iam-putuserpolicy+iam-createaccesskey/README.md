# IAM Inline User Policy + Access Key Creation to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** principal-access
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** User-to-user lateral movement via policy modification and credential creation
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_iam_018_iam_putuserpolicy_iam_createaccesskey`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** iam-018
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-018-to-admin-starting-user` IAM user to the `pl-prod-iam-018-to-admin-target-user` IAM user (with full administrative access) by adding an inline admin policy to the target user via `iam:PutUserPolicy` and then creating access keys for that user via `iam:CreateAccessKey`.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-018-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:user/pl-prod-iam-018-to-admin-target-user`

### Starting Permissions

**Required** (`pl-prod-iam-018-to-admin-starting-user`):
- `iam:PutUserPolicy` on `arn:aws:iam::*:user/pl-prod-iam-018-to-admin-target-user` -- modify the target user's inline policies to grant admin access
- `iam:CreateAccessKey` on `arn:aws:iam::*:user/pl-prod-iam-018-to-admin-target-user` -- create credentials for the target user after elevating their permissions

**Helpful** (`pl-prod-iam-018-to-admin-starting-user`):
- `iam:ListUsers` -- discover target users to escalate through
- `iam:GetUser` -- get target user details and current permissions
- `iam:ListUserPolicies` -- list inline policies on target user
- `iam:GetUserPolicy` -- view target user's inline policies
- `iam:ListAccessKeys` -- list existing access keys for target user

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable iam-018-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-018-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-018-to-admin-starting-user` | Scenario-specific starting user with access keys and inline policy for lateral movement permissions |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-018-to-admin-target-user` | Target user that will be granted admin permissions and have credentials created (initially has minimal permissions) |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/iam-018-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Verify successful privilege escalation
4. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions


#### Resources Created by Attack Script

- Inline policy added to `pl-prod-iam-018-to-admin-target-user` granting `AdministratorAccess`
- New access keys for `pl-prod-iam-018-to-admin-target-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-018-iam-putuserpolicy+iam-createaccesskey
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-018-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-018-iam-putuserpolicy+iam-createaccesskey
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-018-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable iam-018-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-018-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user (`pl-prod-iam-018-to-admin-starting-user`) has `iam:PutUserPolicy` permission targeting another IAM user (`pl-prod-iam-018-to-admin-target-user`)
- IAM user has `iam:CreateAccessKey` permission targeting another IAM user — enabling credential theft
- Combined `iam:PutUserPolicy` + `iam:CreateAccessKey` on the same target user constitutes a complete privilege escalation path
- Cross-user IAM management permissions present without resource-level restrictions

#### Prevention Recommendations

- Never grant `iam:PutUserPolicy` permissions that allow modifying other users' policies
- Restrict `iam:CreateAccessKey` to prevent users from creating credentials for other users; use `Condition: {"StringLike": {"iam:ResourceTag/aws:username": "${aws:username}"}}` to enforce self-only operations
- Use SCPs to prevent cross-user IAM policy modifications: `Deny iam:PutUserPolicy where aws:userId != ${aws:userid}`
- Use IAM Access Analyzer to identify users with permissions on other IAM principals
- Use resource-based conditions to restrict which users can be modified: `"Resource": "arn:aws:iam::*:user/${aws:username}"`
- Regularly audit IAM permissions to identify and remediate cross-user management capabilities

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `iam:PutUserPolicy` -- Inline policy added to an IAM user; critical when targeting a user other than the caller and when the policy grants elevated permissions
- `iam:CreateAccessKey` -- New access keys created for an IAM user; critical when the caller and the target user differ, indicating cross-user credential creation

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
