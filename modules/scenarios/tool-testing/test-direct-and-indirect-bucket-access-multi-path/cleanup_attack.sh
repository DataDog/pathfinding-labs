#!/bin/bash

# Cleanup script for test-direct-and-indirect-bucket-access-multi-path
# This script:
#   1. Reverts role-untrusted's trust policy back to its original ec2.amazonaws.com-only
#      state, undoing the iam:UpdateAssumeRolePolicy trust-policy bypass performed by
#      user-trustbypass during the demo.
#   2. Removes the test objects written to the bucket by each of the three principals.
#
# It preserves all Terraform-managed infrastructure (users, roles, bucket) so the
# scenario can be re-run.

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Direct and Indirect Bucket${NC}"
echo -e "${GREEN}Access Multi-Path Test${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Navigate to the Terraform root directory (4 levels up from a tool-testing scenario directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# Step 1: Get admin credentials, region, and scenario configuration from Terraform
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

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.tool_testing_test_direct_and_indirect_bucket_access_multi_path.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output for this scenario${NC}"
    exit 1
fi

ROLE_UNTRUSTED_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.role_untrusted_name')
BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.target_bucket_name')

export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_REGION="$CURRENT_REGION"
export AWS_DEFAULT_REGION="$CURRENT_REGION"
unset AWS_SESSION_TOKEN

echo "Region from Terraform: $CURRENT_REGION"
echo "role-untrusted:        $ROLE_UNTRUSTED_NAME"
echo "bucket:                $BUCKET_NAME"
echo -e "${GREEN}✓ Retrieved admin credentials and scenario configuration${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Safety restore: ensure helpful permissions deny policy is removed
source "$SCRIPT_DIR/../../../../scripts/lib/demo_permissions.sh"
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 2: Revert role-untrusted's trust policy back to its original state
echo -e "${YELLOW}Step 2: Reverting role-untrusted's trust policy to ec2.amazonaws.com-only${NC}"

if [ -z "$ROLE_UNTRUSTED_NAME" ] || [ "$ROLE_UNTRUSTED_NAME" == "null" ]; then
    echo -e "${YELLOW}Could not determine role-untrusted's name, skipping trust policy revert${NC}"
else
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

    if aws iam get-role --role-name "$ROLE_UNTRUSTED_NAME" &> /dev/null; then
        aws iam update-assume-role-policy \
            --role-name "$ROLE_UNTRUSTED_NAME" \
            --policy-document "$ORIGINAL_TRUST_POLICY"
        echo -e "${GREEN}✓ Restored role-untrusted's original trust policy (ec2.amazonaws.com only)${NC}"
    else
        echo -e "${YELLOW}Role $ROLE_UNTRUSTED_NAME not found (may already be destroyed)${NC}"
    fi
fi
echo ""

# Step 3: Remove test objects written to the bucket during the demo
echo -e "${YELLOW}Step 3: Removing test objects from the bucket${NC}"

if [ -z "$BUCKET_NAME" ] || [ "$BUCKET_NAME" == "null" ]; then
    echo -e "${YELLOW}Could not determine bucket name, skipping object cleanup${NC}"
else
    TEST_OBJECT_KEYS=(
        "dimp-test-direct.txt"
        "dimp-test-assumer.txt"
        "dimp-test-trustbypass.txt"
    )

    OBJECTS_REMOVED=0
    for KEY in "${TEST_OBJECT_KEYS[@]}"; do
        if aws s3api head-object --bucket "$BUCKET_NAME" --key "$KEY" --region "$CURRENT_REGION" &> /dev/null; then
            aws s3 rm "s3://$BUCKET_NAME/$KEY" --region "$CURRENT_REGION"
            echo -e "${GREEN}✓ Removed: s3://$BUCKET_NAME/$KEY${NC}"
            OBJECTS_REMOVED=$((OBJECTS_REMOVED + 1))
        else
            echo -e "${YELLOW}Note: s3://$BUCKET_NAME/$KEY not found (may already be deleted)${NC}"
        fi
    done
fi
echo ""

# Step 4: Remove local temporary files
echo -e "${YELLOW}Step 4: Removing local temporary files${NC}"
rm -f /tmp/dimp-test-direct.txt \
      /tmp/dimp-test-direct-readback.txt \
      /tmp/dimp-test-assumer.txt \
      /tmp/dimp-test-assumer-readback.txt \
      /tmp/dimp-test-trustbypass.txt \
      /tmp/dimp-test-trustbypass-readback.txt
echo -e "${GREEN}✓ Removed local temporary files${NC}\n"

# Final summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Summary:${NC}"
echo "  - role-untrusted's trust policy reverted to ec2.amazonaws.com-only"
echo "  - Test objects removed from s3://$BUCKET_NAME"
echo "  - Local temporary files removed"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, and bucket) remains deployed.${NC}"
echo "To remove all infrastructure, set the scenario flag to false and run terraform apply"
echo ""

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
