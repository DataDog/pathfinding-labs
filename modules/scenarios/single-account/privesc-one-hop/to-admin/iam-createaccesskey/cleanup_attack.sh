#!/bin/bash

# Cleanup script for iam:CreateAccessKey privilege escalation demo
# This script removes the access keys created during the demo

set -e

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ADMIN_USER="pl-prod-one-hop-cak-admin"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM CreateAccessKey Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials from Terraform output
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Go to project root

# Get admin cleanup user credentials from root terraform output
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup credentials in terraform output${NC}"
    echo "Make sure the admin cleanup user is deployed"
    exit 1
fi

# Set admin credentials
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
unset AWS_SESSION_TOKEN

echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

cd - > /dev/null  # Return to scenario directory

# Step 2: List all access keys for the admin user
echo -e "${YELLOW}Step 2: Listing access keys for $ADMIN_USER${NC}"
ACCESS_KEYS=$(aws iam list-access-keys --user-name $ADMIN_USER --query 'AccessKeyMetadata[*].AccessKeyId' --output text)

if [ -z "$ACCESS_KEYS" ]; then
    echo -e "${GREEN}No access keys found for $ADMIN_USER${NC}"
else
    echo "Found access keys: $ACCESS_KEYS"
    
    # Step 3: Delete each access key
    echo -e "${YELLOW}Step 3: Deleting access keys${NC}"
    for KEY in $ACCESS_KEYS; do
        echo "Deleting access key: $KEY"
        aws iam delete-access-key \
            --user-name $ADMIN_USER \
            --access-key-id $KEY
        echo -e "${GREEN}✓ Deleted access key: $KEY${NC}"
    done
fi


echo -e "${GREEN}✓ Cleanup instructions provided${NC}\n"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}All access keys for $ADMIN_USER have been deleted${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

