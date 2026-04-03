# One-Hop Privilege Escalation: ssm:StartSession to EC2 with S3 Bucket Access

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $5/mo
* **Technique:** Start interactive shell sessions on EC2 instances with S3 access roles to extract credentials via IMDS and access sensitive buckets
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_bucket_ssm_001_ssm_startsession`
* **Schema Version:** 4.0.0
* **Pathfinding.cloud ID:** ssm-001
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0006 - Credential Access
* **MITRE Techniques:** T1552.005 - Unsecured Credentials: Cloud Instance Metadata API, T1078.004 - Valid Accounts: Cloud Accounts

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-ssm-001-to-bucket-starting-user` IAM user to the `pl-sensitive-data-ssm-001-to-bucket-{account_id}-{suffix}` S3 bucket by starting an interactive SSM session on a target EC2 instance and extracting temporary credentials from the Instance Metadata Service (IMDS).

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-ssm-001-to-bucket-starting-user`
- **Destination resource:** `arn:aws:s3:::pl-sensitive-data-ssm-001-to-bucket-{account_id}-{suffix}`

### Starting Permissions

**Required** (`pl-prod-ssm-001-to-bucket-starting-user`):
- `ssm:StartSession` on `arn:aws:ec2:*:{account_id}:instance/{target_instance_id}` and `arn:aws:ssm:*:*:document/SSM-SessionManagerRunShell` -- allows establishing an interactive shell session on the target EC2 instance

**Helpful** (`pl-prod-ssm-001-to-bucket-starting-user`):
- `ec2:DescribeInstances` -- discover target EC2 instances and their attached instance profiles
- `ssm:DescribeInstanceInformation` -- identify which instances have the SSM agent running and are reachable
- `sts:GetCallerIdentity` -- verify credentials after exfiltration from IMDS
- `s3:ListBucket` -- enumerate bucket contents after gaining access via extracted credentials

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_bucket_ssm_001_ssm_startsession
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
| `arn:aws:iam::{account_id}:user/pl-prod-ssm-001-to-bucket-starting-user` | Scenario-specific starting user with access keys and SSM StartSession permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-ssm-001-to-bucket-ec2-role` | S3 access role attached to the EC2 instance (target for credential extraction) |
| `arn:aws:iam::{account_id}:instance-profile/pl-prod-ssm-001-to-bucket-instance-profile` | Instance profile associating the S3 role with the EC2 instance |
| `arn:aws:ec2:{region}:{account_id}:instance/i-xxxxxxxxx` | EC2 instance with SSM agent and S3 access role attached |
| `arn:aws:s3:::pl-sensitive-data-ssm-001-to-bucket-{account_id}-{suffix}` | Target S3 bucket containing sensitive data |
| `arn:aws:s3:::pl-sensitive-data-ssm-001-to-bucket-{account_id}-{suffix}/sensitive-data.txt` | Sensitive file in the target bucket |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Verify successful privilege escalation to S3 bucket access
4. Output standardized test results for automation

#### Resources Created by Attack Script

- Temporary credential files with extracted EC2 instance role credentials
- Downloaded sensitive data files from the target S3 bucket

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
plabs disable enable_single_account_privesc_one_hop_to_bucket_ssm_001_ssm_startsession
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

- **EC2 instances with sensitive data access**: Instances with IAM roles that grant access to sensitive S3 buckets or other data stores represent a significant risk, especially if those instances are also accessible via SSM Session Manager.
- **Principals with ssm:StartSession on wildcard resources**: The ability to start interactive sessions on any EC2 instance in the account should be restricted to specific instances using resource ARNs or IAM condition keys.
- **Lack of IAM condition keys restricting SSM access**: Policies should use conditions like `ssm:resourceTag/Environment` to limit which instances can be targeted for interactive sessions.
- **Missing AWS Systems Manager Session Manager logging**: SSM sessions should be logged to CloudWatch Logs or S3 for audit and forensic purposes.
- **EC2 instances without IMDSv2 enforcement**: The Instance Metadata Service should be configured to require IMDSv2, which provides protection against SSRF attacks and makes metadata extraction more difficult (though still possible from an interactive shell).
- **Overly permissive S3 bucket access from EC2 roles**: EC2 instance roles should only have access to specific S3 prefixes or objects, not entire buckets with sensitive data.
- **Privilege escalation path via SSM**: Tools should detect that a principal with ssm:StartSession can gain access to credentials of EC2 instance roles, creating a privilege escalation path to S3 bucket access.

