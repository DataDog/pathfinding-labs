# IAM Inline Role Policy Modification to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** self-escalation
* **Path Type:** self-escalation
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Self-modification via iam:PutRolePolicy
* **Terraform Variable:** `enable_single_account_privesc_self_escalation_to_admin_iam_005_iam_putrolepolicy`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** iam-005
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098 - Account Manipulation, T1098.001 - Additional Cloud Credentials

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-005-to-admin-starting-user` IAM user to effective administrator access by assuming the `pl-prod-iam-005-to-admin-starting-role` role and using `iam:PutRolePolicy` to add an inline administrator policy to that role itself.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-005-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-iam-005-to-admin-starting-role` (with administrator access)

### Starting Permissions

**Required** (`pl-prod-iam-005-to-admin-starting-role`):
- `iam:PutRolePolicy` on `arn:aws:iam::*:role/pl-prod-iam-005-to-admin-starting-role` -- allows the role to add inline policies to itself, enabling self-escalation

**Helpful** (`pl-prod-iam-005-to-admin-starting-user`):
- `iam:GetRolePolicy` -- view existing inline policies on the role
- `iam:ListRolePolicies` -- list all inline policies attached to the role

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
plabs enable iam-005-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-005-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-005-to-admin-starting-user` | Scenario-specific starting user with AssumeRole permission |
| `arn:aws:iam::{account_id}:role/pl-prod-iam-005-to-admin-starting-role` | Starting role with self-modification capability |
| `arn:aws:iam::{account_id}:policy/pl-prod-iam-005-to-admin-policy` | Allows `iam:PutRolePolicy` on the role itself |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/iam-005-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

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

- Inline policy added to `pl-prod-iam-005-to-admin-starting-role` granting administrator access

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-005-iam-putrolepolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-005-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-005-iam-putrolepolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-005-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable iam-005-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-005-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM role `pl-prod-iam-005-to-admin-starting-role` has `iam:PutRolePolicy` on itself, enabling self-escalation to administrator
- Privilege escalation path detected: role can modify its own inline policies to gain admin access
- IAM principal with permissions to modify its own trust or permission boundary

#### Prevention Recommendations

- Avoid granting `iam:PutRolePolicy` permissions on roles
- If required, use resource-based conditions to restrict which roles can be modified
- Implement SCPs to prevent self-modification of roles
- Monitor CloudTrail for `PutRolePolicy` API calls, especially when the role modifies itself
- Enable MFA requirements for sensitive operations
- Use IAM Access Analyzer to identify privilege escalation paths

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `iam:PutRolePolicy` -- Inline policy added to a role; critical when the caller and the target role are the same principal (self-modification)
- `sts:AssumeRole` -- Role assumption event; monitor for the starting user assuming the escalation role

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

