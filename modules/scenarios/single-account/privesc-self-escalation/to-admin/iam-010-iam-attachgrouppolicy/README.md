# IAM Managed Group Policy Attachment to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** self-escalation
* **Path Type:** self-escalation
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Self-escalation via attaching admin policy to own group
* **Terraform Variable:** `enable_single_account_privesc_self_escalation_to_admin_iam_010_iam_attachgrouppolicy`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** iam-010
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098 - Account Manipulation, T1098.001 - Additional Cloud Credentials

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-010-to-admin-starting-user` IAM user to administrator access by attaching the `AdministratorAccess` managed policy to the `pl-prod-iam-010-to-admin-group` IAM group that you are already a member of.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-010-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::aws:policy/AdministratorAccess` (attached to `arn:aws:iam::{account_id}:group/pl-prod-iam-010-to-admin-group`)

### Starting Permissions

**Required** (`pl-prod-iam-010-to-admin-starting-user`):
- `iam:AttachGroupPolicy` on `*` -- attach managed policies to IAM groups

**Helpful** (`pl-prod-iam-010-to-admin-starting-user`):
- `iam:ListGroups` -- list groups the user belongs to
- `iam:ListAttachedGroupPolicies` -- view currently attached group policies
- `iam:ListPolicies` -- discover available managed policies

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
plabs enable iam-010-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-010-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-010-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:group/pl-prod-iam-010-to-admin-group` | IAM group that the user belongs to |
| `arn:aws:iam::{account_id}:policy/pl-prod-iam-010-to-admin-attachgrouppolicy-policy` | Allows `iam:AttachGroupPolicy` on the group |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/iam-010-to-admin` | CTF flag (readable with admin access via `ssm:GetParameter`) |

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

- `AdministratorAccess` managed policy attached to `pl-prod-iam-010-to-admin-group`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-010-iam-attachgrouppolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-010-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-010-iam-attachgrouppolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-010-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable iam-010-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-010-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user has `iam:AttachGroupPolicy` permission on a group they are a member of
- Privilege escalation path detected: user can elevate their own permissions via group policy attachment
- Group membership combined with group policy modification permission creates a self-escalation risk

#### Prevention Recommendations

- Avoid granting `iam:AttachGroupPolicy` permissions to users who are members of the target group
- Use resource-based conditions to restrict which groups can have policies attached
- Implement SCPs to prevent policy attachment to sensitive groups
- Monitor CloudTrail for `AttachGroupPolicy` API calls, especially for administrative policies
- Enable MFA requirements for sensitive IAM operations
- Use IAM Access Analyzer to identify privilege escalation paths
- Implement a least-privilege model where users cannot modify their own effective permissions

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `iam:AttachGroupPolicy` -- Managed policy attached to an IAM group; critical when the policy is `AdministratorAccess` or otherwise grants elevated permissions

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
