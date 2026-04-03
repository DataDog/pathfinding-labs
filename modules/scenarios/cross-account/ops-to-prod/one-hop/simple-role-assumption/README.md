# Cross-Account from Operations to Prod Simple Role Assumption

* **Category:** Privilege Escalation
* **Sub-Category:** cross-account-escalation
* **Path Type:** cross-account
* **Target:** to-admin
* **Environments:** operations, prod
* **Cost Estimate:** $0/mo
* **Technique:** Cross-account role assumption from operations to prod
* **Terraform Variable:** `enable_cross_account_ops_to_prod_one_hop_simple_role_assumption`
* **Schema Version:** 4.0.0
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0008 - Lateral Movement
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-pathfinding-starting-user-operations` IAM user in the operations account to the `pl-x-account-prod-target-role` administrative role in the production account by assuming the operations role (which has `sts:AssumeRole` on `*`) and then using it to perform cross-account role assumption into any prod role that trusts the operations account.

- **Start:** `arn:aws:iam::{operations_account_id}:user/pl-pathfinding-starting-user-operations`
- **Destination resource:** `arn:aws:iam::{prod_account_id}:role/pl-x-account-prod-target-role`

### Starting Permissions

**Required** (`pl-pathfinding-starting-user-operations`):
- `sts:AssumeRole` on `*` -- allows the starting user to assume `pl-x-account-ops-role-with-assume-role-star`, which itself carries an unrestricted `sts:AssumeRole` on `*` enabling cross-account role assumption into any prod role that trusts the operations account

**Helpful** (`pl-pathfinding-starting-user-operations`):
- `iam:ListRoles` -- discover roles in the prod account to identify assumable targets
- `iam:GetRole` -- view role trust policies and permissions to select the most privileged target

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_cross_account_ops_to_prod_one_hop_simple_role_assumption
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
|-----|---------|
| `arn:aws:iam::{operations_account_id}:user/pl-pathfinding-starting-user-operations` | Starting user in the operations account |
| `arn:aws:iam::{operations_account_id}:role/pl-x-account-ops-role-with-assume-role-star` | Operations role with unrestricted sts:AssumeRole |
| `arn:aws:iam::{prod_account_id}:role/pl-x-account-prod-target-role` | Target prod role that trusts the operations account |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:

1. Read starting credentials from Terraform outputs
2. Assume the operations role in the operations account
3. Enumerate roles in the prod account
4. Assume multiple privileged prod roles using the operations role credentials
5. Verify elevated access in the prod account

#### Resources Created by Attack Script

- Temporary STS session credentials for the operations role
- Temporary STS session credentials for the prod target role

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo simple-role-assumption
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup simple-role-assumption
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_cross_account_ops_to_prod_one_hop_simple_role_assumption
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

- IAM role in the operations account has `sts:AssumeRole` on `*` — this is an overly permissive cross-account permission that enables lateral movement to any role in any account
- Prod IAM role trust policy allows assumption from the operations account without condition keys (e.g., no `aws:PrincipalArn` condition narrowing which operations principals may assume it)
- No MFA or external ID condition on cross-account role assumption in the trust policy of the prod target role
- The combination of an unconstrained ops-to-prod trust relationship and admin-level permissions on the prod role creates a direct privilege escalation path from the operations account

#### Prevention Recommendations

- Scope `sts:AssumeRole` in the operations role policy to specific prod role ARNs rather than `*`
- Add `aws:PrincipalArn` or `aws:PrincipalAccount` conditions to prod role trust policies to restrict which principals may assume them
- Require an `sts:ExternalId` condition on all cross-account trust relationships to prevent confused deputy attacks
- Implement an SCP in AWS Organizations that denies `sts:AssumeRole` across account boundaries unless the request comes from an approved operations role ARN
- Enforce MFA conditions (`aws:MultiFactorAuthPresent: true`) on cross-account role trust policies for any role with elevated privileges
- Use AWS IAM Access Analyzer to continuously monitor cross-account trust relationships and alert on overly permissive configurations

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `STS: AssumeRole` -- Cross-account role assumption; alert when a principal in the operations account assumes a role in the prod account, especially admin-level roles
- `IAM: ListRoles` -- Enumeration of roles in the prod account; expected from legitimate ops tooling but suspicious if not from a known automation principal

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
