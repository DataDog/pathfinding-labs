# SSM Send Command to Bucket

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $8/mo
* **Technique:** Execute commands on EC2 instances with S3 access roles to extract credentials and access sensitive buckets via SSM SendCommand
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_bucket_ssm_002_ssm_sendcommand`
* **Schema Version:** 4.1.1
* **Pathfinding.cloud ID:** ssm-002
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0008 - Lateral Movement, TA0006 - Credential Access
* **MITRE Techniques:** T1651 - Cloud Administration Command, T1552.005 - Unsecured Credentials: Cloud Instance Metadata API

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-ssm-002-to-bucket-starting-user` IAM user to the `pl-sensitive-data-ssm-002-{account_id}-{suffix}` S3 bucket by sending an SSM command to an EC2 instance with an attached S3 access role, extracting the temporary credentials from the instance metadata service, and using those credentials locally to access the sensitive bucket.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-ssm-002-to-bucket-starting-user`
- **Destination resource:** `arn:aws:s3:::pl-sensitive-data-ssm-002-{account_id}-{suffix}`

### Starting Permissions

**Required** (`pl-prod-ssm-002-to-bucket-starting-user`):
- `ssm:SendCommand` on `*` -- execute arbitrary shell commands on EC2 instances via AWS Systems Manager

**Helpful** (`pl-prod-ssm-002-to-bucket-starting-user`):
- `ssm:ListCommands` -- view command execution status and results
- `ssm:ListCommandInvocations` -- list command invocations for the sent commands
- `ssm:GetCommandInvocation` -- retrieve detailed command output containing extracted credentials
- `ssm:DescribeInstanceInformation` -- verify SSM agent status on target instances
- `ec2:DescribeInstances` -- discover EC2 instances with S3 access roles attached

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable single_account_privesc_one_hop_to_bucket_ssm_002_ssm_sendcommand
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ssm-002-to-bucket` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-ssm-002-to-bucket-starting-user` | Scenario-specific starting user with access keys and SSM permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-ssm-002-to-bucket-ec2-bucket-role` | S3 access role attached to the EC2 instance (target for credential extraction) |
| `arn:aws:iam::{account_id}:instance-profile/pl-prod-ssm-002-to-bucket-instance-profile` | Instance profile associating the S3 role with the EC2 instance |
| `arn:aws:ec2:{region}:{account_id}:instance/i-xxxxxxxxx` | EC2 instance with SSM agent and S3 access role attached |
| `arn:aws:s3:::pl-sensitive-data-ssm-002-{account_id}-{suffix}` | Target S3 bucket containing sensitive data |
| `arn:aws:s3:::pl-sensitive-data-ssm-002-{account_id}-{suffix}/sensitive-data.txt` | Sensitive file in the target bucket |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Verify successful privilege escalation to S3 bucket access
4. Output standardized test results for automation

#### Resources Created by Attack Script

- Temporary credential files containing extracted EC2 instance role credentials
- Downloaded sensitive data files from the target S3 bucket

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo ssm-002-ssm-sendcommand
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ssm-002-to-bucket` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup ssm-002-ssm-sendcommand
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ssm-002-to-bucket` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable single_account_privesc_one_hop_to_bucket_ssm_002_ssm_sendcommand
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ssm-002-to-bucket` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- **EC2 instances with sensitive data access**: Instances with IAM roles that grant access to sensitive S3 buckets or other data stores represent a significant risk, especially if those instances are also accessible via SSM.
- **Principals with ssm:SendCommand on wildcard resources**: The ability to execute commands on any EC2 instance in the account should be restricted to specific instances using resource ARNs or IAM condition keys.
- **Lack of IAM condition keys restricting SSM access**: Policies should use conditions like `ssm:resourceTag/Environment` to limit which instances can be targeted.
- **Missing AWS Systems Manager Session Manager logging**: SSM commands should be logged to CloudWatch Logs or S3 for audit and forensic purposes.
- **EC2 instances without IMDSv2 enforcement**: The Instance Metadata Service should be configured to require IMDSv2, which provides protection against SSRF attacks and makes metadata extraction more difficult.
- **Overly permissive S3 bucket access from EC2 roles**: EC2 instance roles should only have access to specific S3 prefixes or objects, not entire buckets with sensitive data.

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

- **Apply least privilege to EC2 instance roles**: EC2 instances should only have the minimum S3 permissions necessary for their function. Restrict bucket access to specific prefixes and use `s3:GetObject` instead of `s3:*`:
  ```json
  {
    "Effect": "Allow",
    "Action": ["s3:GetObject", "s3:PutObject"],
    "Resource": "arn:aws:s3:::my-bucket/application-data/*"
  }
  ```

- **Enforce IMDSv2 on all EC2 instances**: Require Instance Metadata Service Version 2 (IMDSv2), which uses session-based authentication and provides protection against SSRF attacks:
  ```bash
  aws ec2 modify-instance-metadata-options \
    --instance-id i-1234567890abcdef0 \
    --http-tokens required
  ```

- **Enable SSM Session Manager logging**: Configure AWS Systems Manager to log all command executions to CloudWatch Logs or S3 for audit and forensic analysis.

- **Implement S3 bucket policies with VPC endpoint restrictions**: Restrict S3 bucket access to specific VPC endpoints, ensuring that only resources within the expected VPC can access the bucket:
  ```json
  {
    "Effect": "Deny",
    "Principal": "*",
    "Action": "s3:*",
    "Resource": ["arn:aws:s3:::my-bucket/*", "arn:aws:s3:::my-bucket"],
    "Condition": {
      "StringNotEquals": {
        "aws:sourceVpce": "vpce-1234567"
      }
    }
  }
  ```

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

- **Enable S3 Access Logging**: Configure S3 access logging to track all access to sensitive buckets, enabling detection of unusual access patterns:
  ```bash
  aws s3api put-bucket-logging \
    --bucket my-sensitive-bucket \
    --bucket-logging-status file://logging.json
  ```

- **Tag sensitive resources**: Apply consistent tags to sensitive S3 buckets and EC2 instances with access to those buckets, enabling automated policy enforcement and monitoring.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `SSM: SendCommand` -- SSM command sent to an EC2 instance; critical when targeting instances with S3 access roles attached
- `SSM: ListCommandInvocations` -- listing command invocations to track execution status; suspicious when following a SendCommand targeting a privileged instance
- `SSM: GetCommandInvocation` -- retrieving detailed command output; high severity when used to extract credentials from instance metadata
- `S3: GetObject` -- object downloaded from S3 bucket; critical when performed using EC2 instance role credentials from a non-EC2 source IP address

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
