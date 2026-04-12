# IAM Console Password Creation to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** credential-access
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Creating console password for admin user to gain console access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_iam_004_iam_createloginprofile`
* **Schema Version:** 4.1.1
* **Pathfinding.cloud ID:** iam-004
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-004-to-admin-starting-user` IAM user to the `pl-prod-iam-004-to-admin-target-user` administrative user by assuming `pl-prod-iam-004-to-admin-starting-role` and using `iam:CreateLoginProfile` to create a console password for the admin user, granting interactive AWS Management Console access with full administrator privileges.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-004-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:user/pl-prod-iam-004-to-admin-target-user`

### Starting Permissions

**Required** (`pl-prod-iam-004-to-admin-starting-user`):
- `iam:CreateLoginProfile` on `arn:aws:iam::*:user/pl-prod-iam-004-to-admin-target-user` -- creates a console password for the target admin user, enabling console login

**Helpful** (`pl-prod-iam-004-to-admin-starting-user`):
- `iam:ListUsers` -- discover users without login profiles
- `iam:GetUser` -- view user details
- `iam:GetLoginProfile` -- check if a user already has a login profile

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable iam-004-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-004-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-004-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-iam-004-to-admin-starting-role` | Vulnerable role with CreateLoginProfile permission on admin user |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-004-to-admin-target-user` | Target admin user with AdministratorAccess policy but no initial login profile |

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

- Login profile (console password) on `pl-prod-iam-004-to-admin-target-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-004-iam-createloginprofile
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-004-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-004-iam-createloginprofile
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-004-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable iam-004-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-004-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM role has `iam:CreateLoginProfile` permission on a privileged user (privilege escalation path via console credential creation)
- Admin user (`pl-prod-iam-004-to-admin-target-user`) has `AdministratorAccess` and no login profile — making it a silent target for console access creation
- Role can manipulate credentials of a higher-privileged principal without restriction

#### Prevention Recommendations

- Avoid granting `iam:CreateLoginProfile` permissions on privileged users - use resource-based conditions to restrict which users can have login profiles created
- Implement Service Control Policies (SCPs) to prevent login profile creation on admin users across the organization
- Monitor CloudTrail for `CreateLoginProfile` API calls, especially on privileged accounts, and alert on suspicious activity
- Enforce MFA requirements for console access using IAM policies with `aws:MultiFactorAuthPresent` conditions
- Use IAM Access Analyzer to identify and remediate privilege escalation paths involving credential manipulation
- Regularly audit users with `AdministratorAccess` or other privileged policies to ensure login profiles exist only where necessary
- Implement conditional policies that require console access to originate from trusted IP ranges or networks
- Configure AWS Organizations to centrally manage console access policies and prevent unauthorized credential creation

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: CreateLoginProfile` — Console password created for an IAM user; critical when the target user has elevated permissions such as `AdministratorAccess`
- `STS: AssumeRole` — Role assumption by the starting user to gain the vulnerable role's permissions

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
