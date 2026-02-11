#!/bin/bash

# Cleanup script for iam:DeleteAccessKey + iam:CreateAccessKey privilege escalation demo
# This script removes the newly created access key and notes about the deleted key

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ADMIN_USER="pl-prod-iam-003-to-admin-target-user"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: IAM DeleteAccessKey + CreateAccessKey${NC}"
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

# Step 2: Check for deleted key info
echo -e "${YELLOW}Step 2: Checking for deleted key information${NC}"
if [ -f /tmp/deleted_key_info.txt ]; then
    DELETED_KEY=$(cat /tmp/deleted_key_info.txt)
    echo "Found deleted key ID: $DELETED_KEY"
    echo -e "${YELLOW}Note: The deleted key ($DELETED_KEY) cannot be restored.${NC}"
    echo -e "${YELLOW}The Terraform state manages the original keys, so reapplying will recreate them.${NC}"

    # Clean up the temp file
    rm -f /tmp/deleted_key_info.txt
    echo -e "${GREEN}✓ Cleaned up deleted key info file${NC}"
else
    echo -e "${YELLOW}No deleted key info found (may have already been cleaned up)${NC}"
fi
echo ""

# Step 3: List current access keys
echo -e "${YELLOW}Step 3: Listing current access keys for $ADMIN_USER${NC}"
CURRENT_KEYS=$(aws iam list-access-keys --user-name $ADMIN_USER --output json)
KEY_COUNT=$(echo "$CURRENT_KEYS" | jq '.AccessKeyMetadata | length')

echo "Current access keys:"
echo "$CURRENT_KEYS" | jq -r '.AccessKeyMetadata[] | "  - \(.AccessKeyId) (Created: \(.CreateDate), Status: \(.Status))"'
echo "Total keys: $KEY_COUNT"
echo ""

# Step 4: Identify and delete demo-created keys
echo -e "${YELLOW}Step 4: Identifying keys created during demo${NC}"

# Get all key IDs and their creation dates
ALL_KEYS=$(echo "$CURRENT_KEYS" | jq -r '.AccessKeyMetadata[] | "\(.AccessKeyId)|\(.CreateDate)"')

if [ -z "$ALL_KEYS" ]; then
    echo -e "${YELLOW}No access keys found for $ADMIN_USER${NC}"
else
    echo "Analyzing access keys..."

    # Get the module output to find the original Terraform-managed keys
    cd ../../../../../..
    MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_iam_003_iam_deleteaccesskey_createaccesskey.value // empty')

    if [ -n "$MODULE_OUTPUT" ]; then
        # Try to get terraform-managed key IDs if they exist in the output
        TF_KEY_1=$(echo "$MODULE_OUTPUT" | jq -r '.admin_user_existing_key_1_id // empty')
        TF_KEY_2=$(echo "$MODULE_OUTPUT" | jq -r '.admin_user_existing_key_2_id // empty')

        echo "Terraform-managed keys:"
        [ -n "$TF_KEY_1" ] && echo "  - $TF_KEY_1"
        [ -n "$TF_KEY_2" ] && echo "  - $TF_KEY_2"
    fi
    cd - > /dev/null

    echo ""
    echo "Keys to potentially clean up (created during demo):"

    KEYS_DELETED=0
    while IFS='|' read -r KEY_ID CREATE_DATE; do
        # Skip terraform-managed keys if we know them
        if [ "$KEY_ID" == "$TF_KEY_1" ] || [ "$KEY_ID" == "$TF_KEY_2" ]; then
            echo "  - $KEY_ID (Terraform-managed, keeping)"
            continue
        fi

        # This is likely a demo-created key
        echo "  - $KEY_ID (Created: $CREATE_DATE)"
        echo "    Deleting demo-created access key: $KEY_ID"

        aws iam delete-access-key \
            --user-name $ADMIN_USER \
            --access-key-id $KEY_ID

        echo -e "    ${GREEN}✓ Deleted: $KEY_ID${NC}"
        KEYS_DELETED=$((KEYS_DELETED + 1))
    done <<< "$ALL_KEYS"

    if [ $KEYS_DELETED -eq 0 ]; then
        echo -e "${YELLOW}No demo-created keys found to delete${NC}"
        echo -e "${YELLOW}Only Terraform-managed keys remain${NC}"
    fi
fi
echo ""

# Step 5: Verify final state
echo -e "${YELLOW}Step 5: Verifying final state${NC}"
FINAL_KEYS=$(aws iam list-access-keys --user-name $ADMIN_USER --output json)
FINAL_COUNT=$(echo "$FINAL_KEYS" | jq '.AccessKeyMetadata | length')

echo "Final access keys for $ADMIN_USER:"
echo "$FINAL_KEYS" | jq -r '.AccessKeyMetadata[] | "  - \(.AccessKeyId) (Status: \(.Status))"'
echo "Total keys remaining: $FINAL_COUNT"
echo ""

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Deleted demo-created access keys for $ADMIN_USER"
echo "- Cleaned up temporary files"
echo "- Remaining keys: $FINAL_COUNT (Terraform-managed)"

echo -e "\n${YELLOW}Note about deleted keys:${NC}"
echo "The key deleted during the demo cannot be restored directly."
echo "To fully restore the original state with all Terraform-managed keys:"
echo "  1. Set the scenario flag to false in terraform.tfvars"
echo "  2. Run: terraform apply (destroys the scenario)"
echo "  3. Set the scenario flag to true"
echo "  4. Run: terraform apply (recreates with fresh keys)"

echo -e "\n${GREEN}The environment has been cleaned of demo artifacts.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
