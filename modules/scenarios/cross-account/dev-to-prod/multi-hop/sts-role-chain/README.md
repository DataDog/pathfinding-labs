# Dev to Prod Cross-Account Role Chain to Admin

* **Category:** Privilege Escalation
* **Path Type:** cross-account
* **Target:** to-admin
* **Environments:** dev, prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Non-admin dev user chains through dev and prod roles via sts:AssumeRole to reach prod administrative access
* **Terraform Variable:** `enable_cross_account_dev_to_prod_sts_role_chain_to_admin`
* **Schema Version:** 4.7.1
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0008 - Lateral Movement
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-dev-sts-role-chain-starting-user` IAM user in the dev account to the `pl-prod-sts-role-chain-prod-admin-role` administrative role in the prod account by chaining three `sts:AssumeRole` calls — including a cross-account hop — using only trust relationships that already exist between the roles.

- **Start:** `arn:aws:iam::{dev_account_id}:user/pl-dev-sts-role-chain-starting-user`
- **Destination resource:** `arn:aws:ssm:{region}:{prod_account_id}:parameter/pathfinding-labs/flags/sts-role-chain-to-admin`

### Starting Permissions

**Required** (`pl-dev-sts-role-chain-starting-user`):
- `sts:AssumeRole` on `arn:aws:iam::{dev_account_id}:role/pl-dev-sts-role-chain-dev-role` -- allows the starting user to assume the dev role as the first hop

**Required** (`pl-dev-sts-role-chain-dev-role`):
- `sts:AssumeRole` on `arn:aws:iam::{prod_account_id}:role/pl-prod-sts-role-chain-prod-non-admin-role` -- allows the dev role to assume the prod non-admin role cross-account as the second hop

**Required** (`pl-prod-sts-role-chain-prod-non-admin-role`):
- `sts:AssumeRole` on `arn:aws:iam::{prod_account_id}:role/pl-prod-sts-role-chain-prod-admin-role` -- allows the prod non-admin role to assume the prod admin role as the third hop

**Helpful** (`pl-dev-sts-role-chain-starting-user`):
- `iam:ListRoles` -- Discover roles available to assume in dev account

**Helpful** (`pl-dev-sts-role-chain-dev-role`):
- `sts:GetCallerIdentity` -- Verify identity after assuming dev role
- `iam:ListRoles` -- Discover cross-account roles available to assume

**Helpful** (`pl-prod-sts-role-chain-prod-non-admin-role`):
- `sts:GetCallerIdentity` -- Verify identity after assuming prod non-admin role
- `iam:ListRoles` -- Discover admin roles available in prod account

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable sts-role-chain-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `sts-role-chain-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
|-----|---------|
| `arn:aws:iam::{dev_account_id}:user/pl-dev-sts-role-chain-starting-user` | Starting IAM user in the dev account; non-admin with permission to assume the dev role |
| `arn:aws:iam::{dev_account_id}:role/pl-dev-sts-role-chain-dev-role` | Dev account role; trusted by the starting user; holds cross-account assume-role permission to the prod non-admin role |
| `arn:aws:iam::{prod_account_id}:role/pl-prod-sts-role-chain-prod-non-admin-role` | Prod account non-admin role; trusted cross-account by the dev role; holds assume-role permission to the prod admin role |
| `arn:aws:iam::{prod_account_id}:role/pl-prod-sts-role-chain-prod-admin-role` | Prod account admin role with AdministratorAccess; trusted by the prod non-admin role |
| `arn:aws:ssm:{region}:{prod_account_id}:parameter/pathfinding-labs/flags/sts-role-chain-to-admin` | CTF flag stored in SSM Parameter Store; readable with prod admin permissions |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:

