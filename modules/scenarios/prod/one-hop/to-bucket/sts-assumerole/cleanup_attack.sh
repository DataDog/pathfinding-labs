#!/bin/bash

# Cleanup script for sts:AssumeRole to S3 bucket access demo
# This script removes temporary files and test objects created during the demo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROFILE="pl-pathfinder-starting-user-prod"
BUCKET_ACCESS_ROLE="pl-prod-one-hop-assumerole-bucket-access-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}STS AssumeRole Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get account ID
echo -e "${YELLOW}Step 1: Getting account ID${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --profile $PROFILE --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 2: Remove local temporary files
echo -e "${YELLOW}Step 2: Removing local temporary files${NC}"
DOWNLOAD_FILE="/tmp/sensitive-data-${ACCOUNT_ID}.txt"
TEST_FILE="/tmp/test-write-${ACCOUNT_ID}.txt"

if [ -f "$DOWNLOAD_FILE" ]; then
    rm -f "$DOWNLOAD_FILE"
    echo -e "${GREEN}✓ Deleted $DOWNLOAD_FILE${NC}"
else
    echo "No downloaded file found at $DOWNLOAD_FILE"
fi

if [ -f "$TEST_FILE" ]; then
    rm -f "$TEST_FILE"
    echo -e "${GREEN}✓ Deleted $TEST_FILE${NC}"
else
    echo "No test file found at $TEST_FILE"
fi
echo ""

# Step 3: Assume role to clean up S3 objects
echo -e "${YELLOW}Step 3: Assuming role to clean up S3 test objects${NC}"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${BUCKET_ACCESS_ROLE}"

CREDENTIALS=$(aws sts assume-role \
    --role-arn $ROLE_ARN \
    --role-session-name cleanup-session \
    --profile $PROFILE \
    --query 'Credentials' \
    --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')

echo -e "${GREEN}✓ Assumed role for cleanup${NC}\n"

# Step 4: Get bucket name
echo -e "${YELLOW}Step 4: Finding target bucket${NC}"
BUCKET_NAME=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, 'pl-prod-one-hop-assumerole-bucket-')].Name" --output text)

if [ -z "$BUCKET_NAME" ]; then
    echo -e "${RED}Error: Could not find target bucket${NC}"
    exit 1
fi

echo "Target bucket: $BUCKET_NAME"
echo -e "${GREEN}✓ Found target bucket${NC}\n"

# Step 5: Remove test file from S3
echo -e "${YELLOW}Step 5: Removing test objects from S3 bucket${NC}"
if aws s3 ls s3://$BUCKET_NAME/demo-test-file.txt 2>/dev/null; then
    aws s3 rm s3://$BUCKET_NAME/demo-test-file.txt
    echo -e "${GREEN}✓ Deleted demo-test-file.txt from bucket${NC}"
else
    echo "No demo-test-file.txt found in bucket"
fi
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}All temporary files and test objects have been removed${NC}"
echo -e "${YELLOW}The infrastructure (bucket, role, sensitive-data.txt) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
