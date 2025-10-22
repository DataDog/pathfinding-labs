#!/bin/bash

# Cleanup script for iam:AttachRolePolicy to S3 bucket demo
# This script detaches the AmazonS3FullAccess policy from the bucket access role

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROFILE="pl-pathfinder-starting-user-prod"
BUCKET_ACCESS_ROLE="pl-prod-one-hop-attachrolepolicy-bucket-access-role"
S3_POLICY_ARN="arn:aws:iam::aws:policy/AmazonS3FullAccess"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM AttachRolePolicy Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get account ID
echo -e "${YELLOW}Step 1: Getting account ID${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --profile $PROFILE --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 2: Detach S3FullAccess policy
echo -e "${YELLOW}Step 2: Detaching AmazonS3FullAccess policy from $BUCKET_ACCESS_ROLE${NC}"
aws iam detach-role-policy \
    --role-name $BUCKET_ACCESS_ROLE \
    --policy-arn $S3_POLICY_ARN \
    --profile $PROFILE

echo -e "${GREEN}✓ Detached S3FullAccess policy${NC}\n"

# Step 3: Remove local temporary files
echo -e "${YELLOW}Step 3: Removing local temporary files${NC}"
DOWNLOAD_FILE="/tmp/attachrolepolicy-sensitive-data-${ACCOUNT_ID}.txt"

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
echo -e "${GREEN}The AmazonS3FullAccess policy has been detached${NC}"
echo -e "${YELLOW}The infrastructure (bucket, roles, sensitive-data.txt) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
