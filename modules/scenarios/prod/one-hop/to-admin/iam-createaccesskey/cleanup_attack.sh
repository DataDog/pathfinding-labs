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
PROFILE="prod"
ADMIN_USER="pl-cak-admin"
TEMP_CREDS_FILE="/tmp/pl-cak-temp-creds.json"
TEMP_PROFILE="pl-cak-temp-admin"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM CreateAccessKey Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Check if credentials file exists
if [ ! -f "$TEMP_CREDS_FILE" ]; then
    echo -e "${YELLOW}No temporary credentials file found at $TEMP_CREDS_FILE${NC}"
    echo "Attempting to list and delete access keys for user: $ADMIN_USER"
else
    # Read access key ID from temp file
    ACCESS_KEY_ID=$(jq -r '.AccessKey.AccessKeyId' $TEMP_CREDS_FILE)
    echo "Found access key to delete: $ACCESS_KEY_ID"
fi

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

# Step 3: Remove temporary credentials file
if [ -f "$TEMP_CREDS_FILE" ]; then
    echo -e "${YELLOW}Step 3: Removing temporary credentials file${NC}"
    rm -f $TEMP_CREDS_FILE
    echo -e "${GREEN}✓ Removed $TEMP_CREDS_FILE${NC}"
fi

# Step 4: Remove temporary AWS profile
echo -e "${YELLOW}Step 4: Removing temporary AWS profile${NC}"
if aws configure list --profile $TEMP_PROFILE &> /dev/null; then
    aws configure set aws_access_key_id "" --profile $TEMP_PROFILE
    aws configure set aws_secret_access_key "" --profile $TEMP_PROFILE
    # Note: AWS CLI doesn't have a direct command to remove profiles
    echo -e "${YELLOW}Note: You may want to manually remove the [$TEMP_PROFILE] section from ~/.aws/credentials and ~/.aws/config${NC}"
fi
echo -e "${GREEN}✓ Cleanup instructions provided${NC}\n"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}All access keys for $ADMIN_USER have been deleted${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

