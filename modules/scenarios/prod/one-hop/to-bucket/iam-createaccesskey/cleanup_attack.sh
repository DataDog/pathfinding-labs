#!/bin/bash

# Cleanup script for iam:CreateAccessKey to S3 bucket demo
# This script removes the access keys created during the demo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
BUCKET_ACCESS_USER="pl-prod-one-hop-createaccesskey-bucket-access-user"
PRIVESC_USER="pl-prod-one-hop-createaccesskey-bucket-privesc-user"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM CreateAccessKey Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get credentials from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving privesc user credentials from Terraform${NC}"
PRIVESC_ACCESS_KEY=$(cd ../../../../../../ && terraform output -raw prod_one_hop_to_bucket_iam_createaccesskey_privesc_user_access_key_id 2>/dev/null || echo "")
PRIVESC_SECRET_KEY=$(cd ../../../../../../ && terraform output -raw prod_one_hop_to_bucket_iam_createaccesskey_privesc_user_secret_access_key 2>/dev/null || echo "")

if [ -z "$PRIVESC_ACCESS_KEY" ] || [ -z "$PRIVESC_SECRET_KEY" ]; then
    echo -e "${RED}Error: Could not retrieve privesc user credentials from Terraform${NC}"
    echo -e "${YELLOW}Please ensure the scenario is deployed${NC}"
    exit 1
fi

echo "Privesc user: $PRIVESC_USER"
echo -e "${GREEN}✓ Retrieved credentials${NC}\n"

# Step 2: Configure AWS credentials
echo -e "${YELLOW}Step 2: Configuring AWS credentials${NC}"
export AWS_ACCESS_KEY_ID=$PRIVESC_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$PRIVESC_SECRET_KEY
unset AWS_SESSION_TOKEN

ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Configured credentials${NC}\n"

# Step 3: List all access keys for the bucket access user
echo -e "${YELLOW}Step 3: Listing access keys for $BUCKET_ACCESS_USER${NC}"
ACCESS_KEYS=$(aws iam list-access-keys --user-name $BUCKET_ACCESS_USER --query 'AccessKeyMetadata[*].AccessKeyId' --output text)

if [ -z "$ACCESS_KEYS" ]; then
    echo -e "${GREEN}No access keys found for $BUCKET_ACCESS_USER${NC}"
else
    echo "Found access keys: $ACCESS_KEYS"
    
    # Step 4: Delete each access key
    echo -e "${YELLOW}Step 4: Deleting access keys${NC}"
    for KEY in $ACCESS_KEYS; do
        echo "Deleting access key: $KEY"
        aws iam delete-access-key \
            --user-name $BUCKET_ACCESS_USER \
            --access-key-id $KEY
        echo -e "${GREEN}✓ Deleted access key: $KEY${NC}"
    done
fi
echo ""

# Step 5: Remove local temporary files
echo -e "${YELLOW}Step 5: Removing local temporary files${NC}"
DOWNLOAD_FILE="/tmp/createaccesskey-bucket-sensitive-data-${ACCOUNT_ID}.txt"

if [ -f "$DOWNLOAD_FILE" ]; then
    rm -f "$DOWNLOAD_FILE"
    echo -e "${GREEN}✓ Deleted $DOWNLOAD_FILE${NC}"
else
    echo "No downloaded file found at $DOWNLOAD_FILE"
fi
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}All access keys for $BUCKET_ACCESS_USER have been deleted${NC}"
echo -e "${YELLOW}The infrastructure (bucket, users, sensitive-data.txt) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
