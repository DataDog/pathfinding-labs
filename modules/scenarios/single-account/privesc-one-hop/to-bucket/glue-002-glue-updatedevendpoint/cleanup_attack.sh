#!/bin/bash

# Cleanup script for glue:UpdateDevEndpoint privilege escalation demo
# This script removes the attacker's SSH key from the endpoint and cleans up temporary files


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
SSH_KEY_PATH="/tmp/pl-glue-002-demo-key"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Glue UpdateDevEndpoint Demo${NC}"
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

# Get endpoint name from Terraform
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_bucket_glue_002_glue_updatedevendpoint.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output for this scenario${NC}"
    echo "Make sure the scenario is deployed"
    exit 1
fi

ENDPOINT_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.dev_endpoint_name')

if [ "$ENDPOINT_NAME" == "null" ] || [ -z "$ENDPOINT_NAME" ]; then
    echo -e "${RED}Error: Could not retrieve endpoint name from terraform output${NC}"
    exit 1
fi

echo "Target endpoint: $ENDPOINT_NAME"
echo ""

# Navigate back to scenario directory
cd - > /dev/null

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 2: Get the attacker's SSH public key from local file
echo -e "${YELLOW}Step 2: Identifying SSH key to remove${NC}"

if [ -f ${SSH_KEY_PATH}.pub ]; then
    SSH_PUBLIC_KEY=$(cat ${SSH_KEY_PATH}.pub)
    echo "Found SSH public key from demo"
    echo -e "${GREEN}✓ Identified attacker's SSH key${NC}"
else
    echo -e "${YELLOW}SSH public key file not found locally${NC}"
    echo "Will attempt to retrieve from endpoint and remove all keys added during demo"
    SSH_PUBLIC_KEY=""
fi
echo ""

# Step 3: Remove the attacker's SSH key from the endpoint
echo -e "${YELLOW}Step 3: Removing attacker's SSH key from dev endpoint${NC}"
echo "Endpoint: $ENDPOINT_NAME"

# Check if endpoint exists
ENDPOINT_EXISTS=$(aws glue get-dev-endpoint \
    --endpoint-name $ENDPOINT_NAME \
    --region $CURRENT_REGION \
    --query 'DevEndpoint.EndpointName' \
    --output text 2>/dev/null || echo "")

if [ -z "$ENDPOINT_EXISTS" ] || [ "$ENDPOINT_EXISTS" = "None" ]; then
    echo -e "${YELLOW}Endpoint $ENDPOINT_NAME not found${NC}"
    echo "The endpoint may have been manually deleted or not yet created"
else
    echo "Found endpoint: $ENDPOINT_NAME"

    # Get current public keys
    CURRENT_KEYS=$(aws glue get-dev-endpoint \
        --endpoint-name $ENDPOINT_NAME \
        --region $CURRENT_REGION \
        --query 'DevEndpoint.PublicKeys' \
        --output json 2>/dev/null || echo "[]")

    NUM_KEYS=$(echo "$CURRENT_KEYS" | jq '. | length')
    echo "Current number of public keys on endpoint: $NUM_KEYS"

    if [ "$NUM_KEYS" -eq 0 ]; then
        echo -e "${YELLOW}No public keys found on endpoint (may already be cleaned)${NC}"
    else
        echo "Public keys present on endpoint"

        # If we have the local key, remove it specifically
        if [ -n "$SSH_PUBLIC_KEY" ]; then
            echo "Removing specific SSH key from endpoint..."

            aws glue update-dev-endpoint \
                --endpoint-name $ENDPOINT_NAME \
                --region $CURRENT_REGION \
                --delete-public-keys "$SSH_PUBLIC_KEY" \
                --output json > /dev/null

            echo -e "${GREEN}✓ Removed attacker's SSH key from endpoint${NC}"
        else
            # If we don't have the local key, we'll remove all keys
            # This is safe because the endpoint was created without keys (Terraform doesn't set any)
            echo -e "${YELLOW}Removing all public keys from endpoint (restoring to original state)${NC}"

            # Get all keys as an array
            KEYS_ARRAY=$(echo "$CURRENT_KEYS" | jq -r '.[]')

            # Remove each key
            while IFS= read -r key; do
                if [ -n "$key" ]; then
                    echo "Removing key..."
                    aws glue update-dev-endpoint \
                        --endpoint-name $ENDPOINT_NAME \
                        --region $CURRENT_REGION \
                        --delete-public-keys "$key" \
                        --output json > /dev/null 2>&1 || true
                fi
            done <<< "$KEYS_ARRAY"

            echo -e "${GREEN}✓ Removed all SSH keys from endpoint${NC}"
        fi

        # Wait for update to complete
        echo "Waiting for update to propagate..."
        sleep 10

        # Verify keys were removed
        REMAINING_KEYS=$(aws glue get-dev-endpoint \
            --endpoint-name $ENDPOINT_NAME \
            --region $CURRENT_REGION \
            --query 'DevEndpoint.PublicKeys | length(@)' \
            --output text 2>/dev/null || echo "0")

        echo "Remaining public keys: $REMAINING_KEYS"

        if [ "$REMAINING_KEYS" -eq 0 ]; then
            echo -e "${GREEN}✓ All SSH keys successfully removed${NC}"
        else
            echo -e "${YELLOW}⚠ Warning: Some SSH keys may still be present${NC}"
        fi
    fi
fi
echo ""

# Step 4: Remove local SSH keys
echo -e "${YELLOW}Step 4: Removing temporary SSH key files${NC}"
if [ -f ${SSH_KEY_PATH} ] || [ -f ${SSH_KEY_PATH}.pub ]; then
    rm -f ${SSH_KEY_PATH} ${SSH_KEY_PATH}.pub
    echo -e "${GREEN}✓ Removed SSH key files${NC}"
else
    echo -e "${YELLOW}SSH key files not found (may already be removed)${NC}"
fi
echo ""

# Step 5: Verify cleanup
echo -e "${YELLOW}Step 5: Verifying cleanup${NC}"

# Check endpoint still exists (it should - it's infrastructure)
if [ -n "$ENDPOINT_EXISTS" ] && [ "$ENDPOINT_EXISTS" != "None" ]; then
    FINAL_KEY_COUNT=$(aws glue get-dev-endpoint \
        --endpoint-name $ENDPOINT_NAME \
        --region $CURRENT_REGION \
        --query 'DevEndpoint.PublicKeys | length(@)' \
        --output text 2>/dev/null || echo "0")

    echo "Endpoint still exists (as expected): $ENDPOINT_NAME"
    echo "Current SSH keys on endpoint: $FINAL_KEY_COUNT"

    if [ "$FINAL_KEY_COUNT" -eq 0 ]; then
        echo -e "${GREEN}✓ Endpoint restored to original state (no SSH keys)${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: Endpoint has $FINAL_KEY_COUNT SSH key(s)${NC}"
    fi
else
    echo -e "${YELLOW}Endpoint not found (may not have been created yet)${NC}"
fi

# Check that SSH keys are gone
if [ ! -f ${SSH_KEY_PATH} ] && [ ! -f ${SSH_KEY_PATH}.pub ]; then
    echo -e "${GREEN}✓ Local SSH keys removed${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Some SSH key files may still exist${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Removed attacker's SSH key from endpoint: $ENDPOINT_NAME"
echo "- Removed temporary SSH key files"
echo "- Endpoint continues to run (part of infrastructure)"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The Glue endpoint remains deployed and continues to incur costs (~\$2.20/hour)${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, endpoint) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
