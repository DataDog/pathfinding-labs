# IAM Policy Attachment + Role Assumption to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** principal-access
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Attaching administrator policy to an assumable role to gain admin access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_iam_014_iam_attachrolepolicy_sts_assumerole`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** iam-014
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation
* **MITRE Techniques:** T1098 - Account Manipulation

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-014-to-admin-starting-user` IAM user to the `pl-prod-iam-014-to-admin-target-role` administrative role by attaching the `AdministratorAccess` managed policy to the target role and then assuming it.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-014-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-iam-014-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-iam-014-to-admin-starting-user`):
- `iam:AttachRolePolicy` on `arn:aws:iam::*:role/pl-prod-iam-014-to-admin-target-role` -- attach managed policies to the target role
- `sts:AssumeRole` on `arn:aws:iam::*:role/pl-prod-iam-014-to-admin-target-role` -- assume the target role after elevating its permissions

**Helpful** (`pl-prod-iam-014-to-admin-starting-user`):
- `iam:ListRoles` -- discover available roles that can be modified
- `iam:GetRole` -- view role trust policies to identify assumable roles
- `iam:ListAttachedRolePolicies` -- view current role permissions before and after modification

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable iam-014-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-014-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-014-to-admin-starting-user` | Scenario-specific starting user with access keys and inline policy granting iam:AttachRolePolicy and sts:AssumeRole |
| `arn:aws:iam::{account_id}:role/pl-prod-iam-014-to-admin-target-role` | Target role with minimal permissions that can be modified and assumed |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/iam-014-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Verify successful privilege escalation
4. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions


#### Resources Created by Attack Script

- Managed policy attachment: `AdministratorAccess` attached to `pl-prod-iam-014-to-admin-target-role`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-014-iam-attachrolepolicy+sts-assumerole
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-014-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-014-iam-attachrolepolicy+sts-assumerole
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-014-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable iam-014-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-014-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM principal (`pl-prod-iam-014-to-admin-starting-user`) has both `iam:AttachRolePolicy` and `sts:AssumeRole` on the same target role, creating a complete privilege escalation path
- The target role (`pl-prod-iam-014-to-admin-target-role`) is assumable by a principal that can also modify its own attached policies
- Privilege escalation path exists: starting user can elevate to admin by attaching `AdministratorAccess` and assuming the target role

#### Prevention Recommendations

- **Implement SCPs to restrict policy attachment**: Use service control policies to prevent attachment of highly privileged managed policies like `AdministratorAccess` or `PowerUserAccess`
- **Separate attachment and assumption permissions**: Avoid granting both `iam:AttachRolePolicy` and `sts:AssumeRole` to the same principal for the same role
- **Use resource-based conditions on AttachRolePolicy**: Restrict which policies can be attached using the `iam:PolicyARN` condition key to prevent attachment of admin policies
- **Implement permissions boundaries**: Use IAM permissions boundaries to limit the maximum permissions a role can have, even if admin policies are attached
- **Enable MFA for sensitive operations**: Require MFA for both policy attachment operations and role assumption to add an additional security layer
- **Use IAM Access Analyzer**: Regularly scan for privilege escalation paths involving policy modification and role assumption combinations
- **Apply least privilege**: Grant `iam:AttachRolePolicy` only when absolutely necessary, and scope it to specific roles with resource ARN conditions
- **Implement approval workflows**: Require manual approval for attaching managed policies to roles, especially AWS-managed policies with broad permissions

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `iam:AttachRolePolicy` -- Managed policy attached to a role; critical when the attached policy is `AdministratorAccess` or similarly broad, especially when followed by a role assumption
- `sts:AssumeRole` -- Role assumption event; high severity when the assumed role was recently modified via `AttachRolePolicy` within the same session or time window

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
