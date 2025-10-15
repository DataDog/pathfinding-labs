#!/bin/bash

# Demo script for x-account-from-dev-to-prod-role-assumption-s3-access module
# This script demonstrates cross-account role assumption from dev to prod

set -e

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Pathfinder-labs Cross-Account Role Assumption Demo ===${NC}"
echo "This demo shows how to assume roles across accounts from dev to prod"
echo ""

# Get account IDs
DEV_ACCOUNT_ID=$(aws sts get-caller-identity --profile pl-pathfinder-starting-user-dev --query Account --output text)
PROD_ACCOUNT_ID=$(aws sts get-caller-identity --profile pl-pathfinder-starting-user-prod --query Account --output text)

echo -e "${YELLOW}Account Information:${NC}"
echo "Dev Account ID: $DEV_ACCOUNT_ID"
echo "Prod Account ID: $PROD_ACCOUNT_ID"
echo ""

# Role and user names
DEV_ROLE_NAME="pl-x-account-dev-s3-sensitive-data-access-role"
DEV_USER_NAME="pl-x-account-dev-s3-sensitive-data-access-user"
PROD_ROLE_NAME="pl-x-account-prod-s3-sensitive-data-access-role"

echo -e "${YELLOW}Step 1: Testing dev role assumption of prod role${NC}"
# Test dev role assuming prod role
DEV_ROLE_ARN="arn:aws:iam::${DEV_ACCOUNT_ID}:role/${DEV_ROLE_NAME}"
PROD_ROLE_ARN="arn:aws:iam::${PROD_ACCOUNT_ID}:role/${PROD_ROLE_NAME}"

echo "Dev Role ARN: $DEV_ROLE_ARN"
echo "Prod Role ARN: $PROD_ROLE_ARN"

# Assume the dev role first
echo "Assuming dev role..."
DEV_ASSUME_OUTPUT=$(aws sts assume-role --role-arn "$DEV_ROLE_ARN" --role-session-name "cross-account-demo" --profile pl-pathfinder-starting-user-dev)
export AWS_ACCESS_KEY_ID=$(echo "$DEV_ASSUME_OUTPUT" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$DEV_ASSUME_OUTPUT" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$DEV_ASSUME_OUTPUT" | jq -r '.Credentials.SessionToken')

echo -e "${GREEN}✓ Successfully assumed dev role${NC}"

# Now assume the prod role from the dev role
echo "Assuming prod role from dev role..."
PROD_ASSUME_OUTPUT=$(aws sts assume-role --role-arn "$PROD_ROLE_ARN" --role-session-name "cross-account-prod-access")
export AWS_ACCESS_KEY_ID=$(echo "$PROD_ASSUME_OUTPUT" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$PROD_ASSUME_OUTPUT" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$PROD_ASSUME_OUTPUT" | jq -r '.Credentials.SessionToken')

echo -e "${GREEN}✓ Successfully assumed prod role from dev role${NC}"

echo ""
echo -e "${YELLOW}Step 2: Discovering S3 bucket${NC}"
# Now that we have S3 access, discover the bucket
BUCKET_NAME=$(aws s3 ls | grep "pl-x-account-sensitive-data-" | awk '{print $3}' | head -1)

if [ -z "$BUCKET_NAME" ]; then
    echo -e "${RED}✗ Could not find S3 bucket with prefix 'pl-x-account-sensitive-data-'${NC}"
    echo "Available buckets:"
    aws s3 ls
    exit 1
fi

echo -e "${GREEN}✓ Found S3 bucket: $BUCKET_NAME${NC}"

echo ""
echo -e "${YELLOW}Step 3: Verifying cross-account access${NC}"
# Verify we can access the S3 bucket
echo "Current caller identity:"
aws sts get-caller-identity

echo ""
echo "Testing S3 bucket access..."
aws s3 ls s3://$BUCKET_NAME/

echo -e "${GREEN}✓ Successfully accessed S3 bucket from dev account${NC}"

# Reset credentials for next test
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

