# Privilege Escalation via iam:DeleteAccessKey + iam:CreateAccessKey

* **Category:** Privilege Escalation
* **Sub-Category:** credential-access
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Bypassing AWS's 2-access-key limit by deleting an existing key before creating a new one for an admin user
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_iam_003_iam_deleteaccesskey_createaccesskey`
* **Schema Version:** 4.0.0
* **Pathfinding.cloud ID:** iam-003
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-003-to-admin-starting-user` IAM user to the `pl-prod-iam-003-to-admin-target-user` administrative user by deleting one of the target user's two existing access keys to free up a slot, then creating a new access key under your control to gain administrative credentials.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-003-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:user/pl-prod-iam-003-to-admin-target-user`

### Starting Permissions

**Required** (`pl-prod-iam-003-to-admin-starting-user`):
- `iam:DeleteAccessKey` on `arn:aws:iam::*:user/pl-prod-iam-003-to-admin-target-user` -- delete one of the target admin user's existing access keys to free up a slot
- `iam:CreateAccessKey` on `arn:aws:iam::*:user/pl-prod-iam-003-to-admin-target-user` -- create a new access key for the target admin user under attacker control

**Helpful** (`pl-prod-iam-003-to-admin-starting-user`):
- `iam:ListAccessKeys` -- list existing access keys to identify which one to delete
- `iam:ListUsers` -- discover privileged users to target
- `iam:GetUser` -- view user details and attached policies
- `iam:ListAttachedUserPolicies` -- identify users with admin permissions

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_admin_iam_003_iam_deleteaccesskey_createaccesskey
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
| `arn:aws:iam::{account_id}:user/pl-prod-iam-003-to-admin-starting-user` | Scenario-specific starting user with access keys and permissions to delete and create access keys |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-003-to-admin-target-user` | Target admin user with AdministratorAccess managed policy attached and 2 pre-existing access keys |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Demonstrate bypassing the 2-key limit by deleting an existing key
4. Verify successful privilege escalation
5. Output standardized test results for automation

#### Resources Created by Attack Script

- New IAM access key created for `pl-prod-iam-003-to-admin-target-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-003-iam-deleteaccesskey+createaccesskey
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-003-iam-deleteaccesskey+createaccesskey
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_iam_003_iam_deleteaccesskey_createaccesskey
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

- IAM user (`pl-prod-iam-003-to-admin-starting-user`) has `iam:DeleteAccessKey` permission on a privileged user — privilege escalation path via credential manipulation
- IAM user (`pl-prod-iam-003-to-admin-starting-user`) has `iam:CreateAccessKey` permission on a privileged user — allows creation of new credentials for admin account
- Combined `iam:DeleteAccessKey` + `iam:CreateAccessKey` permissions on the same target user creates a bypass for AWS's 2-key limit, enabling credential takeover even when both slots are occupied

#### Prevention Recommendations

- Implement least privilege principles - avoid granting `iam:DeleteAccessKey` and `iam:CreateAccessKey` permissions unless absolutely necessary
- Use resource-based conditions to restrict which users can have access keys deleted or created: `"Condition": {"StringNotEquals": {"aws:username": ["admin-user"]}}`
- Implement Service Control Policies (SCPs) at the organization level to prevent access key operations on privileged accounts
- Enable MFA requirements for sensitive IAM operations using condition keys like `aws:MultiFactorAuthPresent`
- Use IAM Access Analyzer to identify and remediate privilege escalation paths involving `iam:DeleteAccessKey` and `iam:CreateAccessKey` permissions
- Consider using IAM roles instead of IAM users for administrative access, as roles cannot have access keys created by other principals
- Maintain an inventory of all access keys for privileged accounts and alert on unexpected key lifecycle events (creation, deletion, rotation)

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: ListAccessKeys` — Enumeration of existing access keys on a target user; baseline behavior for this attack pattern
- `IAM: DeleteAccessKey` — Access key deleted for an IAM user; critical when the target has elevated permissions and precedes a CreateAccessKey call
- `IAM: CreateAccessKey` — New access keys created for an IAM user; critical when the target has elevated permissions; correlate with preceding DeleteAccessKey on the same user

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
