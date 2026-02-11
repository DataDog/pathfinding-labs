#!/bin/bash

# Cleanup script for iam:PassRole + airflow:CreateEnvironment privilege escalation demo
# This script removes the MWAA environment and detaches AdministratorAccess from the starting user
#
# IMPORTANT: Run this script immediately after the demo to avoid ongoing MWAA charges!

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-mwaa-001-to-admin-starting-user"
DEMO_ENVIRONMENT_PREFIX="pl-mwaa-001-demo-"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + MWAA CreateEnvironment Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${YELLOW}This cleanup will:${NC}"
echo "  1. Delete any MWAA environments created by the demo"
echo "  2. Detach AdministratorAccess from the starting user"
echo ""
echo -e "${BLUE}Note: MWAA environment deletion takes 10-20 minutes${NC}"
echo ""

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

# Step 2: Find and delete MWAA environments created by the demo
echo -e "${YELLOW}Step 2: Finding and deleting demo MWAA environments${NC}"
echo "Searching for MWAA environments with prefix: $DEMO_ENVIRONMENT_PREFIX"
echo "Region: $CURRENT_REGION"
echo ""

# List all MWAA environments
ALL_ENVIRONMENTS=$(aws mwaa list-environments \
    --region "$CURRENT_REGION" \
    --query 'Environments' \
    --output json 2>/dev/null || echo "[]")

# Filter for demo environments
DEMO_ENVIRONMENTS=$(echo "$ALL_ENVIRONMENTS" | jq -r ".[] | select(startswith(\"$DEMO_ENVIRONMENT_PREFIX\"))")

if [ -n "$DEMO_ENVIRONMENTS" ]; then
    echo "Found MWAA environments to delete:"
    echo "$DEMO_ENVIRONMENTS"
    echo ""

    # Delete each environment
    for ENV_NAME in $DEMO_ENVIRONMENTS; do
        echo -e "${YELLOW}Deleting MWAA environment: $ENV_NAME${NC}"

        # Check current status
        ENV_STATUS=$(aws mwaa get-environment \
            --region "$CURRENT_REGION" \
            --name "$ENV_NAME" \
            --query 'Environment.Status' \
            --output text 2>/dev/null || echo "UNKNOWN")

        echo "  Current status: $ENV_STATUS"

        if [ "$ENV_STATUS" = "DELETING" ]; then
            echo "  Environment is already being deleted"
        elif [ "$ENV_STATUS" != "DELETED" ] && [ "$ENV_STATUS" != "UNKNOWN" ]; then
            # Delete the environment
            aws mwaa delete-environment \
                --region "$CURRENT_REGION" \
                --name "$ENV_NAME" 2>/dev/null || true

            echo -e "${GREEN}OK Initiated deletion of environment: $ENV_NAME${NC}"
        else
            echo "  Environment already deleted or not found"
        fi
        echo ""
    done

    # Wait for environments to be deleted
    echo -e "${YELLOW}Waiting for MWAA environment(s) to be deleted...${NC}"
    echo -e "${BLUE}This typically takes 10-20 minutes. Please be patient...${NC}"
    echo ""

    MAX_WAIT=1800  # 30 minutes maximum
    ELAPSED=0
    CHECK_INTERVAL=60  # Check every minute

    while [ $ELAPSED -lt $MAX_WAIT ]; do
        ALL_DELETED=true

        for ENV_NAME in $DEMO_ENVIRONMENTS; do
            ENV_STATUS=$(aws mwaa get-environment \
                --region "$CURRENT_REGION" \
                --name "$ENV_NAME" \
                --query 'Environment.Status' \
                --output text 2>/dev/null || echo "DELETED")

            if [ "$ENV_STATUS" != "DELETED" ] && [ "$ENV_STATUS" != "ResourceNotFoundException" ]; then
                ALL_DELETED=false
                MINUTES=$((ELAPSED / 60))
                echo "  [${MINUTES}m] $ENV_NAME status: $ENV_STATUS"
            fi
        done

        if [ "$ALL_DELETED" = true ]; then
            echo ""
            echo -e "${GREEN}OK All demo MWAA environments deleted!${NC}"
            break
        fi

        sleep $CHECK_INTERVAL
        ELAPSED=$((ELAPSED + CHECK_INTERVAL))
    done

    if [ $ELAPSED -ge $MAX_WAIT ]; then
        echo -e "${YELLOW}Warning: Timeout waiting for environment deletion${NC}"
        echo "The environment(s) may still be deleting. Check the AWS console."
    fi
else
    echo -e "${YELLOW}No demo MWAA environments found (may already be deleted)${NC}"
fi
echo ""

# Step 3: Clean up orphaned ENIs in MWAA subnets
# MWAA creates ENIs that can persist after environment deletion and block Terraform from deleting subnets
echo -e "${YELLOW}Step 3: Cleaning up orphaned ENIs in MWAA subnets${NC}"

