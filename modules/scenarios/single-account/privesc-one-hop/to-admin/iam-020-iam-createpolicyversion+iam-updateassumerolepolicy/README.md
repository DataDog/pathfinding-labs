# IAM Policy Version + Trust Policy Update to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** principal-access
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Modify customer-managed policy permissions and role trust policy to gain admin access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_iam_020_iam_createpolicyversion_iam_updateassumerolepolicy`
* **Schema Version:** 4.0.0
* **Pathfinding.cloud ID:** iam-020
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-020-to-admin-starting-user` IAM user to the `pl-prod-iam-020-to-admin-target-role` administrative role by creating a new version of a customer-managed policy with full administrative permissions and updating the role's trust policy to allow assumption by the starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-020-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-iam-020-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-iam-020-to-admin-starting-user`):
- `iam:CreatePolicyVersion` on `arn:aws:iam::*:policy/pl-prod-iam-020-to-admin-target-policy` -- create a new default version of the customer-managed policy with elevated permissions
- `iam:UpdateAssumeRolePolicy` on `arn:aws:iam::*:role/pl-prod-iam-020-to-admin-target-role` -- modify the role's trust policy to allow the starting user to assume it

**Helpful** (`pl-prod-iam-020-to-admin-starting-user`):
- `iam:GetPolicy` -- get policy ARN and current version information
- `iam:GetPolicyVersion` -- view current policy document and version details
- `iam:ListPolicyVersions` -- list all policy versions to verify new version creation
- `iam:ListRoles` -- discover roles that have the target policy attached
- `iam:GetRole` -- view role details, trust policy, and attached policies

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_admin_iam_020_iam_createpolicyversion_iam_updateassumerolepolicy
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
| `arn:aws:iam::{account_id}:user/pl-prod-iam-020-to-admin-starting-user` | Scenario-specific starting user with access keys and limited permissions |
| `arn:aws:iam::{account_id}:policy/pl-prod-iam-020-to-admin-target-policy` | Customer-managed policy attached to the target role (initially has minimal permissions) |
| `arn:aws:iam::{account_id}:role/pl-prod-iam-020-to-admin-target-role` | Target role with the customer-managed policy attached (initially has limited trust policy) |
| `arn:aws:iam::{account_id}:policy/pl-prod-iam-020-to-admin-starting-user-policy` | Policy granting CreatePolicyVersion and UpdateAssumeRolePolicy permissions to the starting user |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Demonstrate policy version creation with admin permissions
4. Show trust policy modification to add the starting user
5. Assume the role without needing explicit sts:AssumeRole permissions
6. Verify successful privilege escalation with admin-level API calls
7. Output standardized test results for automation

#### Resources Created by Attack Script

- New policy version on `pl-prod-iam-020-to-admin-target-policy` with administrative permissions (`*:*`)
- Modified trust policy on `pl-prod-iam-020-to-admin-target-role` adding the starting user as a trusted principal
- Temporary AWS CLI profile for the assumed role session

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-020-iam-createpolicyversion+iam-updateassumerolepolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-020-iam-createpolicyversion+iam-updateassumerolepolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_iam_020_iam_createpolicyversion_iam_updateassumerolepolicy
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

- **Dangerous Permission Combination**: User/role has both `iam:CreatePolicyVersion` and `iam:UpdateAssumeRolePolicy` permissions
- **Privilege Escalation Path**: Attack graph analysis should identify the escalation path from starting user to admin role via policy modification
- **Overly Permissive IAM Grants**: Starting user can modify policies attached to roles they cannot initially assume
- **Customer-Managed Policy Vulnerability**: Roles using customer-managed policies that can be modified by non-admin principals
- **Trust Policy Modification Risk**: Principals with `iam:UpdateAssumeRolePolicy` can grant themselves access to privileged roles

#### Prevention Recommendations

- **Restrict CreatePolicyVersion permissions**: Grant `iam:CreatePolicyVersion` only to administrative roles and limit it with resource-based conditions to specific policies
  ```json
  {
    "Effect": "Allow",
    "Action": "iam:CreatePolicyVersion",
    "Resource": "arn:aws:iam::*:policy/approved-policy-prefix-*"
  }
  ```

- **Restrict UpdateAssumeRolePolicy permissions**: Limit `iam:UpdateAssumeRolePolicy` to break glass administrative roles only
  ```json
  {
    "Effect": "Deny",
    "Action": "iam:UpdateAssumeRolePolicy",
    "Resource": "*",
    "Condition": {
      "StringNotEquals": {
        "aws:PrincipalArn": "arn:aws:iam::ACCOUNT_ID:role/BreakGlassAdmin"
      }
    }
  }
  ```

- **Use AWS managed policies where possible**: AWS managed policies cannot be modified with `iam:CreatePolicyVersion`, eliminating this attack vector

- **Implement policy version limits**: AWS allows up to 5 policy versions. Regularly audit and delete old versions to make policy modification more detectable

- **Require MFA for sensitive IAM operations**: Use SCP or IAM conditions to require MFA for `iam:CreatePolicyVersion` and `iam:UpdateAssumeRolePolicy`
  ```json
  {
    "Effect": "Deny",
    "Action": [
      "iam:CreatePolicyVersion",
      "iam:UpdateAssumeRolePolicy"
    ],
    "Resource": "*",
    "Condition": {
      "BoolIfExists": {
        "aws:MultiFactorAuthPresent": "false"
      }
    }
  }
  ```

- **Use AWS IAM Access Analyzer**: Configure policy validation and external access findings to detect when roles can be assumed by unintended principals

- **Implement separation of duties**: Never grant the same principal both `iam:CreatePolicyVersion` and `iam:UpdateAssumeRolePolicy` permissions

- **Monitor with AWS Config**: Create Config rules to alert when customer-managed policies are modified or role trust policies change

- **Use Service Control Policies (SCPs)**: Implement organization-wide restrictions on policy modification capabilities
  ```json
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Deny",
        "Action": [
          "iam:CreatePolicyVersion",
          "iam:UpdateAssumeRolePolicy"
        ],
        "Resource": "*",
        "Condition": {
          "StringNotLike": {
            "aws:PrincipalArn": "arn:aws:iam::*:role/Admin*"
          }
        }
      }
    ]
  }
  ```

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: CreatePolicyVersion` -- New policy version created; critical when the new version contains significantly elevated permissions (`*:*`) and the requestor is not a trusted admin principal
- `IAM: UpdateAssumeRolePolicy` -- Role trust policy modified; high severity when the requestor is the same principal being added to the trust policy and the modified role has administrative permissions
- `STS: AssumeRole` -- Role assumption; suspicious when it occurs shortly after `CreatePolicyVersion` and `UpdateAssumeRolePolicy` by the same principal; monitor for sequential activity within a short time window

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
