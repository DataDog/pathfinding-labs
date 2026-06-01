# PassRole + Cognito Identity Pool: Unauthenticated Role Swap

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Principal with iam:PassRole and cognito-identity:SetIdentityPoolRoles can bind an admin role to an existing pool's unauthenticated slot, turning it into a public STS credential-vending endpoint
* **Pathfinding.cloud ID:** cognito-identity-001
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_cognito_identity_001_iam_passrole_cognito_identity_setidentitypoolroles`
* **Schema Version:** 4.7.1
* **MITRE Tactics:** TA0004 - Privilege Escalation
* **MITRE Techniques:** T1098 - Account Manipulation, T1078.004 - Cloud Accounts
* **CTF Flag Location:** ssm-parameter
* **Required Preconditions:**
  - Cognito Identity Pool: with AllowUnauthenticatedIdentities=true and AllowClassicFlow=true (models a mobile app's guest access tier)
  - IAM Role: with AdministratorAccess and a trust policy scoped to cognito-identity.amazonaws.com with the pool ID in the aud condition

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-cognito-identity-001-to-admin-starting-user` IAM user to the `pl-prod-cognito-identity-001-to-admin-admin-role` administrative role by binding the admin role to an existing Cognito Identity Pool's unauthenticated slot and using the pool's public credential-vending endpoints to obtain STS credentials without any AWS authentication.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-cognito-identity-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/cognito-identity-001-to-admin`

### Starting Permissions

**Required** (`pl-prod-cognito-identity-001-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-cognito-identity-001-to-admin-admin-role` -- pass the admin role to the Cognito identity pool's unauthenticated slot
- `cognito-identity:SetIdentityPoolRoles` on `*` -- bind an IAM role to a pool's unauthenticated identity slot

**Helpful** (`pl-prod-cognito-identity-001-to-admin-starting-user`):
- `cognito-identity:ListIdentityPools` -- Discover existing Cognito identity pools in the account
- `cognito-identity:DescribeIdentityPool` -- View pool configuration including unauthenticated access settings and classic flow
- `cognito-identity:GetIdentityPoolRoles` -- Check whether a privileged role is already bound to the pool's unauthenticated slot
- `iam:ListRoles` -- Discover available IAM roles to pass to the pool
- `iam:GetRole` -- Inspect role trust policies to find roles trusting cognito-identity.amazonaws.com

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable cognito-identity-001-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `cognito-identity-001-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
|-----|---------|
| `arn:aws:iam::{account_id}:user/pl-prod-cognito-identity-001-to-admin-starting-user` | Starting IAM user with iam:PassRole and cognito-identity:SetIdentityPoolRoles |
| `arn:aws:cognito-identity:{region}:{account_id}:identitypool/{pool_id}` | Cognito Identity Pool with unauthenticated access and classic flow enabled |
| `arn:aws:iam::{account_id}:role/pl-prod-cognito-identity-001-to-admin-admin-role` | Admin role with AdministratorAccess, trust policy scoped to the pool |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/cognito-identity-001-to-admin` | CTF flag parameter (SecureString, readable only by admin-equivalent principals) |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:

1. Confirm identity of the starting principal and wait 15 seconds for IAM policy propagation
2. Verify the starting principal cannot read the SSM flag directly (proves escalation is required)
3. Call `cognito-identity:SetIdentityPoolRoles` as the starting user to bind the admin role to the pool's unauthenticated slot (uses `iam:PassRole` implicitly)
4. Call `cognito-identity:GetId` with `--no-sign-request` to obtain a Cognito identity ID — no AWS credentials required
5. Call `cognito-identity:GetOpenIdToken` with `--no-sign-request` to obtain an OIDC token via the classic flow — no AWS credentials required
6. Call `sts:AssumeRoleWithWebIdentity` with `--no-sign-request` using the OIDC token to receive full STS credentials for the admin role (classic flow, no session policy restriction)
7. Use the escalated admin credentials to read the CTF flag from SSM Parameter Store, confirming privilege escalation

#### Resources Created by Attack Script

- No persistent AWS resources are created by the attack script
- The `SetIdentityPoolRoles` call modifies the existing pool's role binding in-place; `cleanup_attack.sh` clears the binding

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo cognito-identity-001-iam-passrole+cognito-identity-setidentitypoolroles
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup cognito-identity-001-iam-passrole+cognito-identity-setidentitypoolroles
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable cognito-identity-001-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `cognito-identity-001-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user `pl-prod-cognito-identity-001-to-admin-starting-user` has `iam:PassRole` permission on an admin-equivalent role (`pl-prod-cognito-identity-001-to-admin-admin-role` with `AdministratorAccess`) combined with `cognito-identity:SetIdentityPoolRoles` — a complete privilege escalation path
- Cognito Identity Pool `pl-prod-cognito-identity-001-to-admin-pool` has `AllowUnauthenticatedIdentities=true` and `AllowClassicFlow=true` — the classic flow bypasses the Cognito-managed session policy that would otherwise restrict the role's permissions
- IAM role `pl-prod-cognito-identity-001-to-admin-admin-role` has `AdministratorAccess` and a trust policy scoped to `cognito-identity.amazonaws.com` — any principal with `SetIdentityPoolRoles` on the associated pool can obtain full admin credentials via unauthenticated public API calls
- The combination of a pool-trusted admin role and `AllowClassicFlow=true` means `sts:AssumeRoleWithWebIdentity` calls against this role will not have a Cognito session policy applied, granting unrestricted `AdministratorAccess`

