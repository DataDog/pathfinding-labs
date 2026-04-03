# Self-Escalation Privilege Escalation: iam:AttachRolePolicy

* **Category:** Privilege Escalation
* **Sub-Category:** self-escalation
* **Path Type:** self-escalation
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Self-modification via iam:AttachRolePolicy
* **Terraform Variable:** `enable_single_account_privesc_self_escalation_to_admin_iam_009_iam_attachrolepolicy`
* **Schema Version:** 4.0.0
* **Pathfinding.cloud ID:** iam-009
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098 - Account Manipulation, T1098.001 - Additional Cloud Credentials

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-009-to-admin-starting-user` IAM user to effective administrator access by assuming the `pl-prod-iam-009-to-admin-starting-role` role and using `iam:AttachRolePolicy` to attach the AWS-managed `AdministratorAccess` policy to that role itself.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-009-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::aws:policy/AdministratorAccess` (attached to `arn:aws:iam::{account_id}:role/pl-prod-iam-009-to-admin-starting-role`)

### Starting Permissions

**Required** (`pl-prod-iam-009-to-admin-starting-user`):
- `iam:AttachRolePolicy` on `arn:aws:iam::*:role/pl-prod-iam-009-to-admin-starting-role` -- allows the role to attach managed policies to itself

**Helpful** (`pl-prod-iam-009-to-admin-starting-user`):
- `iam:ListAttachedRolePolicies` -- list managed policies currently attached to the role
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
plabs enable enable_single_account_privesc_self_escalation_to_admin_iam_009_iam_attachrolepolicy
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
| `arn:aws:iam::{account_id}:user/pl-prod-iam-009-to-admin-starting-user` | Scenario-specific starting user with AssumeRole permission |
| `arn:aws:iam::{account_id}:role/pl-prod-iam-009-to-admin-starting-role` | Starting role with policy attachment capability |
| `arn:aws:iam::{account_id}:policy/pl-prod-iam-009-to-admin-policy` | Allows `iam:AttachRolePolicy` on the role itself |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve starting user credentials from Terraform outputs
2. Verify identity as `pl-prod-iam-009-to-admin-starting-user`
3. Assume the `pl-prod-iam-009-to-admin-starting-role` role
4. Confirm limited permissions on the role before escalation
5. Attach the `AdministratorAccess` managed policy to the role using `iam:AttachRolePolicy`
6. Wait for policy propagation and verify administrator access is achieved

#### Resources Created by Attack Script

- `AdministratorAccess` managed policy attached to `pl-prod-iam-009-to-admin-starting-role`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-009-iam-attachrolepolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-009-iam-attachrolepolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_self_escalation_to_admin_iam_009_iam_attachrolepolicy
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

- IAM role `pl-prod-iam-009-to-admin-starting-role` has `iam:AttachRolePolicy` permission scoped to itself, enabling self-escalation
- Role can attach the AWS-managed `AdministratorAccess` policy to itself without any additional approval
- No SCP or permission boundary prevents the role from attaching high-privilege managed policies

#### Prevention Recommendations

- Avoid granting `iam:AttachRolePolicy` permissions on roles
- If required, use resource-based conditions to restrict which roles can be modified
- Implement SCPs to prevent self-attachment of policies
- Monitor CloudTrail for `AttachRolePolicy` API calls, especially when roles modify themselves
- Enable MFA requirements for sensitive operations
- Use IAM Access Analyzer to identify privilege escalation paths
- Restrict attachment of high-privilege AWS-managed policies like `AdministratorAccess`
- Use conditions to limit which policies can be attached (e.g., by policy name pattern)

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: AttachRolePolicy` -- Managed policy attached to a role; critical when the role is the same principal making the call (self-escalation)
- `STS: AssumeRole` -- Role assumption by the starting user to obtain the escalation-capable role credentials

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
