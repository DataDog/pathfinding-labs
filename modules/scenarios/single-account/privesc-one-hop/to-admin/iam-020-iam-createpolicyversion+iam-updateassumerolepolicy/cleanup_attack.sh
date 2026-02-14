#!/bin/bash

# Cleanup script for iam-createpolicyversion+iam-updateassumerolepolicy privilege escalation demo
# This script deletes the malicious policy version v2, restores v1 as default, and restores the original trust policy


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
TARGET_POLICY="pl-prod-iam-020-to-admin-target-policy"
TARGET_ROLE="pl-prod-iam-020-to-admin-target-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: iam:CreatePolicyVersion + iam:UpdateAssumeRolePolicy${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials and region from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get admin cleanup user credentials from root terraform output
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)
CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup credentials in terraform output${NC}"
    echo "Make sure the admin cleanup user is deployed"
    exit 1
fi

if [ -z "$CURRENT_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    CURRENT_REGION="us-east-1"
fi

# Set admin credentials
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_REGION="$CURRENT_REGION"
unset AWS_SESSION_TOKEN

echo "Region from Terraform: $CURRENT_REGION"
echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 2: Get target policy and role ARNs from Terraform
echo -e "${YELLOW}Step 2: Getting target policy and role information from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_iam_020_iam_createpolicyversion_iam_updateassumerolepolicy.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output for this scenario${NC}"
    echo "The scenario may not be deployed"
    exit 1
fi

TARGET_POLICY_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.target_policy_arn')
TARGET_ROLE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.target_role_name')

if [ "$TARGET_POLICY_ARN" == "null" ] || [ -z "$TARGET_POLICY_ARN" ]; then
    echo -e "${RED}Error: Could not extract policy ARN from terraform output${NC}"
    exit 1
fi

echo "Target policy ARN: $TARGET_POLICY_ARN"
echo "Target role name: $TARGET_ROLE_NAME"
echo -e "${GREEN}✓ Retrieved resource information${NC}\n"

cd - > /dev/null

# Step 3: List current policy versions
echo -e "${YELLOW}Step 3: Checking current policy versions${NC}"
echo "Target policy: $TARGET_POLICY"
echo ""

echo "Current policy versions:"
POLICY_VERSIONS=$(aws iam list-policy-versions \
    --policy-arn $TARGET_POLICY_ARN \
    --query 'Versions[*].[VersionId,IsDefaultVersion,CreateDate]' \
    --output table 2>/dev/null || echo "None")

echo "$POLICY_VERSIONS"
echo ""

# Step 4: Delete policy version v2 if it exists
echo -e "${YELLOW}Step 4: Deleting malicious policy version v2${NC}"

# Check if v2 exists
if aws iam get-policy-version \
    --policy-arn $TARGET_POLICY_ARN \
    --version-id v2 &> /dev/null; then

    echo "Found policy version v2, deleting..."

    # If v2 is the default, we need to set v1 as default first
    DEFAULT_VERSION=$(aws iam get-policy \
        --policy-arn $TARGET_POLICY_ARN \
        --query 'Policy.DefaultVersionId' \
        --output text)

    if [ "$DEFAULT_VERSION" == "v2" ]; then
        echo "Setting v1 as the default version..."
        aws iam set-default-policy-version \
            --policy-arn $TARGET_POLICY_ARN \
            --version-id v1
        echo -e "${GREEN}✓ Set v1 as default version${NC}"
    fi

    # Now delete v2
    aws iam delete-policy-version \
        --policy-arn $TARGET_POLICY_ARN \
        --version-id v2

    echo -e "${GREEN}✓ Deleted policy version v2${NC}"
else
    echo -e "${YELLOW}Policy version v2 not found (may already be deleted)${NC}"
fi
echo ""

# Step 5: Restore original trust policy
echo -e "${YELLOW}Step 5: Restoring original role trust policy${NC}"
echo "Target role: $TARGET_ROLE_NAME"
echo ""

# Restore the original trust policy (only EC2 service)
ORIGINAL_TRUST_POLICY='{
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
}'

# Write to temporary file
echo "$ORIGINAL_TRUST_POLICY" > /tmp/original-trust-policy.json

echo "Restoring original trust policy (EC2 service only)..."
aws iam update-assume-role-policy \
    --role-name $TARGET_ROLE_NAME \
    --policy-document file:///tmp/original-trust-policy.json

echo -e "${GREEN}✓ Restored original trust policy${NC}"
echo ""

# Step 6: Clean up temporary files
echo -e "${YELLOW}Step 6: Cleaning up temporary files${NC}"
TEMP_FILES=("/tmp/admin-policy.json" "/tmp/new-trust-policy.json" "/tmp/original-trust-policy.json")

for FILE in "${TEMP_FILES[@]}"; do
    if [ -f "$FILE" ]; then
        rm -f "$FILE"
        echo -e "${GREEN}✓ Deleted $FILE${NC}"
    fi
done

# Check if any files were not found
FILES_NOT_FOUND=0
for FILE in "${TEMP_FILES[@]}"; do
    if [ ! -f "$FILE" ] && [ "$FILES_NOT_FOUND" -eq 0 ]; then
        echo -e "${YELLOW}Some temporary files not found (may already be deleted)${NC}"
        FILES_NOT_FOUND=1
    fi
done
echo ""

# Step 7: Verify cleanup
echo -e "${YELLOW}Step 7: Verifying cleanup${NC}"
echo "Policy versions after cleanup:"
aws iam list-policy-versions \
    --policy-arn $TARGET_POLICY_ARN \
    --query 'Versions[*].[VersionId,IsDefaultVersion,CreateDate]' \
    --output table 2>/dev/null

echo ""
echo "Default version policy document:"
CURRENT_VERSION=$(aws iam get-policy \
    --policy-arn $TARGET_POLICY_ARN \
    --query 'Policy.DefaultVersionId' \
    --output text)

aws iam get-policy-version \
    --policy-arn $TARGET_POLICY_ARN \
    --version-id $CURRENT_VERSION \
    --query 'PolicyVersion.Document' \
    --output json | jq '.'

echo ""
echo "Restored trust policy:"
aws iam get-role \
    --role-name $TARGET_ROLE_NAME \
    --query 'Role.AssumeRolePolicyDocument' \
    --output json | jq '.'

echo ""
echo -e "${GREEN}✓ Verified policy restored to original state (v1 with minimal permissions)${NC}"
echo -e "${GREEN}✓ Verified trust policy restored to original state (EC2 service only)${NC}"
echo ""

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Deleted policy version v2 with admin permissions"
echo "- Restored v1 as the default version"
echo "- Target policy now has only minimal permissions"
echo "- Restored original trust policy (EC2 service only)"
echo "- Cleaned up temporary files"
echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, and policies) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
