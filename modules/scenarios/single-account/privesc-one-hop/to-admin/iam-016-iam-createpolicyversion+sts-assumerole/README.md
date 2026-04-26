# IAM Policy Version + Role Assumption to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** principal-access
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Modify customer-managed policy version to grant admin permissions, then assume role
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_iam_016_iam_createpolicyversion_sts_assumerole`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** iam-016
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-016-to-admin-starting-user` IAM user to the `pl-prod-iam-016-to-admin-target-role` administrative role by creating a new version of a customer-managed IAM policy with administrative permissions and then assuming the now-privileged role.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-016-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-iam-016-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-iam-016-to-admin-starting-user`):
- `iam:CreatePolicyVersion` on `arn:aws:iam::*:policy/pl-prod-iam-016-to-admin-target-policy` -- create a new default version of the customer-managed policy with arbitrary permissions
- `sts:AssumeRole` on `arn:aws:iam::*:role/pl-prod-iam-016-to-admin-target-role` -- assume the target role after its policy has been elevated to admin

**Helpful** (`pl-prod-iam-016-to-admin-starting-user`):
- `iam:GetPolicy` -- get policy ARN and current version information
- `iam:GetPolicyVersion` -- view current policy document and version details
- `iam:ListPolicyVersions` -- list all policy versions to verify new version creation
- `iam:ListRoles` -- discover roles that have the target policy attached
- `iam:GetRole` -- view role details and attached policies

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable iam-016-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-016-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-016-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:policy/pl-prod-iam-016-to-admin-target-policy` | Customer-managed policy with initial non-privileged permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-iam-016-to-admin-target-role` | Target role with the customer-managed policy attached and trust policy allowing starting user to assume it |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/iam-016-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

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

- New IAM policy version (v2) with administrative permissions (`*:*` on `*`) on `pl-prod-iam-016-to-admin-target-policy`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-016-iam-createpolicyversion+sts-assumerole
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-016-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-016-iam-createpolicyversion+sts-assumerole
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-016-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable iam-016-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-016-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user has `iam:CreatePolicyVersion` permission on a customer-managed policy attached to a privileged role, creating a privilege escalation path
- Customer-managed policy attached to a role with admin or high-privilege permissions is modifiable by non-admin principals
- Privilege escalation path: `starting_user → iam:CreatePolicyVersion → target_policy → target_role (admin)`

#### Prevention Recommendations

- **Restrict CreatePolicyVersion Permission**: Limit `iam:CreatePolicyVersion` to security administrators and infrastructure teams only. This permission is as dangerous as `iam:AttachRolePolicy` or `iam:PutRolePolicy`.
- **Use Condition Keys**: Apply condition keys to `iam:CreatePolicyVersion` permissions to restrict which policies can be modified (e.g., `aws:RequestedRegion` or custom tags).
- **Prefer AWS-Managed Policies**: For privileged roles, use AWS-managed policies when possible, as they cannot be versioned or modified by customer accounts.
- **Implement SCPs**: Create Service Control Policies that prevent policy version creation on sensitive customer-managed policies:
  ```json
  {
    "Effect": "Deny",
    "Action": "iam:CreatePolicyVersion",
    "Resource": "arn:aws:iam::*:policy/sensitive-*"
  }
  ```
- **Monitor Policy Version Changes**: Set up CloudTrail alerts for `CreatePolicyVersion` API calls, especially on policies attached to privileged roles. Create CloudWatch alarms or EventBridge rules to detect this activity.
- **Regular Policy Audits**: Periodically review customer-managed policies and their versions to detect unauthorized changes. Look for policies with multiple versions where the latest version has significantly more permissions.
- **IAM Access Analyzer**: Use IAM Access Analyzer to continuously monitor for privilege escalation paths involving policy version manipulation.
- **Limit Policy Scope**: When creating customer-managed policies for roles, minimize the permissions granted and avoid granting permissions that allow self-modification.
- **Require MFA**: Implement MFA requirements for sensitive IAM operations including policy version creation through condition keys in SCPs or IAM policies.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: CreatePolicyVersion` -- New policy version created; critical when the target policy is attached to a privileged role, as new versions automatically become the default
- `STS: AssumeRole` -- Role assumption; high severity when the assumed role has administrator permissions and follows a recent `CreatePolicyVersion` call

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
