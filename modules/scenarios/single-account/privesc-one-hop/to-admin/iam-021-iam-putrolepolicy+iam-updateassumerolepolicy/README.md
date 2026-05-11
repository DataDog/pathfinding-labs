# IAM Inline Role Policy + Trust Policy Update to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** principal-access
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Modifying a role's inline policy to grant admin permissions and updating its trust policy to allow assumption
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_iam_021_iam_putrolepolicy_iam_updateassumerolepolicy`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** iam-021
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation
* **MITRE Techniques:** T1098 - Account Manipulation

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-021-to-admin-starting-user` IAM user to the `pl-prod-iam-021-to-admin-target-role` administrative role by adding an inline admin policy to the target role and updating its trust policy to allow yourself to assume it.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-021-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-iam-021-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-iam-021-to-admin-starting-user`):
- `iam:PutRolePolicy` on `arn:aws:iam::*:role/pl-prod-iam-021-to-admin-target-role` -- add an inline policy granting administrative permissions to the target role
- `iam:UpdateAssumeRolePolicy` on `arn:aws:iam::*:role/pl-prod-iam-021-to-admin-target-role` -- modify the target role's trust policy to allow the starting user to assume it

**Helpful** (`pl-prod-iam-021-to-admin-starting-user`):
- `iam:ListRoles` -- discover available roles that can be modified
- `iam:GetRole` -- view role trust policies and current policies
- `iam:ListRolePolicies` -- view current inline role policies
- `iam:GetRolePolicy` -- view inline policy details before and after modification

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
plabs enable iam-021-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-021-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-021-to-admin-starting-user` | Scenario-specific starting user with access keys and permissions to modify target role |
| `arn:aws:iam::{account_id}:role/pl-prod-iam-021-to-admin-target-role` | Target role with minimal initial permissions that can be escalated |
| `arn:aws:iam::{account_id}:policy/pl-prod-iam-021-to-admin-starting-user-policy` | Inline policy granting iam:PutRolePolicy and iam:UpdateAssumeRolePolicy on target role |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/iam-021-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Demonstrate adding an admin inline policy to the target role
4. Demonstrate updating the trust policy to allow assumption
5. Verify successful privilege escalation by assuming the role and testing admin permissions
6. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions


#### Resources Created by Attack Script

- Inline admin policy added to `pl-prod-iam-021-to-admin-target-role`
- Updated trust policy on `pl-prod-iam-021-to-admin-target-role` adding starting user as trusted principal

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-021-iam-putrolepolicy+iam-updateassumerolepolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-021-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-021-iam-putrolepolicy+iam-updateassumerolepolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-021-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable iam-021-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-021-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user `pl-prod-iam-021-to-admin-starting-user` has both `iam:PutRolePolicy` and `iam:UpdateAssumeRolePolicy` on `pl-prod-iam-021-to-admin-target-role`, forming a complete privilege escalation path to admin
- Principal with permission to modify inline policies on roles that have or can acquire administrative permissions
- Principal with permission to update trust policies on roles, enabling unauthorized role assumption

#### Prevention Recommendations

- Implement least privilege principles - avoid granting `iam:PutRolePolicy` and `iam:UpdateAssumeRolePolicy` together unless absolutely necessary for administrative functions
- Use resource-based conditions to restrict which roles can have their policies modified: `"Condition": {"StringNotLike": {"iam:PolicyArn": ["arn:aws:iam::*:role/admin-*"]}}`
- Implement Service Control Policies (SCPs) at the organization level to prevent modification of critical role trust policies and inline policies
- Enable MFA requirements for sensitive IAM operations using condition keys like `aws:MultiFactorAuthPresent`
- Use IAM Access Analyzer to identify and remediate privilege escalation paths involving policy modification permissions
- Consider using permission boundaries on roles to limit the maximum permissions that can be granted via inline policies
- Regularly audit roles with both `iam:PutRolePolicy` and `iam:UpdateAssumeRolePolicy` permissions to ensure they are truly necessary and appropriately scoped

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `iam:PutRolePolicy` -- Inline policy added or modified on a role; critical when targeting roles with elevated permissions or when the policy grants broad access
- `iam:UpdateAssumeRolePolicy` -- Trust policy updated on a role; high severity when a new principal is added as trusted, especially after a PutRolePolicy call on the same role
- `sts:AssumeRole` -- Role assumption; correlate with preceding PutRolePolicy and UpdateAssumeRolePolicy calls on the same role to identify this attack pattern

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
