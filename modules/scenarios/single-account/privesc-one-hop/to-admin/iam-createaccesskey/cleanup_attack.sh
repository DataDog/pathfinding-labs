#!/bin/bash

# Cleanup script for iam:CreateAccessKey privilege escalation demo
# This script removes the access keys created during the demo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROFILE="pl-admin-cleanup-prod"
ADMIN_USER="pl-prod-one-hop-cak-admin"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM CreateAccessKey Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: List all access keys for the admin user
echo -e "${YELLOW}Step 1: Listing access keys for $ADMIN_USER${NC}"
ACCESS_KEYS=$(aws iam list-access-keys --user-name $ADMIN_USER --profile $PROFILE --query 'AccessKeyMetadata[*].AccessKeyId' --output text)

if [ -z "$ACCESS_KEYS" ]; then
    echo -e "${GREEN}No access keys found for $ADMIN_USER${NC}"
else
    echo "Found access keys: $ACCESS_KEYS"
    
    # Step 2: Delete each access key
    echo -e "${YELLOW}Step 2: Deleting access keys${NC}"
    for KEY in $ACCESS_KEYS; do
        echo "Deleting access key: $KEY"
        aws iam delete-access-key \
            --user-name $ADMIN_USER \
            --access-key-id $KEY \
            --profile $PROFILE
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

