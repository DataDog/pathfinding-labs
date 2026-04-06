#!/bin/bash

# Cleanup script for iam:PassRole + glue:CreateSession + glue:RunStatement privilege escalation demo
# This script removes the AdministratorAccess policy and Glue sessions created during the demo


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Source demo permissions library for safety restore
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Safety: remove any orphaned restriction policies
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

# Configuration
STARTING_USER="pl-prod-glue-007-to-admin-starting-user"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + Glue CreateSession + RunStatement Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Go to project root

# Get admin cleanup user credentials from root terraform output
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup credentials in terraform output${NC}"
    echo "Make sure the admin cleanup user is deployed"
    exit 1
fi

# Set admin credentials
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
unset AWS_SESSION_TOKEN

echo -e "${GREEN}OK Retrieved admin credentials${NC}\n"

# Get region from Terraform
CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$CURRENT_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    CURRENT_REGION="us-east-1"
fi

export AWS_REGION=$CURRENT_REGION

echo "Region from Terraform: $CURRENT_REGION"

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"

cd - > /dev/null  # Return to scenario directory
echo ""

# Step 2: Detach AdministratorAccess policy from starting user
echo -e "${YELLOW}Step 2: Detaching AdministratorAccess policy from starting user${NC}"
echo "User: $STARTING_USER"

# Check if the policy is attached
if aws iam list-attached-user-policies \
    --user-name "$STARTING_USER" \
    --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`]' \
    --output text | grep -q "AdministratorAccess"; then

    echo "Found AdministratorAccess policy attached to user"
    aws iam detach-user-policy \
        --user-name "$STARTING_USER" \
        --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"

    echo -e "${GREEN}OK Detached AdministratorAccess policy from $STARTING_USER${NC}"
else
    echo -e "${YELLOW}AdministratorAccess policy not attached to user (may already be detached)${NC}"
fi
echo ""

# Step 3: Find and delete Glue Interactive Sessions created by the demo
echo -e "${YELLOW}Step 3: Finding and deleting demo Glue Interactive Sessions${NC}"
DEMO_SESSION_PREFIX="pl-glue-007-demo-session-"

echo "Searching for Glue sessions with prefix: $DEMO_SESSION_PREFIX"
echo "Region: $CURRENT_REGION"

# List all sessions matching our prefix
# Note: Glue list-sessions returns all sessions, we filter by Id prefix
GLUE_SESSIONS=$(aws glue list-sessions \
    --region "$CURRENT_REGION" \
    --query "Sessions[?starts_with(Id, '${DEMO_SESSION_PREFIX}')].Id" \
    --output text 2>/dev/null || echo "")

if [ -n "$GLUE_SESSIONS" ]; then
    echo "Found Glue sessions to delete:"
    echo "$GLUE_SESSIONS"
    echo ""

    # Delete each session
    for SESSION_ID in $GLUE_SESSIONS; do
        echo "Deleting Glue session: $SESSION_ID"

        # First try to stop the session if it's running
        SESSION_STATUS=$(aws glue get-session \
            --region "$CURRENT_REGION" \
            --id "$SESSION_ID" \
            --query 'Session.Status' \
            --output text 2>/dev/null || echo "UNKNOWN")

        if [ "$SESSION_STATUS" = "READY" ] || [ "$SESSION_STATUS" = "PROVISIONING" ]; then
            echo "  Stopping session first (status: $SESSION_STATUS)..."
            aws glue stop-session \
                --region "$CURRENT_REGION" \
                --id "$SESSION_ID" 2>/dev/null || true
            # Wait a moment for stop to take effect
            sleep 5
        fi

        # Delete the session
        aws glue delete-session \
            --region "$CURRENT_REGION" \
            --id "$SESSION_ID" 2>/dev/null || true

        echo -e "${GREEN}OK Deleted session: $SESSION_ID${NC}"
    done
else
    echo -e "${YELLOW}No demo Glue sessions found (may already be deleted)${NC}"
fi
echo ""

# Step 4: Verify cleanup
echo -e "${YELLOW}Step 4: Verifying cleanup${NC}"

# Check that AdministratorAccess is detached
if aws iam list-attached-user-policies \
    --user-name "$STARTING_USER" \
    --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`]' \
    --output text | grep -q "AdministratorAccess"; then
    echo -e "${YELLOW}Warning: AdministratorAccess still attached to $STARTING_USER${NC}"
else
    echo -e "${GREEN}OK AdministratorAccess successfully detached from user${NC}"
fi

# Check for remaining Glue sessions
REMAINING_SESSIONS=$(aws glue list-sessions \
    --region "$CURRENT_REGION" \
    --query "Sessions[?starts_with(Id, '${DEMO_SESSION_PREFIX}') && Status != 'STOPPED'].Id" \
    --output text 2>/dev/null || echo "")

if [ -n "$REMAINING_SESSIONS" ]; then
    echo -e "${YELLOW}Warning: Some Glue sessions still exist: $REMAINING_SESSIONS${NC}"
else
    echo -e "${GREEN}OK All demo Glue sessions deleted or stopped${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess policy from starting user"
echo "- Deleted Glue Interactive Sessions with prefix: $DEMO_SESSION_PREFIX"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
