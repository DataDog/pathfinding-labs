# Glue Dev Endpoint Update to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $634/mo
* **Technique:** Add SSH public key to existing Glue dev endpoint and execute commands with the endpoint's administrative role
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_glue_002_glue_updatedevendpoint`
* **Schema Version:** 4.0.0
* **Pathfinding.cloud ID:** glue-002
* **MITRE Tactics:** TA0004 - Privilege Escalation
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1021.004 - Remote Services: SSH

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-glue-002-to-admin-starting-user` IAM user to the `pl-prod-glue-002-to-admin-target-role` administrative role by adding an SSH public key to a pre-existing Glue development endpoint and executing AWS CLI commands through the SSH session using the endpoint's attached IAM role.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-glue-002-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-glue-002-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-glue-002-to-admin-starting-user`):
- `glue:UpdateDevEndpoint` on `*` -- add an SSH public key to any existing Glue development endpoint

**Helpful** (`pl-prod-glue-002-to-admin-starting-user`):
- `glue:GetDevEndpoint` -- retrieve endpoint details including the public address needed for the SSH connection
- `glue:GetDevEndpoints` -- list existing endpoints to identify targets with privileged roles attached

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_admin_glue_002_glue_updatedevendpoint
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
| `arn:aws:iam::{account_id}:user/pl-prod-glue-002-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:policy/pl-prod-glue-002-to-admin-policy` | Allows `glue:UpdateDevEndpoint` and `glue:GetDevEndpoint` permissions |
| `arn:aws:glue:{region}:{account_id}:devEndpoint/pl-prod-glue-002-to-admin-endpoint` | Pre-existing Glue development endpoint with administrative role |
| `arn:aws:iam::{account_id}:role/pl-prod-glue-002-to-admin-target-role` | Administrative role attached to the Glue dev endpoint |
| `arn:aws:iam::{account_id}:role/pl-prod-glue-002-to-admin-endpoint-service-role` | Service role allowing Glue to assume the target role |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Generate an SSH key pair for the attack
3. Update the Glue dev endpoint to add the SSH public key
4. Wait for the endpoint to become ready (this may take 5-10 minutes)
5. Retrieve the endpoint SSH address
6. Connect via SSH and execute AWS CLI commands with administrative privileges
7. Verify successful privilege escalation
8. Output standardized test results for automation

#### Resources Created by Attack Script

- Temporary SSH key pair generated for the attack (`/tmp/pl-glue-002-updatede-key`)
- SSH public key added to the Glue dev endpoint

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo glue-002-glue-updatedevendpoint
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

After demonstrating the attack, clean up the SSH public key from the endpoint. This will remove the attacker's SSH public key from the endpoint, reverting it to its original state. The cleanup script uses admin credentials to ensure successful removal of attack artifacts.

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup glue-002-glue-updatedevendpoint
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_glue_002_glue_updatedevendpoint
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

- **Privilege Escalation Path**: User with `glue:UpdateDevEndpoint` can access roles attached to existing endpoints
- **Overprivileged Endpoint Roles**: Glue dev endpoints configured with administrative or highly privileged IAM roles
- **Broad Glue Permissions**: IAM principals with `glue:UpdateDevEndpoint` permissions on all endpoints (`Resource: "*"`)
- **Long-Running Dev Endpoints**: Glue dev endpoints that remain active for extended periods with privileged roles
- **Missing Resource Conditions**: Glue permissions without resource-level restrictions or condition keys
- **SSH Access to Privileged Resources**: Ability to add SSH keys to compute resources with administrative roles

#### Prevention Recommendations

- **Restrict UpdateDevEndpoint Permissions**: Limit `glue:UpdateDevEndpoint` to specific endpoints using resource ARNs, not wildcard (`*`)
- **Use Least Privilege Roles**: Attach only the minimum necessary IAM permissions to Glue dev endpoint roles, avoiding administrative access
- **Implement Resource Tagging**: Use tags and condition keys to control which principals can update specific endpoints:
  ```json
  {
    "Condition": {
      "StringEquals": {
        "aws:ResourceTag/Team": "${aws:PrincipalTag/Team}"
      }
    }
  }
  ```
- **Use SCPs for Sensitive Roles**: Implement Service Control Policies to prevent Glue endpoints from assuming highly privileged roles:
  ```json
  {
    "Effect": "Deny",
    "Action": "sts:AssumeRole",
    "Resource": "arn:aws:iam::*:role/*Admin*",
    "Condition": {
      "StringEquals": {
        "aws:PrincipalServiceName": "glue.amazonaws.com"
      }
    }
  }
  ```
- **Limit Endpoint Lifespan**: Use automation to terminate idle Glue dev endpoints or those running for extended periods
- **Separate Development and Production**: Never use Glue dev endpoints with production-level IAM roles; use separate accounts or strict role boundaries
- **Use IAM Access Analyzer**: Regularly scan for privilege escalation paths involving Glue permissions
- **Disable Unused Endpoints**: Automatically terminate Glue dev endpoints that haven't been accessed in a defined period

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `Glue: UpdateDevEndpoint` -- Glue dev endpoint updated; critical when `addPublicKeys` parameter is present, indicating SSH key injection
- `Glue: GetDevEndpoint` -- Dev endpoint details retrieved; may indicate reconnaissance to obtain the SSH address after key injection
- `Glue: GetDevEndpoints` -- All dev endpoints listed; may indicate reconnaissance to identify privileged targets

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
