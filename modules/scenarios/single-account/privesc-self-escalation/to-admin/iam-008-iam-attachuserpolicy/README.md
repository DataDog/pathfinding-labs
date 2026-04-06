# IAM Managed User Policy Attachment to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** self-escalation
* **Path Type:** self-escalation
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** User self-modification via iam:AttachUserPolicy to attach managed admin policy
* **Terraform Variable:** `enable_single_account_privesc_self_escalation_to_admin_iam_008_iam_attachuserpolicy`
* **Schema Version:** 4.0.0
* **Pathfinding.cloud ID:** iam-008
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098 - Account Manipulation, T1098.001 - Additional Cloud Credentials

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-008-to-admin-starting-user` IAM user to effective administrator access by using `iam:AttachUserPolicy` to attach the AWS-managed `AdministratorAccess` policy to yourself.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-008-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::aws:policy/AdministratorAccess` (attached to starting user, granting full admin)

### Starting Permissions

**Required** (`pl-prod-iam-008-to-admin-starting-user`):
- `iam:AttachUserPolicy` on `*` -- allows the user to attach any managed policy to themselves

**Helpful** (`pl-prod-iam-008-to-admin-starting-user`):
- `iam:ListAttachedUserPolicies` -- list managed policies currently attached to the user
- `iam:ListPolicies` -- discover available managed policies to attach

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_self_escalation_to_admin_iam_008_iam_attachuserpolicy
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
| `arn:aws:iam::{account_id}:role/pl-iam-008-adam` | Role with AttachUserPolicy permission |
| `arn:aws:iam::{account_id}:user/pl-iam-008-user` | User with AttachUserPolicy permission |
| `arn:aws:iam::{account_id}:policy/pl-prod-one-hop-attachuserpolicy-policy` | Policy allowing `iam:AttachUserPolicy` on any resource |

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

- Managed policy attachment: `arn:aws:iam::aws:policy/AdministratorAccess` attached to the starting user

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-008-iam-attachuserpolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-008-iam-attachuserpolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_self_escalation_to_admin_iam_008_iam_attachuserpolicy
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

- IAM user has `iam:AttachUserPolicy` permission on `*`, enabling self-attachment of any managed policy
- Privilege escalation path detected: user can attach `AdministratorAccess` to themselves
- No resource constraint on `iam:AttachUserPolicy` — no `iam:PolicyARN` condition key limiting attachable policies

#### Prevention Recommendations

- Never grant `iam:AttachUserPolicy` permissions without strict resource constraints
- Use SCPs to prevent managed policy attachments on privileged users
- Implement least privilege — users should not be able to modify their own permissions
- Restrict which managed policies can be attached using `iam:PolicyARN` condition keys
- Use IAM Access Analyzer to identify privilege escalation paths
- Enable MFA requirements for sensitive IAM operations
- Set up alerts for attachment of high-privilege managed policies like AdministratorAccess

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: AttachUserPolicy` -- Managed policy attached to an IAM user; critical when the target user is the caller (self-attachment) or when the attached policy is `AdministratorAccess`

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