#### Prevention Recommendations

- **Restrict ssm:StartSession with resource conditions**: Use IAM policy conditions to limit SSM session access to specific instances or instances with specific tags:
  ```json
  {
    "Effect": "Allow",
    "Action": "ssm:StartSession",
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

- **Enforce IMDSv2 on all EC2 instances**: Require Instance Metadata Service Version 2 (IMDSv2), which uses session-based authentication and provides protection against SSRF attacks. Note that IMDSv2 does not prevent credential extraction from interactive shell access, but it does prevent SSRF-based extraction:
  ```bash
  aws ec2 modify-instance-metadata-options \
    --instance-id i-1234567890abcdef0 \
    --http-tokens required
  ```

- **Enable SSM Session Manager logging**: Configure AWS Systems Manager to log all session activity to CloudWatch Logs or S3 for audit and forensic analysis:
  ```json
  {
    "schemaVersion": "1.0",
    "description": "Document to hold regional settings for Session Manager",
    "sessionType": "Standard_Stream",
    "inputs": {
      "s3BucketName": "my-session-logs-bucket",
      "s3KeyPrefix": "session-logs/",
      "cloudWatchLogGroupName": "/aws/ssm/sessions",
      "cloudWatchEncryptionEnabled": true
    }
  }
  ```

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

- **Use IAM Access Analyzer**: Regularly scan for privilege escalation paths involving SSM and EC2 instance roles using AWS IAM Access Analyzer or third-party tools like Pathfinding.cloud.

- **Enable S3 Access Logging**: Configure S3 access logging to track all access to sensitive buckets, enabling detection of unusual access patterns:
  ```bash
  aws s3api put-bucket-logging \
    --bucket my-sensitive-bucket \
    --bucket-logging-status file://logging.json
  ```

- **Tag sensitive resources**: Apply consistent tags to sensitive S3 buckets and EC2 instances with access to those buckets, enabling automated policy enforcement and monitoring.

- **Implement session duration limits**: Configure maximum session durations for EC2 instance roles to limit the window of opportunity for credential extraction:
  ```json
  {
    "Effect": "Allow",
    "Principal": {
      "Service": "ec2.amazonaws.com"
    },
    "Action": "sts:AssumeRole",
    "Condition": {
      "NumericLessThanEquals": {
        "sts:DurationSeconds": 3600
      }
    }
  }
  ```

- **Use AWS PrivateLink for S3**: Configure VPC endpoints for S3 and enforce that all S3 access must come through the VPC endpoint, preventing access from extracted credentials used outside the VPC.

- **Enable GuardDuty**: AWS GuardDuty can detect anomalous behavior such as unusual S3 API calls or credential usage patterns that may indicate compromised instance credentials.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `SSM: StartSession` -- Interactive shell session started on an EC2 instance; high severity when the target instance has an IAM role with S3 access permissions
- `S3: GetObject` -- Object downloaded from S3; critical when the caller is an EC2 instance role used from a non-EC2 IP address
- `S3: ListBucket` -- Bucket contents enumerated; investigate when instance role credentials are used from an unexpected source IP or geographic location
- `STS: GetCallerIdentity` -- Caller identity verified; commonly used by attackers after extracting credentials to confirm they are working

**Credential Extraction Pattern**:
- `SSM: StartSession` targeting an instance with an S3 access role, followed by S3 API calls from the instance role credentials originating from non-EC2 IP addresses or geographic locations inconsistent with the EC2 instance region

**SSM Session Anomalies**:
- SSM session initiated by principals who rarely or never use SSM
- SSM sessions to instances with sensitive data access roles
- Multiple SSM sessions initiated in rapid succession
- SSM sessions outside normal business hours

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
