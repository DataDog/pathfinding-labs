#!/bin/bash

# Cleanup script for ec2-instance-connect:SendSSHPublicKey privilege escalation demo
# This script removes temporary SSH keys created during the demo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SSH_KEY_PATH="/tmp/pathfinding_eic_key"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}EC2 Instance Connect Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials and region from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get admin cleanup user credentials from root terraform output
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)
CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup credentials in terraform output${NC}"
    echo "Make sure the admin cleanup user is deployed"
    exit 1
fi

if [ -z "$CURRENT_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    CURRENT_REGION="us-east-1"
fi

# Set admin credentials
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_REGION="$CURRENT_REGION"
unset AWS_SESSION_TOKEN

echo "Region from Terraform: $CURRENT_REGION"
echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Get starting user name from scenario outputs
cd ../../../../../..  # Navigate to root again
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_ec2_003_ec2_instance_connect_sendsshpublickey.value // empty')
STARTING_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_name')
cd - > /dev/null

if [ -z "$STARTING_USER_NAME" ] || [ "$STARTING_USER_NAME" == "null" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve starting user name from Terraform outputs${NC}"
    echo -e "${YELLOW}Skipping policy detachment - you may need to manually remove AdministratorAccess policy${NC}"
    echo ""
else
    # Step 2: Remove AdministratorAccess policy from starting user
    echo -e "${YELLOW}Step 2: Removing AdministratorAccess policy from starting user${NC}"
    echo "Starting user: $STARTING_USER_NAME"
    echo "Detaching AdministratorAccess policy..."

    if aws iam detach-user-policy \
        --user-name "$STARTING_USER_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess" 2>/dev/null; then
        echo -e "${GREEN}✓ Successfully detached AdministratorAccess policy from $STARTING_USER_NAME${NC}"
    else
        echo -e "${YELLOW}⚠ Policy may not be attached or already removed${NC}"
    fi
    echo ""
fi

# Step 3: Remove temporary SSH keys
echo -e "${YELLOW}Step 3: Removing temporary SSH keys${NC}"

if [ -f "${SSH_KEY_PATH}" ] || [ -f "${SSH_KEY_PATH}.pub" ]; then
    echo "Removing SSH key pair from: ${SSH_KEY_PATH}"
    rm -f ${SSH_KEY_PATH} ${SSH_KEY_PATH}.pub
    echo -e "${GREEN}✓ Removed temporary SSH keys${NC}"
else
    echo -e "${YELLOW}No SSH keys found at ${SSH_KEY_PATH} (may already be deleted)${NC}"
fi
echo ""

# Step 4: Verify SSH keys are removed
echo -e "${YELLOW}Step 4: Verifying cleanup${NC}"
if [ ! -f "${SSH_KEY_PATH}" ] && [ ! -f "${SSH_KEY_PATH}.pub" ]; then
    echo -e "${GREEN}✓ Confirmed: SSH keys have been removed${NC}"
else
    echo -e "${RED}⚠ Warning: Some SSH key files still exist${NC}"
fi
echo ""

# Step 5: Clean up environment variables
echo -e "${YELLOW}Step 5: Cleaning up environment variables${NC}"
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN
unset AWS_REGION
echo -e "${GREEN}✓ Cleared AWS environment variables${NC}"
echo ""

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Removed AdministratorAccess policy from starting user"
echo "- Removed temporary SSH key pair"
echo "- Cleared environment variables"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (EC2 instance, IAM roles, and users) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}"
echo ""
echo -e "${BLUE}Note: The SSH public key pushed to the instance automatically expires after 60 seconds.${NC}"
echo -e "${BLUE}The extracted instance role credentials are temporary and will expire.${NC}"
echo -e "${BLUE}The AdministratorAccess policy has been removed from the starting user.${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
