#!/bin/bash

# Cleanup script for test-s3-read-write-delete-permission-edges
#
# This script removes all test/staged objects written under rwd-test/ during
# the demo, removes local temp files, and verifies the pre-seeded object
# used for GetObject tests is still present (re-seeding a placeholder copy
# if it is somehow missing, so the scenario remains re-runnable). No IAM
# policies, access keys, or trust policies are modified by this scenario,
# so infrastructure (the 9 IAM principals and the S3 bucket) is preserved.


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: S3 Read/Write/Delete Permission Edges${NC}"
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

# Retrieve bucket name and seed object key from the scenario's grouped output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.tool_testing_test_s3_read_write_delete_permission_edges.value // empty')
BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.target_bucket_name // empty')
SEED_OBJECT_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.seed_object_key // empty')

export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_REGION="$CURRENT_REGION"
export AWS_DEFAULT_REGION="$CURRENT_REGION"
unset AWS_SESSION_TOKEN

echo "Region from Terraform: $CURRENT_REGION"
if [ -n "$BUCKET_NAME" ]; then
    echo "Bucket: $BUCKET_NAME"
fi
if [ -n "$SEED_OBJECT_KEY" ]; then
    echo "Seed object key: $SEED_OBJECT_KEY"
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

# Step 2: Remove test objects and staged delete-target objects from the bucket
echo -e "${YELLOW}Step 2: Removing test objects from S3 bucket${NC}"

if [ -z "$BUCKET_NAME" ]; then
    echo -e "${YELLOW}Warning: Could not determine bucket name from Terraform output, skipping S3 cleanup${NC}"
else
    OBJECTS=$(aws s3 ls "s3://$BUCKET_NAME/rwd-test/" --region "$CURRENT_REGION" --recursive 2>/dev/null)
    if [ -n "$OBJECTS" ]; then
        aws s3 rm "s3://$BUCKET_NAME/rwd-test/" \
            --region "$CURRENT_REGION" \
            --recursive
        echo -e "${GREEN}✓ Removed test objects under s3://$BUCKET_NAME/rwd-test/${NC}"
    else
        echo -e "${YELLOW}No test objects found under rwd-test/ (may already be cleaned)${NC}"
    fi
fi
echo ""

# Step 3: Verify the pre-seeded object still exists; re-seed if it was
# somehow deleted during testing (should not happen under normal demo
# execution, since the demo never targets the seed object for delete tests
# expected to succeed - this is a defensive safety net only).
echo -e "${YELLOW}Step 3: Verifying pre-seeded object is intact${NC}"

if [ -z "$BUCKET_NAME" ] || [ -z "$SEED_OBJECT_KEY" ]; then
    echo -e "${YELLOW}Warning: Could not determine bucket name or seed object key, skipping seed verification${NC}"
else
    if aws s3 ls "s3://$BUCKET_NAME/$SEED_OBJECT_KEY" --region "$CURRENT_REGION" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Seed object s3://$BUCKET_NAME/$SEED_OBJECT_KEY is present${NC}"
    else
        echo -e "${YELLOW}Seed object missing - re-seeding a placeholder copy so the scenario remains re-runnable${NC}"
        PLACEHOLDER_FILE=$(mktemp /tmp/rwd-reseed.XXXXXX)
        echo "This is the pre-seeded object for testing S3 permission edge cases." > "$PLACEHOLDER_FILE"
        aws s3 cp "$PLACEHOLDER_FILE" "s3://$BUCKET_NAME/$SEED_OBJECT_KEY" \
            --region "$CURRENT_REGION" > /dev/null 2>&1
        rm -f "$PLACEHOLDER_FILE"
        echo -e "${GREEN}✓ Re-seeded placeholder object${NC}"
        echo -e "${YELLOW}Note: run 'terraform apply' to restore the exact original seed object content if it differs${NC}"
    fi
fi
echo ""

# Step 4: Remove local temporary files
echo -e "${YELLOW}Step 4: Removing temporary local files${NC}"

FILES_REMOVED=0

LEFTOVER_DOWNLOADS=$(find /tmp -maxdepth 1 -name "rwd-get-*.txt" -type f 2>/dev/null || true)
if [ -n "$LEFTOVER_DOWNLOADS" ]; then
    echo "$LEFTOVER_DOWNLOADS" | while read -r f; do
        rm -f "$f"
        echo -e "${GREEN}✓ Removed: $f${NC}"
    done
    FILES_REMOVED=$(echo "$LEFTOVER_DOWNLOADS" | wc -l | tr -d ' ')
else
    echo -e "${YELLOW}No downloaded test files found under /tmp/rwd-get-*.txt${NC}"
fi

# Also clean up any leftover mktemp upload/stage scratch files from the demo helper
LEFTOVER_UPLOADS=$(find /tmp -maxdepth 1 \( -name "rwd-upload-*" -o -name "rwd-stage.*" -o -name "rwd-reseed.*" \) -type f 2>/dev/null || true)
if [ -n "$LEFTOVER_UPLOADS" ]; then
    echo "$LEFTOVER_UPLOADS" | xargs rm -f
    echo -e "${GREEN}✓ Removed leftover upload/stage scratch files${NC}"
fi

echo ""

# Final summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Summary:${NC}"
echo "  - Test objects removed from: s3://$BUCKET_NAME/rwd-test/ (if present)"
echo "  - Pre-seeded object verified/re-seeded: s3://$BUCKET_NAME/$SEED_OBJECT_KEY"
echo "  - Local temp files removed: $FILES_REMOVED"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo ""
echo -e "${YELLOW}Note:${NC} This scenario does not modify IAM policies, access keys,"
echo "or trust policies during the demo. All infrastructure (the 9 IAM"
echo "principals and the S3 bucket) remains deployed and unchanged."
echo "To remove all infrastructure, set the scenario flag to false and run terraform apply"
echo ""

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