1. **Verification**: Check the current identity and permissions of the starting dev user
2. **Hop 1 — Dev Role**: Assume `pl-dev-sts-role-chain-dev-role` within the dev account using `sts:AssumeRole`
3. **Verification**: Confirm the new identity as the dev role
4. **Hop 2 — Cross-Account**: Assume `pl-prod-sts-role-chain-prod-non-admin-role` in the prod account cross-account
5. **Verification**: Confirm the new identity as the prod non-admin role
6. **Hop 3 — Prod Admin**: Assume `pl-prod-sts-role-chain-prod-admin-role` within the prod account
7. **Admin Verification**: Confirm full administrative access in prod using `iam:ListUsers`
8. **Flag Capture**: Retrieve the CTF flag from SSM Parameter Store using the prod admin credentials

#### Resources Created by Attack Script

- No persistent AWS resources are created; the attack uses only temporary STS session credentials

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo sts-role-chain
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup sts-role-chain
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable sts-role-chain-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `sts-role-chain-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM role `pl-dev-sts-role-chain-dev-role` in the dev account holds `sts:AssumeRole` on a prod account role, creating a cross-account privilege escalation path accessible to any dev account principal that can assume this role
- Cross-account trust relationship allows `pl-dev-sts-role-chain-dev-role` (dev account) to assume `pl-prod-sts-role-chain-prod-non-admin-role` (prod account) — no individual role appears privileged, but the chain reaches admin
- IAM role `pl-prod-sts-role-chain-prod-non-admin-role` in the prod account holds `sts:AssumeRole` on a role with `AdministratorAccess`; a non-admin prod role that can escalate to admin via a single hop is a privilege escalation vector
- Three-hop role assumption chain (dev user → dev role → prod non-admin role → prod admin role) is detectable as a transitive privilege escalation path via graph-based IAM analysis; each hop appears harmless in isolation
- The prod admin role `pl-prod-sts-role-chain-prod-admin-role` is reachable by a dev account user despite no direct cross-account trust between the dev user and any prod admin role

#### Prevention Recommendations

1. **Principle of Least Privilege**: Audit all `sts:AssumeRole` grants; restrict the resource ARN in assume-role policies to only the specific roles needed for documented use cases
2. **Cross-Account Restrictions**: Add `aws:PrincipalOrgID` or explicit account conditions in prod role trust policies so dev account principals cannot assume prod roles without an additional control
3. **Deny Cross-Account Admin Escalation via SCP**: Create an SCP in AWS Organizations that prevents dev account roles from assuming prod roles that carry admin-equivalent policies
4. **Multi-Hop Chain Detection**: Use IAM Access Analyzer to run transitive reachability analysis and surface dev principals that can reach prod admin roles through any chain of trust relationships
5. **Tag-Based Guardrails**: Enforce `iam:ResourceTag/environment` conditions on assume-role operations so only principals tagged for prod can assume prod roles
6. **Regular Trust Policy Reviews**: Establish a quarterly review process for all cross-account trust policies; flag any trust relationship that originates in a non-prod account and terminates on a principal with elevated permissions

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `sts:AssumeRole` -- role assumption from the starting dev user into `pl-dev-sts-role-chain-dev-role`; alert when an IAM user with no prod-account relationships initiates a role chain
- `sts:AssumeRole` -- cross-account role assumption from `pl-dev-sts-role-chain-dev-role` (dev) into `pl-prod-sts-role-chain-prod-non-admin-role` (prod); high severity when the source account is a non-prod account and the destination role resides in a production account
- `sts:AssumeRole` -- same-account role assumption from `pl-prod-sts-role-chain-prod-non-admin-role` into `pl-prod-sts-role-chain-prod-admin-role`; alert when a session that originated outside prod assumes an admin-equivalent role within minutes of a cross-account hop
- `ssm:GetParameter` -- retrieval of a parameter under `/pathfinding-labs/flags/`; alert when the caller's session ancestry traces back to a dev account principal

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [MITRE ATT&CK T1078.004 - Valid Accounts: Cloud Accounts](https://attack.mitre.org/techniques/T1078/004/) -- technique used to traverse trust relationships across account boundaries
- [AWS IAM AssumeRole documentation](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html) -- reference for the STS assume-role API and trust policy evaluation
- [IAM Access Analyzer cross-account findings](https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-cross-account.html) -- using Access Analyzer to surface transitive cross-account paths
