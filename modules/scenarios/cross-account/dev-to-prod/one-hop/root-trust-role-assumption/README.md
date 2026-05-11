# Dev to Prod via Root Trust Assumption to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** principal-access
* **Path Type:** cross-account
* **Target:** to-admin
* **Environments:** dev, prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Cross-account role assumption exploiting overly permissive :root trust policy
* **Terraform Variable:** `enable_cross_account_dev_to_prod_one_hop_root_trust_role_assumption`
* **Schema Version:** 4.6.0
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0008 - Lateral Movement
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-dev-xsarrt-to-admin-starting-user` IAM user in the dev account to the `pl-prod-xsarrt-to-admin-target-role` administrative role in the prod account by assuming the role via a trust policy that grants access to the entire dev account via the `:root` principal.

- **Start:** `arn:aws:iam::{dev_account_id}:user/pl-dev-xsarrt-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{prod_account_id}:role/pl-prod-xsarrt-to-admin-target-role`

### Starting Permissions

**Required** (`pl-dev-xsarrt-to-admin-starting-user`):
- `sts:AssumeRole` on `arn:aws:iam::{prod_account_id}:role/pl-prod-xsarrt-to-admin-target-role` -- allows the dev user to assume the prod admin role

**Helpful** (`pl-dev-xsarrt-to-admin-starting-user`):
- `sts:GetCallerIdentity` -- verify current identity before and after role assumption
- `iam:ListRoles` -- discover assumable roles in the target account

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew tap DataDog/pathfinding-labs https://github.com/DataDog/pathfinding-labs
   brew install DataDog/pathfinding-labs/plabs
   ```
   Or with Go 1.25+ installed:
   ```bash
   go install github.com/DataDog/pathfinding-labs/cmd/plabs@latest
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable root-trust-role-assumption-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `root-trust-role-assumption-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{dev_account_id}:user/pl-dev-xsarrt-to-admin-starting-user` | Dev account starting user with cross-account AssumeRole permission |
| `arn:aws:iam::{prod_account_id}:role/pl-prod-xsarrt-to-admin-target-role` | Prod account admin role with DANGEROUS :root trust policy |
| `arn:aws:ssm:{region}:{prod_account_id}:parameter/pathfinding-labs/flags/root-trust-role-assumption-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal in prod |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Demonstrate how the :root trust allows the assumption
4. Verify successful cross-account privilege escalation to admin
5. Capture the CTF flag from SSM Parameter Store using the assumed admin role credentials


#### Resources Created by Attack Script

- No persistent resources are created; `sts:AssumeRole` sessions are temporary and expire automatically

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo root-trust-role-assumption
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `root-trust-role-assumption-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup root-trust-role-assumption
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `root-trust-role-assumption-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable root-trust-role-assumption-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `root-trust-role-assumption-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

A properly configured Cloud Security Posture Management (CSPM) tool should detect:

- **:root Trust Policies**: ANY role that trusts another account's :root principal (CRITICAL SEVERITY)
- **Cross-Account Trust Violations**: Prod roles that trust principals from lower-trust environments (dev, test, sandbox)
- **Overly Permissive Trust Policies**: Trust policies using :root instead of explicit principal ARNs
- **Direct Admin Access from Non-Prod**: Cross-account paths that grant administrative access from non-production accounts
- **Missing MFA Requirements**: Trust policies for administrative roles that don't require MFA
- **Lack of External ID**: Cross-account trusts without external ID requirements (where applicable)
- **Privilege Escalation Paths**: Automated detection of dev → prod admin paths in IAM Access Analyzer
- **Trust Policy Comparison**: Flag :root trusts as significantly higher risk than explicit principal trusts

**Key Detection Indicators:**

1. **Trust Policy Pattern**: `"Principal": {"AWS": "arn:aws:iam::*:root"}`
2. **Cross-Account Boundary**: Dev account ID ≠ Prod account ID
3. **Permission Level**: Role has administrative or sensitive permissions
4. **Missing Conditions**: No MFA, external ID, or IP restrictions

#### Prevention Recommendations

- **NEVER Use :root in Trust Policies**: Always specify explicit principal ARNs (users or roles) in trust policies, never use :root
- **Principle of Explicit Trust**: Trust specific principals by full ARN, not entire accounts
  ```json
  {
    "Principal": {
      "AWS": "arn:aws:iam::{DEV_ACCOUNT}:role/specific-approved-role"
    }
  }
  ```
- **Audit All :root Trusts**: Use AWS Config or custom scripts to identify and remediate ALL trust policies containing :root principals
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
- **Role Chaining Instead of Direct Trust**: Require multi-hop role assumption with approval workflows for prod access from dev accounts
- **Use IAM Access Analyzer**: Enable IAM Access Analyzer to continuously scan for external access to resources and highlight cross-account trust relationships, especially :root trusts
- **Principle of Least Privilege**: If cross-account access is required, grant only the minimum necessary permissions, not administrative access
- **Time-Based Restrictions**: Add time-of-day restrictions to trust policies to limit when cross-account access is permitted
- **IP Address Restrictions**: Require cross-account assumptions to originate from known IP ranges or VPNs:
  ```json
  {
    "Condition": {
      "IpAddress": {
        "aws:SourceIp": ["10.0.0.0/8", "192.168.0.0/16"]
      }
    }
  }
  ```
- **Regular Trust Policy Audits**: Quarterly reviews of all cross-account trust policies to ensure they follow least-privilege and explicit-trust principles
- **Automated Remediation**: Implement automated remediation to replace :root trusts with explicit principal trusts when detected
- **Security Hub Integration**: Enable AWS Security Hub to receive findings about overly permissive trust policies
- **Break-Glass Process**: For legitimate cross-account access needs, implement break-glass emergency access with approval workflows instead of standing :root trusts

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `sts:AssumeRole` -- Cross-account role assumption; alert when source account ID differs from the target account ID, especially when the assumed role has administrative permissions

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
