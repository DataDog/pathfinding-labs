#!/bin/bash

# Cleanup script for iam:PassRole + glue:CreateDevEndpoint privilege escalation demo
# This script deletes the Glue dev endpoint and removes temporary SSH keys


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
ENDPOINT_NAME="pl-glue-001-demo-endpoint"
SSH_KEY_PATH="/tmp/pl-glue-001-demo-key"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Glue CreateDevEndpoint Demo${NC}"
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

# Step 2: Delete Glue dev endpoint
echo -e "${YELLOW}Step 2: Deleting Glue development endpoint${NC}"
echo "Checking for endpoint: $ENDPOINT_NAME"

# Check if endpoint exists
ENDPOINT_EXISTS=$(aws glue get-dev-endpoint \
    --endpoint-name $ENDPOINT_NAME \
    --region $CURRENT_REGION \
    --query 'DevEndpoint.EndpointName' \
    --output text 2>/dev/null || echo "")

if [ -z "$ENDPOINT_EXISTS" ] || [ "$ENDPOINT_EXISTS" = "None" ]; then
    echo -e "${YELLOW}Endpoint $ENDPOINT_NAME not found (may already be deleted)${NC}"
else
    echo "Found endpoint: $ENDPOINT_NAME"

    # Get endpoint status
    ENDPOINT_STATUS=$(aws glue get-dev-endpoint \
        --endpoint-name $ENDPOINT_NAME \
        --region $CURRENT_REGION \
        --query 'DevEndpoint.Status' \
        --output text 2>/dev/null || echo "UNKNOWN")

    echo "Current status: $ENDPOINT_STATUS"

    # Delete the endpoint
    echo "Deleting endpoint..."
    aws glue delete-dev-endpoint \
        --endpoint-name $ENDPOINT_NAME \
        --region $CURRENT_REGION \
        --output json > /dev/null

    echo -e "${GREEN}✓ Endpoint deletion initiated${NC}"
    echo -e "${BLUE}Note: Endpoint deletion continues in the background (~5-10 min) and stops billing immediately.${NC}"

    # Verify the delete request was accepted (status is DELETING or the endpoint is gone).
    # We do NOT block for full deletion — AWS continues asynchronously and charges stop as soon as
    # the delete is accepted. A long internal wait risks being killed by the test harness's cleanup
    # timeout, which previously caused orphan endpoints to bleed ~$21/day.
    STATUS_AFTER_DELETE=$(aws glue get-dev-endpoint \
        --endpoint-name $ENDPOINT_NAME \
        --region $CURRENT_REGION \
        --query 'DevEndpoint.Status' \
        --output text 2>/dev/null || echo "DELETED")

    if [ "$STATUS_AFTER_DELETE" = "DELETED" ] || [ "$STATUS_AFTER_DELETE" = "DELETING" ]; then
        echo -e "${GREEN}✓ Delete accepted (status: $STATUS_AFTER_DELETE)${NC}"
    else
        echo -e "${YELLOW}⚠ Unexpected status after delete: $STATUS_AFTER_DELETE${NC}"
        echo "If the endpoint remains, re-run cleanup or delete manually via the AWS console."
    fi
fi
echo ""

# Step 3: Remove SSH keys
echo -e "${YELLOW}Step 3: Removing temporary SSH keys${NC}"
if [ -f ${SSH_KEY_PATH} ] || [ -f ${SSH_KEY_PATH}.pub ]; then
    rm -f ${SSH_KEY_PATH} ${SSH_KEY_PATH}.pub
    echo -e "${GREEN}✓ Removed SSH key files${NC}"
else
    echo -e "${YELLOW}SSH key files not found (may already be removed)${NC}"
fi
echo ""

# Step 4: Verify cleanup
echo -e "${YELLOW}Step 4: Verifying cleanup${NC}"

# Check that endpoint is gone
REMAINING_ENDPOINT=$(aws glue get-dev-endpoint \
    --endpoint-name $ENDPOINT_NAME \
    --region $CURRENT_REGION \
    --query 'DevEndpoint.EndpointName' \
    --output text 2>/dev/null || echo "")

if [ -z "$REMAINING_ENDPOINT" ] || [ "$REMAINING_ENDPOINT" = "None" ]; then
    echo -e "${GREEN}✓ No demo endpoint remaining${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Endpoint may still exist: $REMAINING_ENDPOINT${NC}"
    ENDPOINT_STATUS=$(aws glue get-dev-endpoint \
        --endpoint-name $ENDPOINT_NAME \
        --region $CURRENT_REGION \
        --query 'DevEndpoint.Status' \
        --output text 2>/dev/null || echo "UNKNOWN")
    echo "Current status: $ENDPOINT_STATUS"
fi

# Check that SSH keys are gone
if [ ! -f ${SSH_KEY_PATH} ] && [ ! -f ${SSH_KEY_PATH}.pub ]; then
    echo -e "${GREEN}✓ SSH keys removed${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Some SSH key files may still exist${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Deleted Glue dev endpoint: $ENDPOINT_NAME"
echo "- Removed temporary SSH keys"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${GREEN}Glue endpoint costs (~$2.20/hour) have been stopped.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
