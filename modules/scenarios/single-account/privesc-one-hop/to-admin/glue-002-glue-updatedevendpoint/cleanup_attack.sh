#!/bin/bash

# Cleanup script for glue:UpdateDevEndpoint privilege escalation demo
# This script removes the attacker's SSH key from the endpoint (does NOT delete the endpoint)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SSH_KEY_PATH="/tmp/pl-glue-002-updatede-key"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Glue UpdateDevEndpoint Demo Cleanup${NC}"
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

# Get the endpoint name from the scenario output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_glue_002_glue_updatedevendpoint.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output for scenario${NC}"
    echo "Make sure the scenario is deployed"
    exit 1
fi

DEV_ENDPOINT_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.dev_endpoint_name')

if [ "$DEV_ENDPOINT_NAME" == "null" ] || [ -z "$DEV_ENDPOINT_NAME" ]; then
    echo -e "${RED}Error: Could not extract endpoint name from terraform output${NC}"
    exit 1
fi

# Set admin credentials
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_REGION="$CURRENT_REGION"
unset AWS_SESSION_TOKEN

echo "Region from Terraform: $CURRENT_REGION"
echo "Target Endpoint: $DEV_ENDPOINT_NAME"
echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 2: Get the attacker's SSH public key from local file
echo -e "${YELLOW}Step 2: Identifying SSH key to remove${NC}"

if [ -f "${SSH_KEY_PATH}.pub" ]; then
    # Extract just the key part (not the comment)
    SSH_PUBLIC_KEY=$(cat "${SSH_KEY_PATH}.pub" | awk '{print $1 " " $2}')
    echo "Found local SSH public key file"
    echo "Key fingerprint: $(ssh-keygen -lf "${SSH_KEY_PATH}.pub" 2>/dev/null | awk '{print $2}')"
else
    echo -e "${YELLOW}⚠ Warning: Local SSH public key file not found at ${SSH_KEY_PATH}.pub${NC}"
    echo "Will attempt to remove all non-Terraform public keys from the endpoint"
    SSH_PUBLIC_KEY=""
fi
echo ""

# Step 3: Get current public keys on the endpoint
echo -e "${YELLOW}Step 3: Retrieving current public keys from dev endpoint${NC}"
echo "Endpoint: $DEV_ENDPOINT_NAME"
echo ""

# Check if the endpoint exists and is accessible
ENDPOINT_EXISTS=$(aws glue get-dev-endpoint \
    --endpoint-name "$DEV_ENDPOINT_NAME" \
    --region "$CURRENT_REGION" \
    --query 'DevEndpoint.EndpointName' \
    --output text 2>/dev/null || echo "")

if [ -z "$ENDPOINT_EXISTS" ] || [ "$ENDPOINT_EXISTS" = "None" ]; then
    echo -e "${YELLOW}Dev endpoint $DEV_ENDPOINT_NAME not found (may already be deleted)${NC}"
    echo "Skipping SSH key removal"
else
    # Get current public keys
    CURRENT_KEYS=$(aws glue get-dev-endpoint \
        --endpoint-name "$DEV_ENDPOINT_NAME" \
        --region "$CURRENT_REGION" \
        --query 'DevEndpoint.PublicKeys' \
        --output json 2>/dev/null)

    if [ -z "$CURRENT_KEYS" ] || [ "$CURRENT_KEYS" = "null" ] || [ "$CURRENT_KEYS" = "[]" ]; then
        echo -e "${YELLOW}No public keys found on endpoint (may already be cleaned up)${NC}"
    else
        echo "Current public keys on endpoint:"
        echo "$CURRENT_KEYS" | jq -r '.[]' | while read -r key; do
            # Show just the key type and first few characters
            echo "  - $(echo $key | awk '{print $1}') ${key:0:50}..."
        done
        echo ""

        # Step 4: Remove the attacker's SSH key
        echo -e "${YELLOW}Step 4: Removing attacker's SSH key from endpoint${NC}"

        if [ -n "$SSH_PUBLIC_KEY" ]; then
            echo "Removing specific key added during demo..."

            # Update endpoint to delete the specific public key
            aws glue update-dev-endpoint \
                --endpoint-name "$DEV_ENDPOINT_NAME" \
                --region "$CURRENT_REGION" \
                --delete-public-keys "$SSH_PUBLIC_KEY" \
                --output json > /dev/null 2>&1

            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ Successfully removed SSH key from endpoint${NC}"
            else
                echo -e "${YELLOW}⚠ Warning: Could not remove specific key (it may not exist on endpoint)${NC}"
                echo "This is normal if the key was already removed or cleanup was run multiple times"
            fi
        else
            echo -e "${YELLOW}⚠ No specific key to remove (local key file not found)${NC}"
            echo "Note: The endpoint still has the keys that were present"
            echo "If you manually added keys, you may need to remove them via AWS Console"
        fi
    fi
fi
echo ""

# Step 5: Clean up SSH key files
echo -e "${YELLOW}Step 5: Cleaning up local SSH key files${NC}"

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

# Step 6: Verify cleanup
echo -e "${YELLOW}Step 6: Verifying cleanup${NC}"

# Check that SSH keys are cleaned up
FILES_REMAINING=false
if [ -f "$SSH_KEY_PATH" ] || [ -f "${SSH_KEY_PATH}.pub" ]; then
    echo -e "${YELLOW}⚠ Warning: Some SSH key files still exist${NC}"
    FILES_REMAINING=true
else
    echo -e "${GREEN}✓ All local SSH key files cleaned up${NC}"
fi

# Verify endpoint still exists (it should - it's infrastructure)
if [ -n "$ENDPOINT_EXISTS" ] && [ "$ENDPOINT_EXISTS" != "None" ]; then
    ENDPOINT_STATUS=$(aws glue get-dev-endpoint \
        --endpoint-name "$DEV_ENDPOINT_NAME" \
        --region "$CURRENT_REGION" \
        --query 'DevEndpoint.Status' \
        --output text 2>/dev/null || echo "UNKNOWN")

    echo -e "${GREEN}✓ Dev endpoint still exists (status: $ENDPOINT_STATUS)${NC}"
    echo "  This is correct - the endpoint is infrastructure, not an attack artifact"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Removed attacker's SSH key from endpoint: $DEV_ENDPOINT_NAME"
echo "- Cleaned up local SSH key files"
echo "- Endpoint remains running (it's part of the infrastructure)"
echo ""
echo -e "${BLUE}ℹ IMPORTANT: The Glue dev endpoint is still running${NC}"
echo -e "${BLUE}ℹ The endpoint was created by Terraform as part of the scenario${NC}"
echo -e "${BLUE}ℹ It will continue to incur costs (~$2.20/hour) until disabled${NC}"
echo ""
echo -e "${GREEN}The attack artifacts have been removed.${NC}"
echo -e "${YELLOW}To stop all costs and remove infrastructure:${NC}"
echo "  1. Set enable_single_account_privesc_one_hop_to_admin_glue_002_glue_updatedevendpoint = false in terraform.tfvars"
echo "  2. Run: terraform apply"
echo ""

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
