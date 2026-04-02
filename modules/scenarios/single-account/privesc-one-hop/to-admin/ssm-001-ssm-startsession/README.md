# One-Hop Privilege Escalation: ssm:StartSession to EC2 with Admin Role

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $5/mo
* **Technique:** Start interactive session on EC2 instances with privileged roles to extract credentials via SSM StartSession
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_ssm_001_ssm_startsession`
* **Schema Version:** 3.0.0
* **Pathfinding.cloud ID:** ssm-001
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0006 - Credential Access
* **MITRE Techniques:** T1552.005 - Unsecured Credentials: Cloud Instance Metadata API, T1078.004 - Valid Accounts: Cloud Accounts

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-ssm-001-to-admin-starting-user` IAM user to the `pl-prod-ssm-001-to-admin-ec2-role` administrative role by starting an interactive SSM session on an EC2 instance and extracting credentials from the Instance Metadata Service (IMDS).

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-ssm-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-ssm-001-to-admin-ec2-role`

### Starting Permissions

**Required:**
- `ssm:StartSession` on `arn:aws:ec2:*:{account_id}:instance/{target_instance_id}` and `arn:aws:ssm:*:*:document/SSM-SessionManagerRunShell` -- allows opening an interactive shell session on the target EC2 instance

**Helpful:**
- `ec2:DescribeInstances` -- discover target EC2 instances and identify which have privileged IAM roles attached
- `ssm:DescribeInstanceInformation` -- identify which instances have the SSM agent running and are reachable
- `sts:GetCallerIdentity` -- verify credentials after exfiltration to confirm the level of access obtained

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_admin_ssm_001_ssm_startsession
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
| `arn:aws:iam::{account_id}:user/pl-prod-ssm-001-to-admin-starting-user` | Scenario-specific starting user with access keys and SSM permissions |
| `arn:aws:iam::{account_id}:policy/pl-prod-ssm-001-to-admin-policy` | Allows `ssm:StartSession`, `ssm:TerminateSession`, `ssm:ResumeSession`, `ssm:DescribeInstanceInformation`, and `ec2:DescribeInstances` |
| `arn:aws:iam::{account_id}:role/pl-prod-ssm-001-to-admin-ec2-role` | Administrative role attached to the EC2 instance (target for credential extraction) |
| `arn:aws:iam::{account_id}:instance-profile/pl-prod-ssm-001-to-admin-ec2-profile` | Instance profile associating the admin role with the EC2 instance |
| `arn:aws:ec2:{region}:{account_id}:instance/i-xxxxxxxxx` | EC2 instance with SSM agent and admin role attached |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve scenario credentials and instance ID from Terraform outputs
2. Verify the starting user's identity and confirm it lacks admin permissions
3. Discover the target EC2 instance and confirm the SSM agent is online
4. Prompt you to start an interactive SSM session on the instance
5. Guide you through querying the IMDS endpoint inside the session to retrieve temporary admin role credentials
6. Accept the pasted credential JSON and configure them in the local shell
7. Verify administrator access by listing IAM users with the extracted credentials

#### Resources Created by Attack Script

- Temporary AWS credential environment variables extracted from the EC2 instance metadata service (no persistent artifacts created)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo ssm-001-ssm-startsession
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup ssm-001-ssm-startsession
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_ssm_001_ssm_startsession
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

- **EC2 instances with overly privileged IAM roles**: Instances should follow the principle of least privilege. An EC2 instance with `AdministratorAccess` or similar broad permissions represents a significant risk, especially when combined with SSM access.
- **Principals with ssm:StartSession on wildcard resources**: The ability to start interactive sessions on any EC2 instance in the account should be restricted to specific instances using resource ARNs or IAM condition keys.
- **Lack of IAM condition keys restricting SSM access**: Policies should use conditions like `ssm:resourceTag/Environment` to limit which instances can be accessed via Session Manager.
- **Missing AWS Systems Manager Session Manager logging**: SSM sessions should be logged to CloudWatch Logs or S3 for audit and forensic purposes. Interactive sessions can be particularly risky without proper logging.
- **EC2 instances without IMDSv2 enforcement**: The Instance Metadata Service should be configured to require IMDSv2, which provides protection against SSRF attacks and makes metadata extraction more difficult. IMDSv2 requires session tokens before accessing metadata.
- **Session Manager access without MFA requirements**: Sensitive operations like starting sessions on instances with privileged roles should require multi-factor authentication.

#### Prevention Recommendations

- **Restrict ssm:StartSession with resource conditions**: Use IAM policy conditions to limit SSM session access to specific instances or instances with specific tags:
  ```json
  {
    "Effect": "Allow",
    "Action": "ssm:StartSession",
    "Resource": "arn:aws:ec2:*:*:instance/*",
    "Condition": {
      "StringEquals": {
        "ssm:resourceTag/Environment": "dev",
        "ssm:resourceTag/SSMAccess": "Allowed"
      }
    }
  }
  ```

- **Apply least privilege to EC2 instance roles**: EC2 instances should only have the minimum permissions necessary for their function. Avoid attaching `AdministratorAccess` or other broad policies to instance profiles. If an instance needs administrative access, consider using more granular permissions or temporary credential vending mechanisms.

- **Enforce IMDSv2 on all EC2 instances**: Require Instance Metadata Service Version 2 (IMDSv2), which uses session-based authentication and provides protection against SSRF attacks:
  ```bash
  aws ec2 modify-instance-metadata-options \
    --instance-id i-1234567890abcdef0 \
    --http-tokens required \
    --http-put-response-hop-limit 1
  ```

- **Enable SSM Session Manager logging**: Configure AWS Systems Manager to log all session activity to CloudWatch Logs or S3 for audit and forensic analysis. This is critical for detecting and investigating unauthorized access:
  ```json
  {
    "sessionLogging": {
      "cloudWatchLogGroupName": "/aws/ssm/session-logs",
      "cloudWatchEncryptionEnabled": true,
      "s3BucketName": "my-session-logs-bucket",
      "s3EncryptionEnabled": true
    }
  }
  ```

- **Require MFA for sensitive SSM operations**: Use IAM policy conditions to require multi-factor authentication for starting sessions on instances with privileged roles:
  ```json
  {
    "Effect": "Allow",
    "Action": "ssm:StartSession",
    "Resource": "arn:aws:ec2:*:*:instance/*",
    "Condition": {
      "BoolIfExists": {
        "aws:MultiFactorAuthPresent": "true"
      },
      "StringEquals": {
        "ssm:resourceTag/RequiresMFA": "true"
      }
    }
  }
  ```

- **Monitor CloudTrail for suspicious SSM activity**: Create CloudWatch alarms or SIEM rules for `ssm:StartSession` events targeting instances with privileged roles, extended session durations on sensitive instances, unusual API activity patterns from instance role credentials, and instance role credentials used from non-EC2 IP addresses.

- **Implement Service Control Policies (SCPs)**: Use AWS Organizations SCPs to prevent overly broad SSM permissions at the organization level and ensure consistent security controls:
  ```json
  {
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Deny",
      "Action": "ssm:StartSession",
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "ssm:resourceTag/SSMAccess": "Allowed"
        }
      }
    }]
  }
  ```

- **Use VPC endpoints for SSM**: Configure VPC endpoints for Systems Manager to keep SSM traffic within your VPC and enable more granular network-level controls through security groups and VPC endpoint policies.

- **Implement credential guard mechanisms**: Consider using tools or scripts on EC2 instances to detect and alert on unusual IMDS access patterns, such as repeated queries to the credentials endpoint or access from unexpected processes.

- **Use IAM Access Analyzer**: Regularly scan for privilege escalation paths involving SSM and EC2 instance roles using AWS IAM Access Analyzer or third-party tools like Pathfinding.cloud to identify these attack vectors before they can be exploited.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `SSM: StartSession` -- Interactive session started on an EC2 instance; high severity when the target instance has a privileged IAM role attached
- `SSM: TerminateSession` -- Session terminated; correlate with StartSession events to measure session duration and flag unusually long sessions
- `SSM: ResumeSession` -- Session resumed; may indicate persistent interactive access to a sensitive instance
- `STS: GetCallerIdentity` -- Caller identity verified; commonly used after extracting credentials to confirm the level of access obtained
- `EC2: DescribeInstances` -- EC2 instance enumeration; when followed by StartSession, may indicate reconnaissance to identify high-value targets

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
