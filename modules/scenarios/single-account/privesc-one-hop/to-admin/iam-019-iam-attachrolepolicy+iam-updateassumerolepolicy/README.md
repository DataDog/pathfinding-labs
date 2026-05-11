# IAM Policy Attachment + Trust Policy Update to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** principal-access
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Attaching administrative policies to a role and modifying its trust policy to assume it
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_iam_019_iam_attachrolepolicy_iam_updateassumerolepolicy`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** iam-019
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation
* **MITRE Techniques:** T1098 - Account Manipulation

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-019-to-admin-starting-user` IAM user to the `pl-prod-iam-019-to-admin-target-role` administrative role by attaching the `AdministratorAccess` managed policy to the target role and then modifying its trust policy to allow your user to assume it.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-019-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-iam-019-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-iam-019-to-admin-starting-user`):
- `iam:AttachRolePolicy` on `arn:aws:iam::*:role/pl-prod-iam-019-to-admin-target-role` -- attach the AdministratorAccess managed policy to the target role
- `iam:UpdateAssumeRolePolicy` on `arn:aws:iam::*:role/pl-prod-iam-019-to-admin-target-role` -- modify the target role's trust policy to add the starting user as a trusted principal

**Helpful** (`pl-prod-iam-019-to-admin-starting-user`):
- `iam:ListRoles` -- discover available roles that can be modified
- `iam:GetRole` -- view role trust policies and attached policies
- `iam:ListAttachedRolePolicies` -- view current role permissions before and after modification
- `iam:GetUserPolicy` -- verify starting user does not have sts:AssumeRole permission

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
plabs enable iam-019-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-019-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-019-to-admin-starting-user` | Scenario-specific starting user with access keys and role modification permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-iam-019-to-admin-target-role` | Target role with minimal initial permissions that will be escalated |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/iam-019-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Verify successful privilege escalation
4. Capture the CTF flag from SSM Parameter Store using the assumed admin role session


#### Resources Created by Attack Script

- `AdministratorAccess` managed policy attached to `pl-prod-iam-019-to-admin-target-role`
- Modified trust policy on `pl-prod-iam-019-to-admin-target-role` (adds starting user as trusted principal)
- Temporary STS session credentials from assuming the target role

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-019-iam-attachrolepolicy+iam-updateassumerolepolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-019-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-019-iam-attachrolepolicy+iam-updateassumerolepolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-019-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable iam-019-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-019-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- `pl-prod-iam-019-to-admin-starting-user` has `iam:AttachRolePolicy` permission scoped to `pl-prod-iam-019-to-admin-target-role`, enabling attachment of administrative managed policies
- `pl-prod-iam-019-to-admin-starting-user` has `iam:UpdateAssumeRolePolicy` permission scoped to `pl-prod-iam-019-to-admin-target-role`, enabling trust policy modification
- The combination of `iam:AttachRolePolicy` and `iam:UpdateAssumeRolePolicy` on the same principal constitutes a complete privilege escalation path to admin
- No permission boundary is applied to `pl-prod-iam-019-to-admin-starting-user` to prevent escalation beyond current privilege level
- `pl-prod-iam-019-to-admin-target-role` lacks a resource tag-based condition preventing modification by lower-privileged principals

#### Prevention Recommendations

- Implement least privilege principles - avoid granting `iam:AttachRolePolicy` and `iam:UpdateAssumeRolePolicy` together unless absolutely necessary
- Use resource-based conditions to restrict which roles can be modified: `"Condition": {"StringNotLike": {"aws:ResourceTag/Sensitivity": "critical"}}`
- Implement Service Control Policies (SCPs) to prevent attachment of highly privileged managed policies like AdministratorAccess
- Use IAM Access Analyzer to identify roles with overly permissive trust policies or privilege escalation paths
- Enable MFA requirements for sensitive IAM operations using condition keys like `aws:MultiFactorAuthPresent`
- Implement permission boundaries on users to prevent them from attaching policies that exceed their own permissions
- Tag critical roles and use IAM policy conditions to prevent modification of tagged resources
- Regularly audit role trust policies to ensure only expected principals are trusted

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `iam:AttachRolePolicy` -- Managed policy attached to a role; critical when the attached policy is `AdministratorAccess` or another highly privileged policy
- `iam:UpdateAssumeRolePolicy` -- Role trust policy modified; high severity when the change adds a new trusted principal, especially a user or role not previously trusted
- `sts:AssumeRole` -- Role assumption event; correlate with preceding `AttachRolePolicy` and `UpdateAssumeRolePolicy` events to identify the full escalation chain

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
