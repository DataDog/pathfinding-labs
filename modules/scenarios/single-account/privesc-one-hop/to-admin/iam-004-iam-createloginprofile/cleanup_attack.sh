#!/bin/bash

# Cleanup script for iam:CreateLoginProfile privilege escalation demo
# This script removes the login profile created during the attack


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ADMIN_USER="pl-prod-iam-004-to-admin-target-user"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM CreateLoginProfile Demo Cleanup${NC}"
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

# Step 2: Verify admin identity
echo -e "${YELLOW}Step 2: Verifying admin identity${NC}"
ADMIN_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $ADMIN_IDENTITY"
echo -e "${GREEN}✓ Verified admin identity${NC}\n"

# Step 3: Check if login profile exists
echo -e "${YELLOW}Step 3: Checking if login profile exists for $ADMIN_USER${NC}"

if aws iam get-login-profile --user-name $ADMIN_USER &> /dev/null; then
    echo -e "${GREEN}✓ Login profile found for $ADMIN_USER${NC}\n"

    # Step 4: Delete the login profile
    echo -e "${YELLOW}Step 4: Deleting login profile${NC}"

    aws iam delete-login-profile --user-name $ADMIN_USER

    echo -e "${GREEN}✓ Successfully deleted login profile${NC}\n"
else
    echo -e "${YELLOW}No login profile exists for $ADMIN_USER (nothing to clean up)${NC}\n"
fi

# Step 5: Verify cleanup
echo -e "${YELLOW}Step 5: Verifying cleanup${NC}"

if aws iam get-login-profile --user-name $ADMIN_USER &> /dev/null; then
    echo -e "${RED}⚠ Login profile still exists!${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Confirmed: Login profile has been removed${NC}"
fi

echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}The login profile has been removed${NC}"
echo -e "${YELLOW}The infrastructure (users, roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
