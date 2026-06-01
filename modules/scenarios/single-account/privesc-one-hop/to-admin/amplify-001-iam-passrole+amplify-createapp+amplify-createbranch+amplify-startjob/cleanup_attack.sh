#!/bin/bash
set -e

# Cleanup script for iam:PassRole + amplify:CreateApp + amplify:CreateBranch + amplify:StartJob privilege escalation demo
# This script detaches AdministratorAccess from the starting user, deletes the Amplify app,
# and cleans up local temporary files. The CodeCommit repo is managed by Terraform and is NOT deleted.

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-amplify-001-to-admin-starting-user"
APP_NAME="pl-prod-amplify-001-to-admin-app"
CLONE_DIR="/tmp/amplify-001-exploit-repo"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: PassRole + Amplify CreateApp + CreateBranch + StartJob${NC}"
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

# Source demo permissions library
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Safety: remove any orphaned restriction policies
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 2: Detach AdministratorAccess from starting user
echo -e "${YELLOW}Step 2: Detaching AdministratorAccess from starting user${NC}"
echo "User: $STARTING_USER"

ADMIN_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

if aws iam list-attached-user-policies --user-name "$STARTING_USER" --query "AttachedPolicies[?PolicyArn=='$ADMIN_POLICY_ARN'].PolicyName" --output text 2>/dev/null | grep -q "AdministratorAccess"; then
    aws iam detach-user-policy \
        --user-name "$STARTING_USER" \
        --policy-arn "$ADMIN_POLICY_ARN"
    echo -e "${GREEN}✓ Detached AdministratorAccess from $STARTING_USER${NC}"
else
    echo -e "${YELLOW}AdministratorAccess not attached to $STARTING_USER (may already be detached)${NC}"
fi
echo ""

# Step 3: Find and delete Amplify apps
echo -e "${YELLOW}Step 3: Finding and deleting Amplify apps${NC}"
echo "Looking for apps matching: $APP_NAME"

# List all Amplify apps and find ours by name
APP_LIST=$(aws amplify list-apps \
    --region "$CURRENT_REGION" \
    --query "apps[?name=='$APP_NAME']" \
    --output json 2>/dev/null || echo "[]")

if [ -n "$APP_LIST" ] && [ "$APP_LIST" != "[]" ] && [ "$APP_LIST" != "null" ]; then
    for APP_ID in $(echo "$APP_LIST" | jq -r '.[].appId'); do
        echo "Found Amplify app: $APP_ID"
        echo "Deleting Amplify app: $APP_ID (this also deletes branches and jobs)"

        if aws amplify delete-app \
            --app-id "$APP_ID" \
            --region "$CURRENT_REGION" 2>/dev/null; then
            echo -e "${GREEN}✓ Deleted Amplify app: $APP_ID${NC}"
        else
            echo -e "${YELLOW}⚠ Could not delete Amplify app $APP_ID (may need manual cleanup)${NC}"
        fi
    done
else
    echo -e "${YELLOW}No Amplify apps found matching: $APP_NAME (may already be deleted)${NC}"
fi
echo ""

# Step 4: Clean up local temporary files
echo -e "${YELLOW}Step 4: Cleaning up local temporary files${NC}"

if [ -d "$CLONE_DIR" ]; then
    rm -rf "$CLONE_DIR"
    echo "Removed: $CLONE_DIR"
else
    echo "No local clone directory found"
fi

echo -e "${GREEN}✓ Cleaned up local files${NC}"
echo ""

# Step 5: Verify cleanup
echo -e "${YELLOW}Step 5: Verifying cleanup${NC}"

# Check that AdministratorAccess is detached
if aws iam list-attached-user-policies --user-name "$STARTING_USER" --query "AttachedPolicies[?PolicyArn=='$ADMIN_POLICY_ARN'].PolicyName" --output text 2>/dev/null | grep -q "AdministratorAccess"; then
    echo -e "${YELLOW}⚠ Warning: AdministratorAccess still attached to $STARTING_USER${NC}"
else
    echo -e "${GREEN}✓ AdministratorAccess successfully detached from $STARTING_USER${NC}"
fi

# Check that Amplify apps are deleted
REMAINING_APPS=$(aws amplify list-apps \
    --region "$CURRENT_REGION" \
    --query "apps[?name=='$APP_NAME'].appId" \
    --output text 2>/dev/null || echo "")

if [ -z "$REMAINING_APPS" ] || [ "$REMAINING_APPS" == "None" ]; then
    echo -e "${GREEN}✓ All Amplify apps cleaned up${NC}"
else
    echo -e "${YELLOW}⚠ Some Amplify apps still exist: $REMAINING_APPS${NC}"
fi

# Check local files
if [ -d "$CLONE_DIR" ]; then
    echo -e "${YELLOW}⚠ Warning: Local clone directory still exists: $CLONE_DIR${NC}"
else
    echo -e "${GREEN}✓ Local temporary files cleaned up${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess from $STARTING_USER"
echo "- Deleted Amplify app(s) (including branches and jobs)"
echo "- Cleaned up local temporary files"
echo "- CodeCommit repository preserved (managed by Terraform)"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, and CodeCommit repo) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
