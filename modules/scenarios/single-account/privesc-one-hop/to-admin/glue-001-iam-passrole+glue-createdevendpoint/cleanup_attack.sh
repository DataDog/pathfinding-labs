#!/bin/bash

# Cleanup script for iam:PassRole + glue:CreateDevEndpoint privilege escalation demo
# This script removes the Glue Dev Endpoint and SSH keys created during the demo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
DEV_ENDPOINT_NAME="pl-glue-001-demo-endpoint"
SSH_KEY_PATH="/tmp/pl-glue-001-demo-key"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Glue CreateDevEndpoint Demo Cleanup${NC}"
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

# Step 2: Delete the Glue Dev Endpoint
echo -e "${YELLOW}Step 2: Deleting Glue Dev Endpoint${NC}"
echo "Endpoint name: $DEV_ENDPOINT_NAME"
echo "Region: $CURRENT_REGION"
echo ""

# Check if the endpoint exists
ENDPOINT_EXISTS=$(aws glue get-dev-endpoint \
    --endpoint-name "$DEV_ENDPOINT_NAME" \
    --query 'DevEndpoint.EndpointName' \
    --output text 2>/dev/null || echo "")

if [ -n "$ENDPOINT_EXISTS" ] && [ "$ENDPOINT_EXISTS" != "None" ]; then
    echo "Found Glue Dev Endpoint: $DEV_ENDPOINT_NAME"

    # Get current status
    ENDPOINT_STATUS=$(aws glue get-dev-endpoint \
        --endpoint-name "$DEV_ENDPOINT_NAME" \
        --query 'DevEndpoint.Status' \
        --output text)
    echo "Current status: $ENDPOINT_STATUS"

    # Delete the endpoint
    echo "Initiating deletion..."
    aws glue delete-dev-endpoint \
        --endpoint-name "$DEV_ENDPOINT_NAME"

    echo -e "${GREEN}✓ Deletion initiated for Dev Endpoint: $DEV_ENDPOINT_NAME${NC}"
    echo -e "${BLUE}Note: Endpoint deletion may take a few minutes to complete${NC}"

    # Wait for deletion to complete
    echo "Waiting for endpoint deletion to complete..."
    MAX_WAIT=20  # 20 checks * 15 seconds = 5 minutes max wait
    WAIT_COUNT=0

    while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
        ENDPOINT_CHECK=$(aws glue get-dev-endpoint \
            --endpoint-name "$DEV_ENDPOINT_NAME" \
            --query 'DevEndpoint.Status' \
            --output text 2>/dev/null || echo "DELETED")

        if [ "$ENDPOINT_CHECK" = "DELETED" ]; then
            echo -e "${GREEN}✓ Dev Endpoint successfully deleted${NC}"
            break
        fi

        echo "Status: $ENDPOINT_CHECK (waiting...)"
        sleep 15
        WAIT_COUNT=$((WAIT_COUNT + 1))
    done

    if [ "$ENDPOINT_CHECK" != "DELETED" ]; then
        echo -e "${YELLOW}⚠ Endpoint deletion still in progress${NC}"
        echo "The endpoint will continue deleting in the background"
    fi
else
    echo -e "${YELLOW}Glue Dev Endpoint $DEV_ENDPOINT_NAME not found (may already be deleted)${NC}"
fi
echo ""

# Step 3: Clean up SSH keys
echo -e "${YELLOW}Step 3: Cleaning up SSH key files${NC}"

FILES_CLEANED=0
if [ -f "$SSH_KEY_PATH" ]; then
    rm -f "$SSH_KEY_PATH"
    echo "Removed: $SSH_KEY_PATH"
    FILES_CLEANED=$((FILES_CLEANED + 1))
fi

if [ -f "${SSH_KEY_PATH}.pub" ]; then
    rm -f "${SSH_KEY_PATH}.pub"
    echo "Removed: ${SSH_KEY_PATH}.pub"
    FILES_CLEANED=$((FILES_CLEANED + 1))
fi

if [ $FILES_CLEANED -eq 0 ]; then
    echo -e "${YELLOW}No SSH key files found (may already be deleted)${NC}"
else
    echo -e "${GREEN}✓ Cleaned up $FILES_CLEANED SSH key file(s)${NC}"
fi
echo ""

# Step 4: Verify cleanup
echo -e "${YELLOW}Step 4: Verifying cleanup${NC}"

# Check that the endpoint no longer exists
FINAL_CHECK=$(aws glue get-dev-endpoint \
    --endpoint-name "$DEV_ENDPOINT_NAME" \
    --query 'DevEndpoint.EndpointName' \
    --output text 2>/dev/null || echo "")

if [ -z "$FINAL_CHECK" ] || [ "$FINAL_CHECK" = "None" ]; then
    echo -e "${GREEN}✓ Glue Dev Endpoint successfully deleted${NC}"
else
    FINAL_STATUS=$(aws glue get-dev-endpoint \
        --endpoint-name "$DEV_ENDPOINT_NAME" \
        --query 'DevEndpoint.Status' \
        --output text 2>/dev/null || echo "UNKNOWN")

    if [ "$FINAL_STATUS" = "DELETING" ]; then
        echo -e "${YELLOW}⚠ Dev Endpoint is still deleting (this is normal)${NC}"
        echo "The endpoint will be fully removed shortly"
    else
        echo -e "${YELLOW}⚠ Warning: Dev Endpoint $DEV_ENDPOINT_NAME still exists with status: $FINAL_STATUS${NC}"
    fi
fi

# Check that SSH keys are cleaned up
FILES_REMAINING=false
if [ -f "$SSH_KEY_PATH" ] || [ -f "${SSH_KEY_PATH}.pub" ]; then
    echo -e "${YELLOW}⚠ Warning: Some SSH key files still exist${NC}"
    FILES_REMAINING=true
else
    echo -e "${GREEN}✓ All SSH key files cleaned up${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Deleted Glue Dev Endpoint: $DEV_ENDPOINT_NAME"
echo "- Cleaned up SSH key files"
echo ""
echo -e "${GREEN}Charges for the Glue Dev Endpoint have stopped${NC}"
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