# Get subnet IDs from Terraform output
cd ../../../../../..  # Go to project root
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_mwaa_001_iam_passrole_airflow_createenvironment.value // empty')

if [ -n "$MODULE_OUTPUT" ] && [ "$MODULE_OUTPUT" != "null" ]; then
    SUBNET_IDS=$(echo "$MODULE_OUTPUT" | jq -r '.private_subnet_ids // [] | .[]' 2>/dev/null)
    VPC_ID=$(echo "$MODULE_OUTPUT" | jq -r '.vpc_id // empty' 2>/dev/null)
fi
cd - > /dev/null

if [ -n "$SUBNET_IDS" ]; then
    echo "Checking for orphaned ENIs in MWAA subnets..."

    for SUBNET_ID in $SUBNET_IDS; do
        echo "  Checking subnet: $SUBNET_ID"

        # Find available (orphaned) ENIs in this subnet
        ORPHANED_ENIS=$(aws ec2 describe-network-interfaces \
            --filters "Name=subnet-id,Values=$SUBNET_ID" "Name=status,Values=available" \
            --query 'NetworkInterfaces[].NetworkInterfaceId' \
            --output text 2>/dev/null || echo "")

        if [ -n "$ORPHANED_ENIS" ] && [ "$ORPHANED_ENIS" != "None" ]; then
            for ENI_ID in $ORPHANED_ENIS; do
                echo "    Deleting orphaned ENI: $ENI_ID"
                aws ec2 delete-network-interface --network-interface-id "$ENI_ID" 2>/dev/null || true
            done
        fi

        # Also check for in-use ENIs that might be from deleted MWAA
        IN_USE_ENIS=$(aws ec2 describe-network-interfaces \
            --filters "Name=subnet-id,Values=$SUBNET_ID" \
            --query 'NetworkInterfaces[?Status==`in-use`].[NetworkInterfaceId,Description]' \
            --output text 2>/dev/null || echo "")

        if [ -n "$IN_USE_ENIS" ] && [ "$IN_USE_ENIS" != "None" ]; then
            echo -e "    ${YELLOW}Note: Some ENIs are still in-use (may be from active resources):${NC}"
            echo "$IN_USE_ENIS" | while read line; do
                echo "      $line"
            done
        fi
    done

    echo -e "${GREEN}OK ENI cleanup complete${NC}"
else
    echo -e "${YELLOW}Could not retrieve subnet IDs from Terraform output${NC}"
    echo "If you encounter subnet deletion errors, manually delete orphaned ENIs"
fi
echo ""

# Step 4: Detach AdministratorAccess policy from starting user
echo -e "${YELLOW}Step 4: Detaching AdministratorAccess policy from starting user${NC}"
echo "User: $STARTING_USER"

# Check if the policy is attached
if aws iam list-attached-user-policies \
    --user-name "$STARTING_USER" \
    --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`]' \
    --output text 2>/dev/null | grep -q "AdministratorAccess"; then

    echo "Found AdministratorAccess policy attached to user"
    aws iam detach-user-policy \
        --user-name "$STARTING_USER" \
        --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"

    echo -e "${GREEN}OK Detached AdministratorAccess policy from $STARTING_USER${NC}"
else
    echo -e "${YELLOW}AdministratorAccess policy not attached to user (may already be detached)${NC}"
fi
echo ""

# Step 5: Verify cleanup
echo -e "${YELLOW}Step 5: Verifying cleanup${NC}"

# Check that AdministratorAccess is detached
if aws iam list-attached-user-policies \
    --user-name "$STARTING_USER" \
    --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`]' \
    --output text 2>/dev/null | grep -q "AdministratorAccess"; then
    echo -e "${YELLOW}Warning: AdministratorAccess still attached to $STARTING_USER${NC}"
else
    echo -e "${GREEN}OK AdministratorAccess successfully detached from user${NC}"
fi

# Check for remaining MWAA environments
REMAINING_ENVIRONMENTS=$(aws mwaa list-environments \
    --region "$CURRENT_REGION" \
    --query 'Environments' \
    --output json 2>/dev/null || echo "[]")

REMAINING_DEMO=$(echo "$REMAINING_ENVIRONMENTS" | jq -r ".[] | select(startswith(\"$DEMO_ENVIRONMENT_PREFIX\"))" 2>/dev/null || echo "")

if [ -n "$REMAINING_DEMO" ]; then
    echo -e "${YELLOW}Warning: Some demo MWAA environments may still exist (could be deleting):${NC}"
    echo "$REMAINING_DEMO"
    echo "Check the AWS console to verify deletion status."
else
    echo -e "${GREEN}OK No demo MWAA environments found${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Deleted MWAA environments with prefix: $DEMO_ENVIRONMENT_PREFIX"
echo "- Detached AdministratorAccess policy from starting user"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${GREEN}MWAA billing should stop once deletion is complete.${NC}"
echo ""
echo -e "${YELLOW}The infrastructure (users, roles, VPC, S3 bucket) remains deployed.${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply.${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