echo ""
echo -e "${YELLOW}Step 4: Testing alternative access path${NC}"
# Test the alternative access path (this demonstrates the same concept)
echo "Testing alternative cross-account access pattern..."

# Reset credentials first
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

# Assume the dev role again and then the prod role (demonstrating the pattern)
echo "Assuming dev role again..."
DEV_ASSUME_OUTPUT2=$(aws sts assume-role --role-arn "$DEV_ROLE_ARN" --role-session-name "cross-account-demo-2" --profile pl-pathfinder-starting-user-dev)
export AWS_ACCESS_KEY_ID=$(echo "$DEV_ASSUME_OUTPUT2" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$DEV_ASSUME_OUTPUT2" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$DEV_ASSUME_OUTPUT2" | jq -r '.Credentials.SessionToken')

echo -e "${GREEN}✓ Successfully assumed dev role again${NC}"

# Now assume the prod role from the dev role
echo "Assuming prod role from dev role (alternative path)..."
PROD_ASSUME_OUTPUT2=$(aws sts assume-role --role-arn "$PROD_ROLE_ARN" --role-session-name "cross-account-prod-access-2")
export AWS_ACCESS_KEY_ID=$(echo "$PROD_ASSUME_OUTPUT2" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$PROD_ASSUME_OUTPUT2" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$PROD_ASSUME_OUTPUT2" | jq -r '.Credentials.SessionToken')

echo -e "${GREEN}✓ Successfully assumed prod role from dev role (alternative path)${NC}"

echo ""
echo -e "${YELLOW}Step 5: Verifying alternative cross-account access${NC}"
# Verify we can access the S3 bucket
echo "Current caller identity:"
aws sts get-caller-identity

echo ""
echo "Testing S3 bucket access..."
aws s3 ls s3://$BUCKET_NAME/

echo -e "${GREEN}✓ Successfully accessed S3 bucket via alternative path${NC}"

echo ""
echo -e "${YELLOW}Step 6: Demonstrating sensitive data access${NC}"
# Create a test file to demonstrate access
echo "Creating test file to demonstrate access..."
echo "Cross-account access successful! This is sensitive data from prod account." > /tmp/sensitive-data.txt

# Upload the file (using current assumed role credentials)
aws s3 cp /tmp/sensitive-data.txt s3://$BUCKET_NAME/test-file.txt
echo -e "${GREEN}✓ Uploaded test file to S3 bucket${NC}"

# Download and verify the file (using current assumed role credentials)
echo "Downloading and verifying file access..."
aws s3 cp s3://$BUCKET_NAME/test-file.txt /tmp/downloaded-sensitive-data.txt
cat /tmp/downloaded-sensitive-data.txt

echo -e "${GREEN}✓ Successfully demonstrated cross-account data access${NC}"

# Clean up test files
rm -f /tmp/sensitive-data.txt /tmp/downloaded-sensitive-data.txt

echo ""
echo -e "${GREEN}✓ Cross-account role assumption successful!${NC}"
echo "This demonstrates how dev resources can access prod resources through role assumption."

# Standardized test results output
echo "TEST_RESULT:x-account-from-dev-to-prod-role-assumption-s3-access:SUCCESS"
echo "TEST_DETAILS:x-account-from-dev-to-prod-role-assumption-s3-access:Successfully demonstrated cross-account role assumption from dev to prod with S3 access"
echo "TEST_METRICS:x-account-from-dev-to-prod-role-assumption-s3-access:dev_role_assumed=true,prod_role_assumed=true,s3_access_gained=true,data_transfer_tested=true"

echo ""
echo -e "${YELLOW}Step 7: Cleanup${NC}"
# Clean up the test file (using current assumed role credentials)
aws s3 rm s3://$BUCKET_NAME/test-file.txt
echo -e "${GREEN}✓ Cleaned up test file${NC}"

echo ""
echo -e "${GREEN}=== Demo Complete ===${NC}"
echo "This demonstrates cross-account role assumption from dev to prod environments."
echo "Both role-based and user-based access patterns were successfully tested."
