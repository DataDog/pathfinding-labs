# One-Hop Privilege Escalation: sts:AssumeRole

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Direct role assumption via sts:AssumeRole
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_sts_001_sts_assumerole`
* **Schema Version:** 4.0.0
* **Pathfinding.cloud ID:** sts-001
* **MITRE Tactics:** TA0004 - Privilege Escalation
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-sts-001-to-admin-starting-user` IAM user to the `pl-prod-sts-001-to-admin-target-role` administrative role by directly calling `sts:AssumeRole` to obtain temporary credentials with full `AdministratorAccess`.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-sts-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-sts-001-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-sts-001-to-admin-starting-user`):
- `sts:AssumeRole` on `arn:aws:iam::*:role/pl-prod-sts-001-to-admin-target-role` -- allows the starting user to assume the admin role directly

**Helpful** (`pl-prod-sts-001-to-admin-starting-user`):
- `iam:ListRoles` -- discover available roles to assume
- `iam:GetRole` -- view role permissions and trust policy

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_admin_sts_001_sts_assumerole
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
| `arn:aws:iam::{account_id}:user/pl-prod-sts-001-to-admin-starting-user` | Starting user with sts:AssumeRole permission |
| `arn:aws:iam::{account_id}:role/pl-prod-sts-001-to-admin-target-role` | Admin role with AdministratorAccess policy attached |
| `arn:aws:iam::aws:policy/AdministratorAccess` | AWS-managed policy granting full admin permissions |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve starting user credentials from Terraform output
2. Verify identity as the starting user and confirm no admin access
3. Call `sts:AssumeRole` to directly assume `pl-prod-sts-001-to-admin-target-role`
4. Verify the new identity and confirm administrator access by listing IAM users

#### Resources Created by Attack Script

- No persistent artifacts are created; this scenario only involves role assumption (temporary session credentials are used in-memory)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo sts-001-sts-assumerole
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup sts-001-sts-assumerole
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_sts_001_sts_assumerole
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

- IAM user `pl-prod-sts-001-to-admin-starting-user` has `sts:AssumeRole` permission targeting an administrative role
- Role `pl-prod-sts-001-to-admin-target-role` has a trust policy allowing assumption by a non-privileged user
- Privilege escalation path exists: non-admin user can directly assume a role with `AdministratorAccess`
- Role trust policy does not enforce MFA or session conditions for assumption of an admin-level role

#### Prevention Recommendations

- Avoid allowing direct assumption of roles with administrative permissions
- Use the principle of least privilege when configuring trust relationships
- Implement SCPs to restrict who can assume privileged roles
- Monitor CloudTrail for `AssumeRole` API calls to administrative roles
- Enable MFA requirements for assuming sensitive roles
- Use IAM Access Analyzer to identify overly permissive trust policies
- Implement session policies to limit permissions even when assuming privileged roles
- Use AWS Config rules to detect roles with administrative permissions that can be assumed by users

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `STS: AssumeRole` -- Role assumption call; high severity when the target role has administrative permissions attached

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._