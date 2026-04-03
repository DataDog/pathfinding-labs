# One-Hop Privilege Escalation: iam:PutRolePolicy + sts:AssumeRole

* **Category:** Privilege Escalation
* **Sub-Category:** principal-access
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Modify another role's inline policy and assume it
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_iam_017_iam_putrolepolicy_sts_assumerole`
* **Schema Version:** 4.0.0
* **Pathfinding.cloud ID:** iam-017
* **MITRE Tactics:** TA0004 - Privilege Escalation
* **MITRE Techniques:** T1098 - Account Manipulation

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-017-to-admin-starting-user` IAM user to the `pl-prod-iam-017-to-admin-target-role` administrative role by adding an inline admin policy to the target role via `iam:PutRolePolicy` and then assuming it with `sts:AssumeRole`.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-017-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-iam-017-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-iam-017-to-admin-starting-user`):
- `iam:PutRolePolicy` on `arn:aws:iam::*:role/pl-prod-iam-017-to-admin-target-role` -- write inline policies onto the target role
- `sts:AssumeRole` on `arn:aws:iam::*:role/pl-prod-iam-017-to-admin-target-role` -- assume the target role after its policy has been modified

**Helpful** (`pl-prod-iam-017-to-admin-starting-user`):
- `iam:ListRoles` -- discover available roles that can be modified
- `iam:GetRole` -- view role trust policies to identify assumable roles
- `iam:ListRolePolicies` -- view current inline role policies
- `iam:GetRolePolicy` -- view inline policy details before and after modification

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_admin_iam_017_iam_putrolepolicy_sts_assumerole
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
| `arn:aws:iam::{account_id}:user/pl-prod-iam-017-to-admin-starting-user` | Scenario-specific starting user with access keys and inline policy |
| `arn:aws:iam::{account_id}:role/pl-prod-iam-017-to-admin-target-role` | Target role that trusts the starting user and can be modified |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve scenario credentials from Terraform outputs
2. Verify the starting user identity and confirm the absence of admin permissions
3. Check the target role's current inline policies
4. Use `iam:PutRolePolicy` to add an inline policy granting `AdministratorAccess` to the target role
5. Wait 15 seconds for IAM policy propagation
6. Use `sts:AssumeRole` to assume the now-privileged target role
7. Verify administrator access by listing IAM users

#### Resources Created by Attack Script

- Inline admin policy named `admin-escalation` added to `pl-prod-iam-017-to-admin-target-role`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-017-iam-putrolepolicy+sts-assumerole
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-017-iam-putrolepolicy+sts-assumerole
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_iam_017_iam_putrolepolicy_sts_assumerole
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

- IAM user has `iam:PutRolePolicy` permission on a role it can also assume — this combination is a direct privilege escalation path
- IAM role trust policy allows assumption by a principal that also holds policy-write permissions on that role
- Inline policy write access on a role without restrictions on which principals can modify it

#### Prevention Recommendations

- Avoid granting `iam:PutRolePolicy` permissions on assumable roles — this combination is functionally equivalent to granting admin access
- Use resource-based conditions to restrict which roles can have inline policies modified: `"Condition": {"StringNotEquals": {"aws:PrincipalArn": "arn:aws:iam::ACCOUNT:role/trusted-admin"}}`
- Implement SCPs to prevent inline policy modification on sensitive roles: `"Effect": "Deny", "Action": "iam:PutRolePolicy", "Resource": "arn:aws:iam::*:role/prod-*"`
- Enable MFA requirements for policy modification operations using IAM policy conditions
- Use IAM Access Analyzer to identify roles with both write policy permissions and assume role capabilities — flag these as high-risk configurations
- Consider using AWS Config rules to detect when roles gain new inline policies, especially those granting administrative permissions
- Prefer managed policies over inline policies for better visibility and centralized management

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: PutRolePolicy` -- Inline policy added or modified on a role; critical when the target role is assumable and the new policy grants elevated permissions
- `STS: AssumeRole` -- Role assumption event; high severity when preceded by a `PutRolePolicy` call on the same role within a short time window

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
