# IAM Group Admin Membership to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** self-escalation
* **Path Type:** self-escalation
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Self-escalation via iam:AddUserToGroup to admin group
* **Terraform Variable:** `enable_single_account_privesc_self_escalation_to_admin_iam_013_iam_addusertogroup`
* **Schema Version:** 4.1.1
* **Pathfinding.cloud ID:** iam-013
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098 - Account Manipulation, T1098.001 - Additional Cloud Credentials

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-013-to-admin-user` IAM user to full administrator access by using the `iam:AddUserToGroup` permission to add yourself to `pl-prod-iam-013-to-admin-group`, which has the `AdministratorAccess` managed policy attached.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-013-to-admin-user`
- **Destination resource:** `arn:aws:iam::{account_id}:group/pl-prod-iam-013-to-admin-group`

### Starting Permissions

**Required** (`pl-prod-iam-013-to-admin-user`):
- `iam:AddUserToGroup` on `*` -- add the starting user to the admin group

**Helpful** (`pl-prod-iam-013-to-admin-user`):
- `iam:ListGroups` -- discover groups to target
- `iam:GetGroup` -- view group members and attached policies
- `iam:ListAttachedGroupPolicies` -- identify groups with admin permissions

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable iam-013-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-013-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-013-to-admin-user` | Starting principal with AddUserToGroup permission |
| `arn:aws:iam::{account_id}:group/pl-prod-iam-013-to-admin-group` | Admin group with AdministratorAccess policy |
| Inline policy on `pl-prod-iam-013-to-admin-user` | Allows iam:AddUserToGroup on the admin group |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve starting user credentials from Terraform outputs
2. Verify identity as `pl-prod-iam-013-to-admin-user`
3. Confirm the user currently lacks admin permissions (cannot list IAM users)
4. Execute `iam:AddUserToGroup` to add the user to `pl-prod-iam-013-to-admin-group`
5. Wait for IAM policy propagation and verify administrator access is granted

#### Resources Created by Attack Script

- Group membership: adds `pl-prod-iam-013-to-admin-user` to `pl-prod-iam-013-to-admin-group`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-013-iam-addusertogroup
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-013-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-013-iam-addusertogroup
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-013-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable iam-013-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-013-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user has `iam:AddUserToGroup` permission without resource constraints, allowing addition to any group including admin groups
- Privilege escalation path detected: `pl-prod-iam-013-to-admin-user` can add itself to `pl-prod-iam-013-to-admin-group` which has `AdministratorAccess`
- IAM group with `AdministratorAccess` policy has open membership (no SCP or permission boundary preventing self-addition)

#### Prevention Recommendations

- Avoid granting `iam:AddUserToGroup` permissions on privileged groups
- Use resource-based conditions to restrict which groups users can add members to
- Implement SCPs to prevent adding users to administrative groups
- Monitor CloudTrail for `AddUserToGroup` API calls on privileged groups
- Enable MFA requirements for sensitive IAM operations
- Use IAM Access Analyzer to identify privilege escalation paths
- Require approval workflows for group membership changes to administrative groups

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: AddUserToGroup` -- User added to an IAM group; critical when the target group has elevated or administrative permissions attached

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
