# Dev to Prod via Direct Role Assumption to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** principal-access
* **Path Type:** cross-account
* **Target:** to-admin
* **Environments:** dev, prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Direct cross-account role assumption from dev user to prod admin role
* **Terraform Variable:** `enable_cross_account_dev_to_prod_one_hop_simple_role_assumption`
* **Schema Version:** 4.6.0
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0008 - Lateral Movement
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-dev-xsare-to-admin-starting-user` IAM user in the dev account to the `pl-prod-xsare-to-admin-target-role` administrative role in the prod account by directly assuming the prod role using `sts:AssumeRole`, crossing the account boundary between a lower-trust development environment and the production environment.

- **Start:** `arn:aws:iam::{dev_account_id}:user/pl-dev-xsare-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{prod_account_id}:role/pl-prod-xsare-to-admin-target-role`

### Starting Permissions

**Required** (`pl-dev-xsare-to-admin-starting-user`):
- `sts:AssumeRole` on `arn:aws:iam::{prod_account_id}:role/pl-prod-xsare-to-admin-target-role` -- allows direct cross-account role assumption to gain administrative access in prod

**Helpful** (`pl-dev-xsare-to-admin-starting-user`):
- `sts:GetCallerIdentity` -- verify current identity before and after role assumption
- `iam:ListRoles` -- discover assumable roles in the target account

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable dev-to-prod-simple-role-assumption-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `dev-to-prod-simple-role-assumption-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{dev_account_id}:user/pl-dev-xsare-to-admin-starting-user` | Dev account starting user with cross-account AssumeRole permission |
| `arn:aws:iam::{prod_account_id}:role/pl-prod-xsare-to-admin-target-role` | Prod account role with AdministratorAccess that trusts the dev user |
| `arn:aws:ssm:{prod_region}:{prod_account_id}:parameter/pathfinding-labs/flags/dev-to-prod-simple-role-assumption-to-admin` | CTF flag stored in prod SSM Parameter Store; readable only with prod admin access |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve scenario credentials and configuration from Terraform outputs
2. Verify starting user identity in the dev account
3. Confirm the starting user does not already have admin access in prod
4. Assume the target role in the prod account using `sts:AssumeRole`
5. Verify successful cross-account privilege escalation by listing IAM users in prod

#### Resources Created by Attack Script

- Temporary STS session credentials for `pl-prod-xsare-to-admin-target-role` (expire automatically; no persistent artifacts created)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo simple-role-assumption
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `dev-to-prod-simple-role-assumption-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

This scenario does not create persistent attack artifacts beyond the infrastructure deployed by Terraform. Role assumption is temporary and sessions expire automatically. No cleanup script is needed for this pure role assumption scenario.

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup simple-role-assumption
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `dev-to-prod-simple-role-assumption-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable dev-to-prod-simple-role-assumption-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `dev-to-prod-simple-role-assumption-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- **Cross-Account Trust Violations**: Prod roles that trust principals from lower-trust environments (dev, test, sandbox)
- **Overly Permissive Trust Policies**: Trust policies that trust specific users instead of requiring role chaining
- **Direct Admin Access from Non-Prod**: Cross-account paths that grant administrative access from non-production accounts
- **Missing MFA Requirements**: Trust policies for administrative roles that don't require MFA
- **Lack of External ID**: Cross-account trusts without external ID requirements (where applicable)
- **Privilege Escalation Paths**: Automated detection of dev → prod admin paths in IAM Access Analyzer

#### Prevention Recommendations

- **Eliminate Direct Cross-Account Trust**: Never allow production administrative roles to trust users or roles in non-production accounts directly
- **Implement Role Chaining with Break-Glass**: Require multi-hop role assumption with approval workflows for prod access from dev accounts
- **Use Service Control Policies (SCPs)**: Implement SCPs at the AWS Organizations level to restrict cross-account AssumeRole operations:
  ```json
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Deny",
        "Action": "sts:AssumeRole",
        "Resource": "arn:aws:iam::{PROD_ACCOUNT}:role/admin-*",
        "Condition": {
          "StringNotEquals": {
            "aws:PrincipalAccount": "{PROD_ACCOUNT}"
          }
        }
      }
    ]
  }
  ```
- **Require MFA for Cross-Account Admin Access**: Add MFA conditions to trust policies for administrative roles:
  ```json
  {
    "Condition": {
      "Bool": {
        "aws:MultiFactorAuthPresent": "true"
      }
    }
  }
  ```
- **Use External IDs**: For service-to-service cross-account access, require external IDs to prevent confused deputy attacks
- **Implement Separate AWS Organizations**: Keep production and non-production accounts in separate AWS Organizations with no trust relationships
- **Monitor CloudTrail for Cross-Account AssumeRole**: Alert on `AssumeRole` API calls where the source account differs from the target account, especially for administrative roles
- **Use IAM Access Analyzer**: Enable IAM Access Analyzer to continuously scan for external access to resources and highlight cross-account trust relationships
- **Principle of Least Privilege**: If cross-account access is required, grant only the minimum necessary permissions, not administrative access
- **Time-Based Restrictions**: Add time-of-day restrictions to trust policies to limit when cross-account access is permitted
- **IP Address Restrictions**: Require cross-account assumptions to originate from known IP ranges or VPNs

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `STS: AssumeRole` -- Cross-account role assumption; critical when the source account differs from the target account and the target role has administrative permissions

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
