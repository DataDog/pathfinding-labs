# Self-Escalation Privilege Escalation: iam:PutGroupPolicy

* **Category:** Privilege Escalation
* **Sub-Category:** self-escalation
* **Path Type:** self-escalation
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Self-escalation via inline policy addition to own group
* **Terraform Variable:** `enable_single_account_privesc_self_escalation_to_admin_iam_011_iam_putgrouppolicy`
* **Schema Version:** 3.0.0
* **Pathfinding.cloud ID:** iam-011
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098 - Account Manipulation, T1098.001 - Additional Cloud Credentials

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-011-to-admin-paul` IAM user to administrator access by using `iam:PutGroupPolicy` to add an inline administrator policy to `pl-prod-iam-011-to-admin-escalation-group`, a group the starting user is already a member of.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-011-to-admin-paul`
- **Destination resource:** `arn:aws:iam::{account_id}:group/pl-prod-iam-011-to-admin-escalation-group` (admin access via group membership)

### Starting Permissions

**Required:**
- `iam:PutGroupPolicy` on `*` -- add inline policies to IAM groups

**Helpful:**
- `iam:ListGroups` -- list groups the user belongs to
- `iam:GetGroupPolicy` -- view existing inline group policies
- `iam:ListGroupPolicies` -- list all inline policies on a group

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_self_escalation_to_admin_iam_011_iam_putgrouppolicy
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
| `arn:aws:iam::{account_id}:user/pl-prod-iam-011-to-admin-paul` | Vulnerable user with PutGroupPolicy permission on their own group |
| `arn:aws:iam::{account_id}:group/pl-prod-iam-011-to-admin-escalation-group` | Target group that pl-prod-iam-011-to-admin-paul belongs to |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Verify successful privilege escalation
4. Output standardized test results for automation

#### Resources Created by Attack Script

- Inline group policy (`EscalatedAdminAccess`) added to `pl-prod-iam-011-to-admin-escalation-group`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-011-iam-putgrouppolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-011-iam-putgrouppolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_self_escalation_to_admin_iam_011_iam_putgrouppolicy
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

- IAM user `pl-prod-iam-011-to-admin-paul` has `iam:PutGroupPolicy` permission scoped to the group they are a member of, enabling self-escalation
- Group `pl-prod-iam-011-to-admin-escalation-group` can receive inline policies from its own members, creating a privilege escalation path
- Privilege escalation path detected: a non-admin user can reach admin access through inline policy attachment on a group they belong to

#### Prevention Recommendations

- Avoid granting `iam:PutGroupPolicy` permissions broadly
- Use resource-based conditions to restrict which groups can have policies added
- Implement SCPs to prevent inline policy additions on sensitive groups
- Monitor CloudTrail for `PutGroupPolicy` API calls
- Use IAM Access Analyzer to identify privilege escalation paths through group memberships
- Prefer managed policies over inline policies for better governance
- Regularly audit group memberships and their effective permissions

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: PutGroupPolicy` -- Inline policy added to a group; critical when the calling user is a member of the target group and the policy grants elevated permissions

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
