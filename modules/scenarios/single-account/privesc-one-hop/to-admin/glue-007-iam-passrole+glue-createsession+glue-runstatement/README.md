# Glue Interactive Session to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Pass privileged role to AWS Glue Interactive Session and run Python code to escalate privileges
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_glue_007_iam_passrole_glue_createsession_glue_runstatement`
* **Schema Version:** 4.1.1
* **Pathfinding.cloud ID:** glue-007
* **MITRE Tactics:** TA0004 - Privilege Escalation
* **MITRE Techniques:** T1098 - Account Manipulation

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-glue-007-to-admin-starting-user` IAM user to the `pl-prod-glue-007-to-admin-admin-role` administrative role by creating an AWS Glue Interactive Session with the admin role and executing Python code via `glue:RunStatement` to attach `AdministratorAccess` to the starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-glue-007-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-glue-007-to-admin-admin-role`

### Starting Permissions

**Required** (`pl-prod-glue-007-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-glue-007-to-admin-admin-role` -- allows passing the admin role to the Glue service when creating a session
- `glue:CreateSession` on `*` -- allows creating a Glue Interactive Session with an assigned IAM role
- `glue:RunStatement` on `*` -- allows executing arbitrary Python code within the Glue session using the session's assigned role permissions

**Helpful** (`pl-prod-glue-007-to-admin-starting-user`):
- `glue:GetSession` -- check session status and wait for it to reach the READY state before running statements
- `glue:GetStatement` -- check statement execution status and retrieve output after running code
- `glue:DeleteSession` -- clean up the Glue Interactive Session after the attack to remove evidence

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable glue-007-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `glue-007-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-glue-007-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-glue-007-to-admin-admin-role` | Administrative role passed to Glue Interactive Session |
| Inline policy: `pl-prod-glue-007-to-admin-starting-user-policy` | Policy granting PassRole, CreateSession, RunStatement, GetSession, GetStatement, and DeleteSession permissions |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Create a Glue Interactive Session with the admin role
4. Wait for the session to become ready
5. Execute a Python statement that attaches AdministratorAccess to the starting user
6. Verify successful privilege escalation by demonstrating admin access


#### Resources Created by Attack Script

- Glue Interactive Session with the admin role attached
- `AdministratorAccess` managed policy attached to `pl-prod-glue-007-to-admin-starting-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo glue-007-iam-passrole+glue-createsession+glue-runstatement
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `glue-007-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup glue-007-iam-passrole+glue-createsession+glue-runstatement
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `glue-007-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable glue-007-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `glue-007-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user with `iam:PassRole` permission on privileged roles
- IAM user with `glue:CreateSession` and `glue:RunStatement` permissions
- Combination of PassRole and Glue Interactive Session permissions enabling privilege escalation
- IAM role with administrative permissions that can be passed to Glue services
- Glue trust policy allowing the Glue service to assume privileged roles
- Privilege escalation path from user to admin via Glue Interactive Sessions

#### Prevention Recommendations

- **Restrict PassRole permissions**: Limit `iam:PassRole` to only the specific roles and services needed. Use resource-level restrictions:
  ```json
  {
    "Effect": "Allow",
    "Action": "iam:PassRole",
    "Resource": "arn:aws:iam::*:role/specific-glue-role",
    "Condition": {
      "StringEquals": {
        "iam:PassedToService": "glue.amazonaws.com"
      }
    }
  }
  ```

- **Implement SCPs to prevent privilege escalation**: Use Service Control Policies to deny PassRole on administrative roles:
  ```json
  {
    "Effect": "Deny",
    "Action": "iam:PassRole",
    "Resource": "arn:aws:iam::*:role/*admin*",
    "Condition": {
      "StringEquals": {
        "iam:PassedToService": "glue.amazonaws.com"
      }
    }
  }
  ```

- **Restrict glue:CreateSession and glue:RunStatement permissions**: Only grant these permissions to users who legitimately need interactive data exploration capabilities. These are powerful permissions that allow arbitrary code execution and should be tightly controlled.

- **Monitor CloudTrail for Interactive Session activity**: Alert on `CreateSession` API calls, especially when combined with PassRole on privileged roles. Monitor `RunStatement` calls for suspicious code patterns, particularly those involving boto3 IAM operations.

- **Use IAM Access Analyzer**: Enable IAM Access Analyzer to automatically detect privilege escalation paths involving PassRole and Glue services. Review findings regularly and remediate identified risks.

- **Implement least privilege for Glue roles**: When creating IAM roles for Glue services, grant only the minimum permissions required for the specific data exploration tasks. Avoid using administrative policies like `AdministratorAccess` or `PowerUserAccess` on Glue service roles. Typical Glue sessions need S3, Glue Data Catalog, and CloudWatch Logs access - not IAM permissions.

- **Require MFA for sensitive operations**: Implement MFA requirements for operations like `glue:CreateSession`, `glue:RunStatement`, and `iam:PassRole` to add an additional layer of security against compromised credentials.

- **Use VPC endpoints and network isolation**: Configure Glue Interactive Sessions to run within private VPCs without public internet access, reducing the attack surface even if a session is created with elevated privileges.

- **Implement session time limits**: Configure automatic session termination after a defined idle period to limit the window of opportunity for exploitation and reduce costs from forgotten sessions.

- **Separate Glue accounts**: Consider running production Glue workloads in dedicated AWS accounts with strict cross-account access controls, limiting the blast radius of compromised Glue permissions.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: PassRole` -- starting user passes the admin role to the Glue service; critical when the target role has elevated permissions
- `Glue: CreateSession` -- new Glue Interactive Session created; high severity when the `Role` parameter references an administrative role
- `Glue: RunStatement` -- statement executed within a Glue Interactive Session; monitor for boto3 IAM operations in the statement code
- `IAM: AttachUserPolicy` -- managed policy attached to an IAM user from a Glue session context; critical when the policy is `AdministratorAccess`
- `IAM: PutUserPolicy` -- inline policy added to an IAM user from a Glue session context
- `Glue: DeleteSession` -- session deleted after use; short-lived sessions (created, used briefly, then deleted) indicate potential abuse

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [AWS Glue Interactive Sessions Documentation](https://docs.aws.amazon.com/glue/latest/dg/interactive-sessions.html) -- official AWS docs for Glue Interactive Sessions
- [AWS Glue Interactive Sessions API](https://docs.aws.amazon.com/glue/latest/dg/aws-glue-api-interactive-sessions.html) -- API reference for CreateSession, RunStatement, and related calls
- [AWS IAM PassRole Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html) -- explains PassRole mechanics and how to restrict it
- [Rhino Security Labs - AWS IAM Privilege Escalation Methods](https://rhinosecuritylabs.com/aws/aws-privilege-escalation-methods-mitigation/) -- comprehensive overview of IAM privilege escalation techniques
