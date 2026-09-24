#!/bin/bash

# Cleanup script for test-s3-access-via-policy-attachment-type
# This script removes the test objects written to the target S3 bucket by
# each of the 4 test principals during the demo, and removes local temp
# files. No IAM policies, access keys, or trust policies are modified by
# this scenario, so the only artifacts to clean up are S3 objects and
# downloaded files.


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: S3 Access via Policy Attachment Type${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Navigate to the Terraform root directory (4 levels up from scenario directory)
TERRAFORM_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# Step 1: Get admin credentials and region from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd "$TERRAFORM_ROOT"

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

# Retrieve bucket name from the scenario's grouped output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.tool_testing_test_s3_access_via_policy_attachment_type.value // empty')
BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.target_bucket_name // empty')

export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_REGION="$CURRENT_REGION"
export AWS_DEFAULT_REGION="$CURRENT_REGION"
unset AWS_SESSION_TOKEN

echo "Region from Terraform: $CURRENT_REGION"
if [ -n "$BUCKET_NAME" ]; then
    echo "Bucket: $BUCKET_NAME"
fi
echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Source demo permissions library for safety restore
source "$SCRIPT_DIR/../../../../scripts/lib/demo_permissions.sh"

# Safety: remove any orphaned restriction policies
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 2: Remove test objects written to the bucket during the demo
echo -e "${YELLOW}Step 2: Removing test objects from S3 bucket${NC}"

if [ -z "$BUCKET_NAME" ]; then
    echo -e "${YELLOW}Warning: Could not determine bucket name from Terraform output, skipping S3 cleanup${NC}"
else
    OBJECTS=$(aws s3 ls "s3://$BUCKET_NAME/patn-test/" --region "$CURRENT_REGION" --recursive 2>/dev/null)
    if [ -n "$OBJECTS" ]; then
        aws s3 rm "s3://$BUCKET_NAME/patn-test/" \
            --region "$CURRENT_REGION" \
            --recursive
        echo -e "${GREEN}✓ Removed test objects under s3://$BUCKET_NAME/patn-test/${NC}"
    else
        echo -e "${YELLOW}No test objects found under patn-test/ (may already be cleaned)${NC}"
    fi
fi
echo ""

# Step 3: Remove local temporary files
echo -e "${YELLOW}Step 3: Removing temporary local files${NC}"

FILES_REMOVED=0
FILES_NOT_FOUND=0

for f in \
    "/tmp/patn-download-user-inline.txt" \
    "/tmp/patn-download-user-managed.txt" \
    "/tmp/patn-download-role-inline.txt" \
    "/tmp/patn-download-role-managed.txt"; do
    if [ -f "$f" ]; then
        rm -f "$f"
        echo -e "${GREEN}✓ Removed: $f${NC}"
        FILES_REMOVED=$((FILES_REMOVED + 1))
    else
        echo -e "${YELLOW}Note: $f not found (may already be deleted)${NC}"
        FILES_NOT_FOUND=$((FILES_NOT_FOUND + 1))
    fi
done

# Also clean up any leftover mktemp upload scratch files from the demo helper
LEFTOVER_UPLOADS=$(find /tmp -maxdepth 1 -name "patn-upload.*" -type f 2>/dev/null || true)
if [ -n "$LEFTOVER_UPLOADS" ]; then
    echo "$LEFTOVER_UPLOADS" | xargs rm -f
    echo -e "${GREEN}✓ Removed leftover upload scratch files${NC}"
fi

echo ""

# Final summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Summary:${NC}"
echo "  - Test objects removed from: s3://$BUCKET_NAME/patn-test/ (if present)"
echo "  - Local temp files removed: $FILES_REMOVED"
if [ $FILES_NOT_FOUND -gt 0 ]; then
    echo "  - Local temp files already absent: $FILES_NOT_FOUND"
fi
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo ""
echo -e "${YELLOW}Note:${NC} This scenario does not modify IAM policies, access keys,"
echo "or trust policies during the demo. All infrastructure (the 5 IAM"
echo "principals and the S3 bucket) remains deployed and unchanged."
echo "To remove all infrastructure, set the scenario flag to false and run terraform apply"
echo ""

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