#### Prevention Recommendations

- Apply least-privilege to `iam:PassRole`: restrict the `Resource` to specific non-privileged roles, or add a condition requiring the role be passed to non-Cognito services only (e.g., `iam:PassedToService` condition key)
- Enforce an SCP or permission boundary that prevents any principal from calling `cognito-identity:SetIdentityPoolRoles` unless they belong to an approved identity management group or automation role
- Attach permission boundaries to all IAM roles whose trust policies reference `cognito-identity.amazonaws.com`; a boundary capping permissions at a scoped read-only policy prevents admin credential issuance even if the role is bound to the unauthenticated slot
- Disable `AllowClassicFlow` on all Cognito Identity Pools unless the application explicitly requires it; enhanced flow (`GetCredentialsForIdentity`) enforces a Cognito-managed session policy that blocks SSM and most IAM actions
- Set `AllowUnauthenticatedIdentities=false` on any pool whose application does not need genuine guest access; if guest access is required, bind only a least-privilege role (never `AdministratorAccess`) to the unauthenticated slot
- Audit Cognito Identity Pool role bindings periodically using `cognito-identity:GetIdentityPoolRoles` and alert when admin-equivalent roles (`AdministratorAccess`, `PowerUserAccess`, or policies with `iam:*`) appear in any pool's role map

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `cognito-identity:SetIdentityPoolRoles` -- a role was bound to an identity pool; critical when the bound role ARN carries `AdministratorAccess` or other elevated permissions; logged in the calling principal's account
- `sts:AssumeRoleWithWebIdentity` -- STS credentials were vended via a web identity token; alert when the `issuer` in `requestParameters` is `cognito-identity.amazonaws.com` and the assumed role ARN is admin-equivalent; also alert on high-frequency calls from a single identity or IP indicating automated abuse
- `ssm:GetParameter` -- SSM parameter read after `sts:AssumeRoleWithWebIdentity` from a Cognito-issued identity is a strong indicator of post-escalation flag or secret access

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [https://pathfinding.cloud/paths/cognito-identity-001](https://pathfinding.cloud/paths/cognito-identity-001) -- Pathfinding.cloud path entry for this technique
- [https://attack.mitre.org/techniques/T1098/](https://attack.mitre.org/techniques/T1098/) -- MITRE ATT&CK T1098: Account Manipulation
- [https://attack.mitre.org/techniques/T1078/004/](https://attack.mitre.org/techniques/T1078/004/) -- MITRE ATT&CK T1078.004: Valid Accounts: Cloud Accounts
- [https://docs.aws.amazon.com/cognito/latest/developerguide/authentication-flow.html](https://docs.aws.amazon.com/cognito/latest/developerguide/authentication-flow.html) -- AWS documentation on Cognito enhanced vs. classic authentication flows
