# IAM Role Trust Policy Update to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** principal-access
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Modifying admin role trust policy to grant self-access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_iam_012_iam_updateassumerolepolicy`
* **Schema Version:** 4.1.1
* **Pathfinding.cloud ID:** iam-012
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098 - Account Manipulation, T1078.004 - Valid Accounts: Cloud Accounts

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-012-to-admin-starting-user` IAM user to the `pl-prod-iam-012-to-admin-target-role` administrative role by modifying the role's trust policy to add your own principal as a trusted entity, then assuming the role with `sts:AssumeRole`.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-012-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-iam-012-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-iam-012-to-admin-starting-user`):
- `iam:UpdateAssumeRolePolicy` on `arn:aws:iam::*:role/pl-prod-iam-012-to-admin-target-role` -- allows modifying who is trusted to assume the target role
- `sts:AssumeRole` on `arn:aws:iam::*:role/pl-prod-iam-012-to-admin-target-role` -- allows assuming the target role once the trust policy has been updated

**Helpful** (`pl-prod-iam-012-to-admin-starting-user`):
- `iam:ListRoles` -- discover privileged roles to target
- `iam:GetRole` -- view the current trust policy before modification

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable iam-012-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-012-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-012-to-admin-starting-user` | Scenario-specific starting user with access keys and UpdateAssumeRolePolicy permission |
| `arn:aws:iam::{account_id}:role/pl-prod-iam-012-to-admin-target-role` | Admin role with AdministratorAccess policy, initially trusts only EC2 service |
| `arn:aws:iam::{account_id}:policy/pl-prod-iam-012-to-admin-starting-user-policy` | User policy granting UpdateAssumeRolePolicy and AssumeRole permissions on target role |

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

- Modified trust policy on `pl-prod-iam-012-to-admin-target-role` (attacker's user ARN added as trusted principal)
- Temporary STS session credentials from assuming the admin role

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-012-iam-updateassumerolepolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-012-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-012-iam-updateassumerolepolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-012-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable iam-012-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-012-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user has `iam:UpdateAssumeRolePolicy` permission on a privileged/admin role — direct privilege escalation path
- Role trust policy allows modification by non-privileged principals
- Privilege escalation path detected: `pl-prod-iam-012-to-admin-starting-user` can assume `pl-prod-iam-012-to-admin-target-role` via trust policy manipulation
- IAM user has both `iam:UpdateAssumeRolePolicy` and `sts:AssumeRole` on the same admin role resource

#### Prevention Recommendations

- **Restrict UpdateAssumeRolePolicy permissions**: Avoid granting `iam:UpdateAssumeRolePolicy` permission except to highly trusted automation or security teams
- **Implement resource conditions**: Use IAM condition keys like `aws:RequestedRegion` or `aws:SourceVpc` to limit where trust policy modifications can originate
- **Use SCPs for protection**: Create Service Control Policies (SCPs) that prevent modification of trust policies on critical roles:
  ```json
  {
    "Effect": "Deny",
    "Action": "iam:UpdateAssumeRolePolicy",
    "Resource": "arn:aws:iam::*:role/Admin*",
    "Condition": {
      "StringNotEquals": {
        "aws:PrincipalOrgID": "o-yourorgid"
      }
    }
  }
  ```
- **Require MFA for sensitive operations**: Enforce MFA for any actions that modify role trust relationships using condition keys like `aws:MultiFactorAuthPresent`
- **Use IAM Access Analyzer**: Regularly run IAM Access Analyzer to identify privilege escalation paths involving trust policy modifications
- **Implement least privilege**: Never grant wildcard permissions on `iam:UpdateAssumeRolePolicy` - always specify exact role resources if this permission is needed
- **Audit trust policies regularly**: Include role trust policies in regular security audits, not just identity-based policies

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: UpdateAssumeRolePolicy` -- Trust policy modified on a role; critical when the target role has elevated permissions, indicates potential privilege escalation setup
- `STS: AssumeRole` -- Role assumption event; high severity when preceded by a trust policy modification on the same role within a short time window

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
