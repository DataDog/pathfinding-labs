#!/bin/bash

# Cleanup script for iam:CreatePolicyVersion privilege escalation demo
# This script removes the malicious policy version created during the demo

set -e

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_ROLE="pl-prod-iam-001-to-admin-starting-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM CreatePolicyVersion Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials from Terraform output
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Go to project root

# Get admin cleanup user credentials from root terraform output
ADMIN_ACCESS_KEY=$(OTEL_TRACES_EXPORTER= terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(OTEL_TRACES_EXPORTER= terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup credentials in terraform output${NC}"
    echo "Make sure the admin cleanup user is deployed"
    exit 1
fi

# Get policy ARN from scenario output
MODULE_OUTPUT=$(OTEL_TRACES_EXPORTER= terraform output -json 2>/dev/null | jq -r '.single_account_privesc_self_escalation_to_admin_iam_001_iam_createpolicyversion.value // empty')
POLICY_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.policy_arn')

if [ -z "$POLICY_ARN" ] || [ "$POLICY_ARN" == "null" ]; then
    echo -e "${RED}Error: Could not find policy ARN in terraform output${NC}"
    exit 1
fi

# Set admin credentials
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"

echo -e "${GREEN}✓ Retrieved admin cleanup credentials${NC}"
echo "Policy ARN: $POLICY_ARN"
echo ""

cd - > /dev/null  # Return to scenario directory

# Step 2: Verify admin access
echo -e "${YELLOW}Step 2: Verifying admin access${NC}"
ADMIN_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $ADMIN_IDENTITY"
echo -e "${GREEN}✓ Verified admin access${NC}\n"

# Step 3: List current policy versions
echo -e "${YELLOW}Step 3: Checking current policy versions${NC}"
echo "Current policy versions:"
aws iam list-policy-versions --policy-arn "$POLICY_ARN"

# Get all policy versions
ALL_VERSIONS=$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" --query 'Versions[].VersionId' --output text)
VERSION_COUNT=$(echo "$ALL_VERSIONS" | wc -w)

echo "Found $VERSION_COUNT policy version(s)"
echo ""

# Step 4: Find and restore the original version
echo -e "${YELLOW}Step 4: Finding original policy version${NC}"

# Get the oldest version (first created)
OLDEST_VERSION=$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" --query 'sort_by(Versions, &CreateDate)[0].VersionId' --output text)
echo "Oldest policy version: $OLDEST_VERSION"

# Check if it's already the default
DEFAULT_VERSION=$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" --query 'Versions[?IsDefaultVersion==`true`].VersionId' --output text)
echo "Current default version: $DEFAULT_VERSION"

if [ "$OLDEST_VERSION" != "$DEFAULT_VERSION" ]; then
    echo "Setting oldest version as default..."
    aws iam set-default-policy-version \
        --policy-arn "$POLICY_ARN" \
        --version-id "$OLDEST_VERSION"
    echo -e "${GREEN}✓ Set oldest version as default${NC}\n"
else
    echo -e "${GREEN}✓ Oldest version is already default${NC}\n"
fi

# Step 5: Delete all other versions
echo -e "${YELLOW}Step 5: Deleting malicious policy versions${NC}"

for version in $ALL_VERSIONS; do
    if [ "$version" != "$OLDEST_VERSION" ]; then
        echo "Deleting policy version: $version"
        aws iam delete-policy-version \
            --policy-arn "$POLICY_ARN" \
            --version-id "$version"
        echo -e "${GREEN}✓ Deleted version: $version${NC}"
    fi
done

echo ""

# Step 6: Verify cleanup
echo -e "${YELLOW}Step 6: Verifying cleanup${NC}"
REMAINING_VERSIONS=$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" --query 'Versions[].VersionId' --output text)
REMAINING_COUNT=$(echo "$REMAINING_VERSIONS" | wc -w)

if [ "$REMAINING_COUNT" -eq 1 ]; then
    echo -e "${GREEN}✓ Only one policy version remains${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Multiple versions still exist${NC}"
fi

echo "Remaining version(s): $REMAINING_VERSIONS"
echo ""

# Show the default policy document
echo "Current default policy document:"
DEFAULT_VERSION=$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" --query 'Versions[?IsDefaultVersion==`true`].VersionId' --output text)
aws iam get-policy-version --policy-arn "$POLICY_ARN" --version-id "$DEFAULT_VERSION" --query 'PolicyVersion.Document' --output json | jq '.'

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo "The policy has been restored to its original version"
echo ""

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
