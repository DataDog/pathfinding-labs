#!/bin/bash

# Cleanup script for test-reverse-blast-radius-escalation
# Reverts the real escalations the demo performed:
#   1. Deletes the extra access key minted on bucket-reader (NOT the terraform one)
#   2. Detaches AdministratorAccess from attach-self-user
# Uses admin cleanup credentials from Terraform (never an AWS profile).
# Idempotent: missing artifacts are treated as already cleaned.

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

BUCKET_READER_NAME="pl-prod-rbr-esc-bucket-reader"
ATTACH_SELF_USER_NAME="pl-prod-rbr-esc-attach-self-user"
ADMIN_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Reverse Blast Radius Escalation${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin cleanup credentials, region and the terraform-managed key id
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../..  # Navigate to root of terraform project

ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)
CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")
# The terraform-managed bucket-reader key MUST be preserved
TF_BUCKET_READER_KEY_ID=$(terraform output -json 2>/dev/null | jq -r '.tool_testing_test_reverse_blast_radius_escalation.value.bucket_reader_access_key_id // empty')

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup credentials in terraform output${NC}"
    echo "Make sure the admin cleanup user is deployed"
    exit 1
fi

if [ -z "$CURRENT_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    CURRENT_REGION="us-east-1"
fi

export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_REGION="$CURRENT_REGION"
unset AWS_SESSION_TOKEN

echo "Region from Terraform: $CURRENT_REGION"
echo "Terraform-managed bucket-reader key (preserved): ${TF_BUCKET_READER_KEY_ID:0:10}..."
echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Safety restore: ensure any helpful-permission deny policy is removed (no-op here)
source "$SCRIPT_DIR/../../../../scripts/lib/demo_permissions.sh"
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

# Re-assert admin creds (library sourcing does not change them, but be explicit)
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_REGION="$CURRENT_REGION"
unset AWS_SESSION_TOKEN

FAILED=0

# Step 2: Delete any access key on bucket-reader beyond the terraform-managed one
echo -e "${YELLOW}Step 2: Deleting the extra access key(s) minted on $BUCKET_READER_NAME${NC}"

EXISTING_KEYS=$(aws iam list-access-keys \
    --user-name "$BUCKET_READER_NAME" \
    --region "$CURRENT_REGION" \
    --query 'AccessKeyMetadata[*].AccessKeyId' \
    --output text 2>/dev/null)

if [ -z "$EXISTING_KEYS" ]; then
    echo -e "${YELLOW}No access keys found for $BUCKET_READER_NAME (user missing or no keys)${NC}"
else
    for KEY_ID in $EXISTING_KEYS; do
        if [ "$KEY_ID" == "$TF_BUCKET_READER_KEY_ID" ]; then
            echo "Preserving terraform-managed key: $KEY_ID"
            continue
        fi
        echo "Deleting demo-minted key: $KEY_ID"
        if aws iam delete-access-key \
            --user-name "$BUCKET_READER_NAME" \
            --access-key-id "$KEY_ID" \
            --region "$CURRENT_REGION" 2>/dev/null; then
            echo -e "${GREEN}✓ Deleted $KEY_ID${NC}"
        else
            echo -e "${RED}✗ Failed to delete $KEY_ID${NC}"
            FAILED=1
        fi
    done
fi
rm -f "$SCRIPT_DIR/.minted_bucket_reader_key"
echo ""

# Step 3: Detach AdministratorAccess from attach-self-user
echo -e "${YELLOW}Step 3: Detaching AdministratorAccess from $ATTACH_SELF_USER_NAME${NC}"
if aws iam list-attached-user-policies \
    --user-name "$ATTACH_SELF_USER_NAME" \
    --region "$CURRENT_REGION" \
    --query 'AttachedPolicies[*].PolicyArn' \
    --output text 2>/dev/null | grep -q "$ADMIN_POLICY_ARN"; then
    if aws iam detach-user-policy \
        --user-name "$ATTACH_SELF_USER_NAME" \
        --policy-arn "$ADMIN_POLICY_ARN" \
        --region "$CURRENT_REGION" 2>/dev/null; then
        echo -e "${GREEN}✓ Detached AdministratorAccess${NC}"
    else
        echo -e "${RED}✗ Failed to detach AdministratorAccess${NC}"
        FAILED=1
    fi
else
    echo -e "${YELLOW}AdministratorAccess not attached (may already be cleaned)${NC}"
fi
echo ""

# Step 4: Remove local demo marker
echo -e "${YELLOW}Step 4: Removing local demo marker${NC}"
rm -f "$SCRIPT_DIR/.demo_active"
echo -e "${GREEN}✓ Removed .demo_active (if present)${NC}\n"

if [ "$FAILED" -ne 0 ]; then
    echo -e "${RED}Cleanup finished with errors${NC}"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Deleted the demo-minted access key(s) on $BUCKET_READER_NAME (terraform key preserved)"
echo "- Detached AdministratorAccess from $ATTACH_SELF_USER_NAME"
echo "- Removed local marker file .demo_active (if present)"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and bucket) remains deployed.${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
