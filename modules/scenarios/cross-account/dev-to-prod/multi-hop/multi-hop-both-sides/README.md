# Dev to Prod Multi-Hop Both Accounts to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** privilege-chaining
* **Path Type:** cross-account
* **Target:** to-admin
* **Environments:** dev, prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Multi-hop privilege escalation across both dev and prod accounts using login profile manipulation
* **Terraform Variable:** `enable_cross_account_dev_to_prod_multi_hop_multi_hop_both_sides`
* **Schema Version:** 4.6.0
* **CTF Flag Location:** ssm-parameter
* **Interactive Demo:** Yes
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0006 - Credential Access, TA0008 - Lateral Movement
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1078.004 - Valid Accounts: Cloud Accounts

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-pathfinding-starting-user-dev` IAM user in the dev account to the `pl-Jeremy` administrative user in the prod account by chaining role assumptions and login profile manipulation across both the dev and prod accounts.

- **Start:** `arn:aws:iam::{dev_account_id}:user/pl-pathfinding-starting-user-dev`
- **Destination resource:** `arn:aws:iam::{prod_account_id}:user/pl-Jeremy`

### Starting Permissions

**Required** (`pl-pathfinding-starting-user-dev`):
- `sts:AssumeRole` on `arn:aws:iam::{dev_account_id}:role/pl-helpdesk` -- assume the helpdesk role in dev to begin the escalation chain

**Required** (`pl-helpdesk`):
- `iam:CreateLoginProfile` on `arn:aws:iam::{dev_account_id}:user/pl-Josh` -- create a console password for the dev admin user, enabling authentication as Josh

**Required** (`pl-trustsdev`):
- `iam:UpdateLoginProfile` on `arn:aws:iam::{prod_account_id}:user/pl-Jeremy` -- reset the prod admin user's console password to a value the attacker controls

**Helpful** (`pl-pathfinding-starting-user-dev`):
- `iam:GetLoginProfile` on `arn:aws:iam::{dev_account_id}:user/pl-Josh` -- check whether pl-Josh already has a login profile before attempting to create one
- `iam:ListUsers` -- discover users in the dev account and identify high-value targets
- `iam:GetUser` -- view user details to confirm which accounts hold elevated permissions

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable multi-hop-both-sides-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `multi-hop-both-sides-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
|-----|---------|
| `arn:aws:iam::{dev_account_id}:user/pl-pathfinding-starting-user-dev` | Starting principal in dev account |
| `arn:aws:iam::{dev_account_id}:role/pl-helpdesk` | Intermediate helpdesk role with `iam:CreateLoginProfile` permission |
| `arn:aws:iam::{dev_account_id}:user/pl-Josh` | Admin user in dev; target of login profile creation |
| `arn:aws:iam::{prod_account_id}:role/pl-trustsdev` | Prod role that trusts Josh user from dev account |
| `arn:aws:iam::{prod_account_id}:user/pl-Jeremy` | Admin user in prod; target of login profile update |
| `arn:aws:ssm:{prod_region}:{prod_account_id}:parameter/pathfinding-labs/flags/multi-hop-both-sides-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal in prod |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:

1. Verify current identity and permissions for the starting dev user
2. Assume the `pl-helpdesk` role in the dev account
3. Create a login profile for the `pl-Josh` user
4. Assume the `pl-trustsdev` role in the prod account as Josh
5. Update the login profile for the `pl-Jeremy` user in prod
6. Confirm admin access in both accounts
7. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions
8. Reset login profiles to their original state

#### Resources Created by Attack Script

- Login profile for `pl-Josh` (created during the attack; removed by cleanup)
- Updated login profile password for `pl-Jeremy` (reset by cleanup)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo multi-hop-both-sides
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `multi-hop-both-sides-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup multi-hop-both-sides
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `multi-hop-both-sides-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable multi-hop-both-sides-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `multi-hop-both-sides-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM role (`pl-helpdesk`) has `iam:CreateLoginProfile` permission scoped to a privileged user (`pl-Josh`), creating a privilege escalation path
- IAM role (`pl-trustsdev`) in prod has `iam:UpdateLoginProfile` permission scoped to a privileged user (`pl-Jeremy`), creating a privilege escalation path
- Cross-account role trust (`pl-trustsdev`) allows assumption by a principal from a non-production account (`pl-Josh` in dev), violating account isolation
- Privilege escalation path exists from dev account to prod admin via login profile manipulation
- `pl-Josh` and `pl-Jeremy` users hold full admin policies, making them high-value targets for login profile manipulation

#### Prevention Recommendations

- Apply the principle of least privilege: avoid granting `iam:CreateLoginProfile` and `iam:UpdateLoginProfile` unless absolutely necessary, and scope them to non-privileged users only
- Limit cross-account role assumptions to specific, documented use cases; use conditions like `aws:PrincipalOrgID` or explicit account conditions in trust policies
- Monitor and alert on login profile creation and updates using CloudTrail; treat any modification to a privileged user's login profile as a high-severity event
- Use more restrictive trust policies for cross-account roles, including `sts:ExternalId` conditions and MFA requirements
- Regularly audit cross-account permissions and login profile usage across all accounts in your organization
- Implement SCPs that deny `iam:CreateLoginProfile` and `iam:UpdateLoginProfile` for production account roles that do not require console access

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `STS: AssumeRole` -- Role assumption from dev to the helpdesk role; alert when the source principal is the pathfinding starting user
- `IAM: CreateLoginProfile` -- Login profile created for a user; critical when the target user holds admin or elevated permissions
- `STS: AssumeRole` -- Cross-account role assumption from dev `pl-Josh` to prod `pl-trustsdev`; alert on cross-account assumptions involving non-prod principals
- `IAM: UpdateLoginProfile` -- Login profile updated for a user; high severity when the target user holds admin permissions in prod
- `STS: GetCallerIdentity` -- Identity verification calls that follow a chain of role assumptions; useful for tracing lateral movement

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
