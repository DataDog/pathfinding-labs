# SSM Send Command to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $8/mo
* **Cost Estimate When Demo Executed:** $8/mo
* **Technique:** Execute commands on EC2 instances with privileged roles to extract credentials via SSM SendCommand
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_ssm_002_ssm_sendcommand`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** ssm-002
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0008 - Lateral Movement
* **MITRE Techniques:** T1651 - Cloud Administration Command, T1552.005 - Unsecured Credentials: Cloud Instance Metadata API

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-ssm-002-to-admin-starting-user` IAM user to the `pl-prod-ssm-002-to-admin-ec2-admin-role` administrative role by sending an SSM command to a target EC2 instance and extracting temporary credentials from the Instance Metadata Service (IMDS).

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-ssm-002-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-ssm-002-to-admin-ec2-admin-role`

### Starting Permissions

**Required** (`pl-prod-ssm-002-to-admin-starting-user`):
- `ssm:SendCommand` on `*` -- execute arbitrary shell commands on EC2 instances via SSM

**Helpful** (`pl-prod-ssm-002-to-admin-starting-user`):
- `ssm:ListCommands` -- track command execution status during the attack
- `ssm:ListCommandInvocations` -- retrieve command output containing the extracted credentials
- `ec2:DescribeInstances` -- discover target EC2 instances with privileged roles attached

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
plabs enable ssm-002-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ssm-002-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-ssm-002-to-admin-starting-user` | Scenario-specific starting user with access keys and SSM permissions |
| `arn:aws:iam::{account_id}:policy/pl-prod-ssm-002-to-admin-policy` | Allows `ssm:SendCommand`, `ssm:ListCommands`, `ssm:ListCommandInvocations`, and `ec2:DescribeInstances` |
| `arn:aws:iam::{account_id}:role/pl-prod-ssm-002-to-admin-ec2-admin-role` | Administrative role attached to the EC2 instance (target for credential extraction) |
| `arn:aws:iam::{account_id}:instance-profile/pl-prod-ssm-002-to-admin-ec2-admin-profile` | Instance profile associating the admin role with the EC2 instance |
| `arn:aws:ec2:{region}:{account_id}:instance/i-xxxxxxxxx` | EC2 instance with SSM agent and admin role attached |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/ssm-002-to-admin` | CTF flag parameter (readable with AdministratorAccess) |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve starting user credentials and EC2 instance ID from Terraform outputs
2. Verify starting user identity and confirm no admin access yet
3. Enumerate the target EC2 instance and confirm SSM agent is online
4. Send an SSM command to execute an IMDSv2 credential extraction on the instance
5. Poll until the command completes, then retrieve the JSON credentials from the command output
6. Export the extracted access key, secret key, and session token as environment variables
7. Verify administrator access by listing IAM users
8. Capture the CTF flag from SSM Parameter Store using the extracted admin credentials

#### Resources Created by Attack Script

- Temporary credential variables containing the extracted EC2 instance role credentials (access key, secret key, session token)
- SSM command record in the account (auto-purged by AWS after 30 days)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo ssm-002-ssm-sendcommand
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ssm-002-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup ssm-002-ssm-sendcommand
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ssm-002-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable ssm-002-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ssm-002-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- **EC2 instances with overly privileged IAM roles**: Instances should follow the principle of least privilege. An EC2 instance with `AdministratorAccess` or similar broad permissions represents a significant risk.
- **Principals with ssm:SendCommand on wildcard resources**: The ability to execute commands on any EC2 instance in the account should be restricted to specific instances using resource ARNs or IAM condition keys.
- **Lack of IAM condition keys restricting SSM access**: Policies should use conditions like `ssm:resourceTag/Environment` to limit which instances can be targeted.
- **Missing AWS Systems Manager Session Manager logging**: SSM commands should be logged to CloudWatch Logs or S3 for audit and forensic purposes.
- **EC2 instances without IMDSv2 enforcement**: The Instance Metadata Service should be configured to require IMDSv2, which provides protection against SSRF attacks and makes metadata extraction more difficult.

#### Prevention Recommendations

- **Restrict ssm:SendCommand with resource conditions**: Use IAM policy conditions to limit SSM command execution to specific instances or instances with specific tags:
  ```json
  {
    "Effect": "Allow",
    "Action": "ssm:SendCommand",
    "Resource": "arn:aws:ec2:*:*:instance/*",
    "Condition": {
      "StringEquals": {
        "ssm:resourceTag/Environment": "dev"
      }
    }
  }
  ```

- **Apply least privilege to EC2 instance roles**: EC2 instances should only have the minimum permissions necessary for their function. Avoid attaching `AdministratorAccess` or other broad policies to instance profiles.

- **Enforce IMDSv2 on all EC2 instances**: Require Instance Metadata Service Version 2 (IMDSv2), which uses session-based authentication and provides protection against SSRF attacks:
  ```bash
  aws ec2 modify-instance-metadata-options \
    --instance-id i-1234567890abcdef0 \
    --http-tokens required
  ```

- **Enable SSM Session Manager logging**: Configure AWS Systems Manager to log all command executions to CloudWatch Logs or S3 for audit and forensic analysis.

- **Implement Service Control Policies (SCPs)**: Use AWS Organizations SCPs to prevent overly broad SSM permissions at the organization level:
  ```json
  {
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Deny",
      "Action": "ssm:SendCommand",
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "ssm:resourceTag/SSMAccess": "Allowed"
        }
      }
    }]
  }
  ```

- **Use IAM Access Analyzer**: Regularly scan for privilege escalation paths involving SSM and EC2 instance roles using AWS IAM Access Analyzer or third-party tools.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `ssm:SendCommand` -- SSM command executed on an EC2 instance; critical when the target instance has a privileged IAM role attached
- `ssm:ListCommandInvocations` -- Command output retrieved; high severity when following a SendCommand on a privileged instance, as it may contain extracted credentials
- `sts:GetCallerIdentity` -- Identity verification call; suspicious when originating from instance role credentials used at a non-EC2 IP address or in an unexpected region

**Credential Extraction Pattern to alert on**:
- `ssm:SendCommand` targeting an instance with a privileged role, followed by
- `ssm:ListCommandInvocations` retrieving the output, followed by
- AWS API calls using the instance role credentials from a non-EC2 source IP

**Anomalous API Usage indicators**:
- Instance role credentials being used from geographic locations inconsistent with the EC2 instance region
- High-volume API calls from instance role credentials outside normal usage patterns
- Instance role credentials used after the EC2 instance has been terminated

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
