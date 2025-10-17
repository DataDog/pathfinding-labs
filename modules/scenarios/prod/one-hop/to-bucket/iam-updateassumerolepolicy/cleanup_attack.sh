#!/bin/bash

# Cleanup script for iam:UpdateAssumeRolePolicy to S3 bucket demo
# This script restores the original trust policy on the bucket access role

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROFILE="pl-pathfinder-starting-user-prod"
BUCKET_ACCESS_ROLE="pl-prod-one-hop-updateassumerolepolicy-bucket-access-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM UpdateAssumeRolePolicy Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get account ID
echo -e "${YELLOW}Step 1: Getting account ID${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --profile $PROFILE --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 2: Restore original trust policy (only root)
echo -e "${YELLOW}Step 2: Restoring original trust policy on $BUCKET_ACCESS_ROLE${NC}"
echo "Setting trust policy to only allow root principal..."

# Restore the original trust policy
cat > /tmp/original-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${ACCOUNT_ID}:root"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam update-assume-role-policy \
    --role-name $BUCKET_ACCESS_ROLE \
    --policy-document file:///tmp/original-trust-policy.json \
    --profile $PROFILE

echo -e "${GREEN}✓ Restored original trust policy${NC}\n"

# Step 3: Remove local temporary files
echo -e "${YELLOW}Step 3: Removing local temporary files${NC}"
DOWNLOAD_FILE="/tmp/updateassumerolepolicy-sensitive-data-${ACCOUNT_ID}.txt"

if [ -f "$DOWNLOAD_FILE" ]; then
    rm -f "$DOWNLOAD_FILE"
    echo -e "${GREEN}✓ Deleted $DOWNLOAD_FILE${NC}"
else
    echo "No downloaded file found at $DOWNLOAD_FILE"
fi

if [ -f "/tmp/original-trust-policy.json" ]; then
    rm -f "/tmp/original-trust-policy.json"
    echo -e "${GREEN}✓ Deleted /tmp/original-trust-policy.json${NC}"
fi

echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}The bucket access role trust policy has been restored${NC}"
echo -e "${YELLOW}The infrastructure (bucket, roles, sensitive-data.txt) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
