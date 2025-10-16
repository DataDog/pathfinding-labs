#!/bin/bash

# Cleanup script for iam:UpdateAssumeRolePolicy privilege escalation demo
# This script restores the original trust policy of the admin role

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROFILE="pl-admin-user-for-cleanup-scripts-prod"
ADMIN_ROLE="pl-prod-one-hop-updateassumerolepolicy-admin-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Restoring Original Trust Policy${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Check for saved original policy
echo -e "${YELLOW}Step 1: Looking for saved original trust policy${NC}"
if [ ! -f /tmp/original_trust_policy.json ]; then
    echo -e "${YELLOW}No saved policy found. Setting default EC2 service trust policy${NC}"
    # Use the original Terraform-defined trust policy
    ORIGINAL_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)
else
    echo -e "${GREEN}✓ Found saved original trust policy${NC}"
    ORIGINAL_POLICY=$(cat /tmp/original_trust_policy.json)
fi

echo "Trust policy to restore:"
echo "$ORIGINAL_POLICY" | jq '.'
echo ""

# Step 2: Get current trust policy
echo -e "${YELLOW}Step 2: Checking current trust policy${NC}"
CURRENT_POLICY=$(aws iam get-role --role-name $ADMIN_ROLE --profile $PROFILE --query 'Role.AssumeRolePolicyDocument' --output json 2>/dev/null || echo "")

if [ -z "$CURRENT_POLICY" ]; then
    echo -e "${RED}Error: Could not retrieve current trust policy${NC}"
    echo "The role might not exist or you might not have permissions"
    exit 1
fi

echo "Current trust policy:"
echo "$CURRENT_POLICY" | jq '.'
echo ""

# Step 3: Restore the original trust policy
echo -e "${YELLOW}Step 3: Restoring original trust policy${NC}"

aws iam update-assume-role-policy \
    --role-name $ADMIN_ROLE \
    --policy-document "$ORIGINAL_POLICY" \
    --profile $PROFILE

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully restored original trust policy${NC}\n"
else
    echo -e "${RED}Failed to restore trust policy${NC}"
    exit 1
fi

# Step 4: Verify the restoration
echo -e "${YELLOW}Step 4: Verifying the restoration${NC}"
RESTORED_POLICY=$(aws iam get-role --role-name $ADMIN_ROLE --profile $PROFILE --query 'Role.AssumeRolePolicyDocument' --output json)

echo "Restored trust policy:"
echo "$RESTORED_POLICY" | jq '.'

# Step 5: Clean up temporary file
if [ -f /tmp/original_trust_policy.json ]; then
    rm /tmp/original_trust_policy.json
    echo -e "\n${GREEN}✓ Removed temporary policy file${NC}"
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Restored original trust policy for $ADMIN_ROLE"
echo "- Admin role now trusts only EC2 service (as originally configured)"
echo "- Attack artifacts have been removed"

echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"