# Privilege Escalation via iam:AttachUserPolicy + iam:CreateAccessKey

* **Category:** Privilege Escalation
* **Sub-Category:** principal-access
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** User with AttachUserPolicy and CreateAccessKey on another user can attach AWS-managed AdministratorAccess policy, create access keys, and gain admin access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_iam_015_iam_attachuserpolicy_iam_createaccesskey`
* **Schema Version:** 4.0.0
* **Pathfinding.cloud ID:** iam-015
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-015-to-admin-starting-user` IAM user to the `pl-prod-iam-015-to-admin-target-user` IAM user (with full administrative access) by attaching the AWS-managed `AdministratorAccess` policy to the target user and then creating access keys to authenticate as them.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-015-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:user/pl-prod-iam-015-to-admin-target-user`

### Starting Permissions

**Required** (`pl-prod-iam-015-to-admin-starting-user`):
- `iam:AttachUserPolicy` on `arn:aws:iam::*:user/pl-prod-iam-015-to-admin-target-user` -- allows attaching managed policies to the target user
- `iam:CreateAccessKey` on `arn:aws:iam::*:user/pl-prod-iam-015-to-admin-target-user` -- allows generating new credentials for the target user

**Helpful** (`pl-prod-iam-015-to-admin-starting-user`):
- `iam:ListUsers` -- discover target users to escalate through
- `iam:GetUser` -- get target user details and current permissions
- `iam:ListAttachedUserPolicies` -- list managed policies attached to target user
- `iam:ListPolicies` -- discover available AWS-managed policies to attach
- `iam:ListAccessKeys` -- list existing access keys for target user

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_admin_iam_015_iam_attachuserpolicy_iam_createaccesskey
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
| `arn:aws:iam::{account_id}:user/pl-prod-iam-015-to-admin-starting-user` | Scenario-specific starting user with access keys and permissions to attach policies and create keys for target user |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-015-to-admin-target-user` | Target user that will be granted admin access via policy attachment |
| `arn:aws:iam::{account_id}:policy/pl-prod-iam-015-to-admin-starting-user-policy` | IAM policy granting AttachUserPolicy and CreateAccessKey on target user |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve scenario credentials from Terraform outputs
2. Verify the starting user lacks administrative access
3. Attach the AWS-managed `AdministratorAccess` policy to `pl-prod-iam-015-to-admin-target-user`
4. Create new access keys for the target user
5. Authenticate as the target user using the new credentials
6. Verify successful privilege escalation by listing IAM users

#### Resources Created by Attack Script

- New access keys created for `pl-prod-iam-015-to-admin-target-user`
- `AdministratorAccess` managed policy attached to `pl-prod-iam-015-to-admin-target-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-015-iam-attachuserpolicy+iam-createaccesskey
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-015-iam-attachuserpolicy+iam-createaccesskey
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_iam_015_iam_attachuserpolicy_iam_createaccesskey
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

- IAM user with `iam:AttachUserPolicy` permission scoped to other IAM users — this permission allows modification of other users' access
- IAM user with `iam:CreateAccessKey` permission scoped to other IAM users — this permission allows credential creation for other users
- Combination of policy attachment and credential creation on the same target user — the toxic combination of these permissions enables complete lateral movement
- Privilege escalation path from user to user — graph-based analysis should identify this as a privilege escalation vector
- Overly permissive cross-user IAM permissions — users should not have administrative control over other users' permissions and credentials

#### Prevention Recommendations

1. **Restrict AttachUserPolicy Permission**: Limit `iam:AttachUserPolicy` to dedicated security/IAM administration teams. Regular users should never have this permission on other users.

2. **Restrict CreateAccessKey Permission**: Prevent users from creating access keys for other users. Use policy conditions to ensure users can only create keys for themselves:
   ```json
   {
     "Effect": "Allow",
     "Action": "iam:CreateAccessKey",
     "Resource": "arn:aws:iam::*:user/${aws:username}"
   }
   ```

3. **Implement Service Control Policies (SCPs)**: Use SCPs to prevent cross-user IAM modifications at the organizational level:
   ```json
   {
     "Effect": "Deny",
     "Action": [
       "iam:AttachUserPolicy",
       "iam:PutUserPolicy",
       "iam:CreateAccessKey"
     ],
     "Resource": "arn:aws:iam::*:user/*",
     "Condition": {
       "StringNotEquals": {
         "aws:PrincipalArn": "arn:aws:iam::*:role/SecurityAdminRole"
       }
     }
   }
   ```

4. **Require MFA for Sensitive IAM Operations**: Add conditions requiring MFA for policy attachment and credential creation:
   ```json
   {
     "Effect": "Deny",
     "Action": [
       "iam:AttachUserPolicy",
       "iam:CreateAccessKey"
     ],
     "Resource": "*",
     "Condition": {
       "BoolIfExists": {
         "aws:MultiFactorAuthPresent": "false"
       }
     }
   }
   ```

5. **Use IAM Access Analyzer**: Enable IAM Access Analyzer to identify users with permissions that allow them to modify other IAM principals. Review findings regularly and remediate overly permissive configurations.

6. **Implement Real-Time Alerting**: Configure CloudWatch Alarms or AWS Security Hub to alert when `AttachUserPolicy` is called with AdministratorAccess or other high-privilege policies, when `CreateAccessKey` is called where the username differs from the caller, and when multiple sensitive IAM actions occur in rapid succession.

7. **Principle of Least Privilege**: Grant users only the permissions they need for their job function. Users should manage only their own credentials, not other users' credentials.

8. **Separate Administrative Duties**: Implement role separation where policy management and credential management are handled by different teams/roles, preventing any single principal from executing the complete attack path.

9. **Regular Permission Audits**: Conduct regular audits of IAM permissions to identify users with cross-user administrative capabilities. Use tools like Prowler, ScoutSuite, or CloudSploit to automate these audits.

10. **Monitor Managed Policy Attachments**: While inline policies often receive more scrutiny, managed policy attachments can be equally dangerous. Ensure monitoring covers both policy types, with special attention to AWS-managed policies containing "Administrator" or "FullAccess" in their names.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: AttachUserPolicy` -- especially when attaching high-privilege policies like AdministratorAccess; critical when the target user differs from the caller
- `IAM: CreateAccessKey` -- particularly when the caller is not the user for whom keys are being created; indicates potential lateral movement

Alert on these patterns:
- User A calling `IAM: AttachUserPolicy` for User B followed by `IAM: CreateAccessKey` for User B within a short time window
- `IAM: AttachUserPolicy` events targeting AWS-managed policies with "Admin" or "FullAccess" in their name
- `IAM: CreateAccessKey` where `userName` parameter differs from the authenticated principal

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
