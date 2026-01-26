#!/bin/bash

# Cleanup script for ssm:SendCommand privilege escalation demo
# This script cleans up any SSM command history (though AWS automatically cleans up after 30 days)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SSM SendCommand Demo Cleanup${NC}"
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

# Step 2: Check for SSM commands (informational only)
echo -e "${YELLOW}Step 2: Checking for SSM command history${NC}"
echo "Note: SSM commands are automatically cleaned up by AWS after 30 days"

# Get module output to find instance ID
cd ../../../../../..
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_ssm_002_ssm_sendcommand.value // empty')
INSTANCE_ID=$(echo "$MODULE_OUTPUT" | jq -r '.ec2_instance_id // empty')
cd - > /dev/null

if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "null" ]; then
    echo "Checking recent SSM commands on instance: $INSTANCE_ID"

    RECENT_COMMANDS=$(aws ssm list-commands \
        --region $CURRENT_REGION \
        --instance-id "$INSTANCE_ID" \
        --max-results 5 \
        --query 'Commands[*].[CommandId,Status,RequestedDateTime]' \
        --output text 2>/dev/null || echo "")

    if [ -n "$RECENT_COMMANDS" ]; then
        echo "Recent SSM commands found:"
        echo "$RECENT_COMMANDS"
        echo ""
        echo -e "${YELLOW}These commands will be automatically deleted by AWS after 30 days${NC}"
    else
        echo -e "${GREEN}✓ No recent SSM commands found${NC}"
    fi
else
    echo -e "${YELLOW}Could not retrieve instance ID from Terraform output${NC}"
fi
echo ""

# Step 3: Clean up environment variables
echo -e "${YELLOW}Step 3: Cleaning up environment variables${NC}"
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
echo "- Checked SSM command history (automatically cleaned by AWS after 30 days)"
echo "- Cleared environment variables"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (EC2 instance, IAM roles, and users) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}"
echo ""
echo -e "${BLUE}Note: This scenario does not create persistent artifacts that require cleanup.${NC}"
echo -e "${BLUE}The SSM command executed during the demo is stored in AWS Systems Manager${NC}"
echo -e "${BLUE}command history and will be automatically deleted after 30 days.${NC}\n"
