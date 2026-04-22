# Glue Dev Endpoint Creation to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $634/mo
* **Technique:** Pass privileged role to AWS Glue dev endpoint for SSH-based command execution
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_glue_001_iam_passrole_glue_createdevendpoint`
* **Schema Version:** 4.1.1
* **Pathfinding.cloud ID:** glue-001
* **MITRE Tactics:** TA0004 - Privilege Escalation
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1578 - Modify Cloud Compute Infrastructure

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-glue-001-to-admin-starting-user` IAM user to the `pl-prod-glue-001-to-admin-target-role` administrative role by passing the admin role to an AWS Glue development endpoint and executing AWS CLI commands via SSH on that endpoint.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-glue-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-glue-001-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-glue-001-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-glue-001-to-admin-target-role` -- allows passing the admin role to the Glue service when creating a dev endpoint
- `glue:CreateDevEndpoint` on `*` -- allows creating a Glue development endpoint that will assume the passed role

**Helpful** (`pl-prod-glue-001-to-admin-starting-user`):
- `glue:GetDevEndpoint` -- check endpoint provisioning status and retrieve the public address for SSH access
- `iam:ListRoles` -- discover available privileged roles that can be passed to Glue
- `glue:DeleteDevEndpoint` -- clean up created endpoints after the demonstration

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable glue-001-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `glue-001-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-glue-001-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-glue-001-to-admin-target-role` | Administrative role passed to Glue dev endpoint |
| `arn:aws:iam::{account_id}:policy/pl-prod-glue-001-to-admin-passrole-policy` | Policy allowing PassRole on target role and glue:CreateDevEndpoint |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

> **Cost Warning:** AWS Glue development endpoints cost approximately $2.20 per hour while running (minimum 2-node configuration). The demo script creates a Glue dev endpoint that accrues charges until deleted. Always run the cleanup script immediately after testing.

#### Executing the automated demo_attack script

The script will:
1. Retrieve starting user credentials and region from Terraform outputs
2. Verify the starting user identity and confirm lack of admin permissions
3. Generate an SSH key pair for the Glue dev endpoint
4. Create the Glue dev endpoint, passing the admin role via `iam:PassRole`
5. Poll endpoint status every 30 seconds until it reaches `READY` (typically 5-10 minutes)
6. Retrieve the endpoint's public address
7. SSH into the endpoint and execute `aws iam list-users` to verify admin access
8. Extract and display the caller identity from the endpoint to confirm the admin role is in use

#### Resources Created by Attack Script

- Glue development endpoint (`pl-glue-001-demo-endpoint`) with admin role attached
- Temporary SSH key pair at `/tmp/pl-glue-001-demo-key` and `/tmp/pl-glue-001-demo-key.pub`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo glue-001-iam-passrole+glue-createdevendpoint
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `glue-001-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

**This cleanup is critical** — the Glue dev endpoint costs ~$2.20/hour while running. The cleanup script deletes the endpoint and removes the temporary SSH key files.

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup glue-001-iam-passrole+glue-createdevendpoint
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `glue-001-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable glue-001-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `glue-001-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user with `iam:PassRole` permission on privileged roles
- IAM user with `glue:CreateDevEndpoint` permission
- Combination of PassRole and Glue permissions enabling privilege escalation
- IAM role with administrative permissions that can be passed to Glue services
- Glue trust policy allowing the Glue service to assume privileged roles
- Privilege escalation path from user to admin via Glue dev endpoint creation

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

- **Restrict glue:CreateDevEndpoint permissions**: Only grant this permission to users who legitimately need to create Glue development endpoints (data engineers, ETL developers). This is a powerful permission that should be tightly controlled.

- **Use IAM Access Analyzer**: Enable IAM Access Analyzer to automatically detect privilege escalation paths involving PassRole and Glue services. Review findings regularly and remediate identified risks.

- **Implement least privilege for Glue roles**: When creating IAM roles for Glue services, grant only the minimum permissions required for the specific ETL tasks. Avoid using administrative policies like `AdministratorAccess` or `PowerUserAccess` on Glue service roles.

- **Require MFA for sensitive operations**: Implement MFA requirements for operations like `glue:CreateDevEndpoint` and `iam:PassRole` to add an additional layer of security against compromised credentials.

- **Use VPC endpoints for Glue**: Configure Glue dev endpoints to run within private VPCs without public SSH access, reducing the attack surface even if an endpoint is created with elevated privileges.

- **Tag and monitor Glue resources**: Apply mandatory tagging to Glue dev endpoints and monitor for endpoints created without proper tags or by unauthorized users. Use AWS Config rules to enforce tagging policies.

- **Set up billing alerts**: Configure AWS Budgets to alert when Glue costs exceed expected thresholds, helping detect unauthorized dev endpoint creation based on unexpected charges.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: PassRole` -- IAM role passed to a Glue service; high severity when the passed role has administrative permissions
- `Glue: CreateDevEndpoint` -- Glue development endpoint created; critical when combined with PassRole on a privileged role
- `Glue: GetDevEndpoint` -- attacker retrieves endpoint details (SSH key, endpoint address) for interactive access

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
