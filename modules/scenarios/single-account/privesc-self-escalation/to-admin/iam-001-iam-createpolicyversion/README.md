# IAM Policy Version Creation to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** self-escalation
* **Path Type:** self-escalation
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Self-modification via iam:CreatePolicyVersion
* **Terraform Variable:** `enable_single_account_privesc_self_escalation_to_admin_iam_001_iam_createpolicyversion`
* **Schema Version:** 4.6.0
* **CTF Flag Location:** ssm-parameter
* **Pathfinding.cloud ID:** iam-001
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098 - Account Manipulation, T1098.001 - Additional Cloud Credentials

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-001-to-admin-starting-user` IAM user to effective administrator access by assuming the `pl-prod-iam-001-to-admin-starting-role` and using `iam:CreatePolicyVersion` to replace the role's own attached policy with one that grants `AdministratorAccess`.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-iam-001-to-admin-starting-role` (after self-escalation to AdministratorAccess)

### Starting Permissions

**Required** (`pl-prod-iam-001-to-admin-starting-user`):
- `iam:CreatePolicyVersion` on `arn:aws:iam::*:policy/*` -- creates a new version of the managed policy attached to the role, replacing it with an admin policy document

**Helpful** (`pl-prod-iam-001-to-admin-starting-user`):
- `iam:ListPolicyVersions` -- list existing policy versions before creating a new one
- `iam:GetPolicyVersion` -- view content of existing policy versions for reconnaissance

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable iam-001-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-001-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-001-to-admin-starting-user` | Scenario-specific starting user with AssumeRole permission |
| `arn:aws:iam::{account_id}:role/pl-prod-iam-001-to-admin-starting-role` | Starting role with policy versioning capability |
| `arn:aws:iam::{account_id}:policy/pl-prod-iam-001-to-admin-policy` | Allows `iam:CreatePolicyVersion` and `iam:ListPolicyVersions` on itself |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/iam-001-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

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

- New IAM policy version (v2) with `AdministratorAccess` permissions attached to `pl-prod-iam-001-to-admin-policy`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-001-iam-createpolicyversion
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-001-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-001-iam-createpolicyversion
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-001-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable iam-001-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-001-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM role has `iam:CreatePolicyVersion` permission on policies attached to itself, enabling self-escalation
- Policy allows modification of the same policy that grants the permission (circular privilege escalation path)
- Role can effectively grant itself `AdministratorAccess` without any external approval

#### Prevention Recommendations

- Avoid granting `iam:CreatePolicyVersion` permissions on policies attached to the same role
- If required, use resource-based conditions to restrict which policies can be modified
- Implement SCPs to prevent policy version manipulation for privilege escalation
- Enable MFA requirements for sensitive operations
- Use IAM Access Analyzer to identify privilege escalation paths
- Implement alerting on policy version changes for critical roles
- Limit the number of policy versions that can exist (AWS allows up to 5)

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `iam:CreatePolicyVersion` -- New policy version created; critical when the creating principal is also attached to the modified policy, indicating self-escalation
- `iam:ListPolicyVersions` -- Reconnaissance to enumerate existing policy versions before creating a new one
- `sts:AssumeRole` -- Role assumption from starting user; monitor for assumption of roles with policy modification capabilities

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
