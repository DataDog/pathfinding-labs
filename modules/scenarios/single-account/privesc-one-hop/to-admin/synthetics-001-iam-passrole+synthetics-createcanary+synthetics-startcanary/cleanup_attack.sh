#!/bin/bash

# Cleanup script for synthetics-001 privilege escalation demo
# This script detaches the AdministratorAccess policy from the starting user,
# stops and deletes the canary, and cleans up canary artifacts.

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-synthetics-001-to-admin-starting-user"
CANARY_NAME="pl-prod-synth-001-privesc"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Synthetics CreateCanary Privilege Escalation${NC}"
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

# Step 2: Detach AdministratorAccess policy from starting user
echo -e "${YELLOW}Step 2: Detaching AdministratorAccess policy from starting user${NC}"
POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

# Check if policy is attached
ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
    --user-name $STARTING_USER \
    --query 'AttachedPolicies[?PolicyArn==`'$POLICY_ARN'`].PolicyArn' \
    --output text)

if [ -n "$ATTACHED_POLICIES" ]; then
    echo "Found AdministratorAccess policy attached to $STARTING_USER"
    aws iam detach-user-policy \
        --user-name $STARTING_USER \
        --policy-arn $POLICY_ARN
    echo -e "${GREEN}✓ Detached AdministratorAccess policy${NC}"
else
    echo -e "${YELLOW}AdministratorAccess policy not attached (may already be removed)${NC}"
fi
echo ""

# Step 3: Stop and delete the canary
echo -e "${YELLOW}Step 3: Stopping and deleting the Synthetics canary${NC}"

# Check if canary exists
CANARY_STATE=$(aws synthetics get-canary \
    --region $CURRENT_REGION \
    --name "$CANARY_NAME" \
    --query 'Canary.Status.State' \
    --output text 2>/dev/null)

if [ -n "$CANARY_STATE" ] && [ "$CANARY_STATE" != "None" ]; then
    echo "Found canary '$CANARY_NAME' in state: $CANARY_STATE"

    # Stop canary if running
    if [ "$CANARY_STATE" == "RUNNING" ]; then
        echo "Stopping canary..."
        aws synthetics stop-canary \
            --region $CURRENT_REGION \
            --name "$CANARY_NAME" 2>/dev/null
        echo "Waiting for canary to stop..."
        sleep 15

        # Re-check state
        CANARY_STATE=$(aws synthetics get-canary \
            --region $CURRENT_REGION \
            --name "$CANARY_NAME" \
            --query 'Canary.Status.State' \
            --output text 2>/dev/null)
        echo "Canary state: $CANARY_STATE"
    fi

    # Delete canary (works in READY or STOPPED state)
    echo "Deleting canary..."
    aws synthetics delete-canary \
        --region $CURRENT_REGION \
        --name "$CANARY_NAME" \
        --delete-lambda 2>/dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Canary deleted (Lambda function will also be removed)${NC}"
    else
        echo -e "${YELLOW}Warning: Could not delete canary (may need manual cleanup)${NC}"
    fi
else
    echo -e "${YELLOW}Canary '$CANARY_NAME' not found (may already be deleted)${NC}"
fi
echo ""

# Step 4: Clean up canary CloudWatch log groups
echo -e "${YELLOW}Step 4: Cleaning up canary CloudWatch log groups${NC}"

LOG_GROUPS=$(aws logs describe-log-groups \
    --region $CURRENT_REGION \
    --log-group-name-prefix "/aws/lambda/cwsyn-${CANARY_NAME}" \
    --query 'logGroups[].logGroupName' \
    --output text 2>/dev/null)

if [ -n "$LOG_GROUPS" ] && [ "$LOG_GROUPS" != "None" ]; then
    for LG in $LOG_GROUPS; do
        echo "Deleting log group: $LG"
        aws logs delete-log-group \
            --region $CURRENT_REGION \
            --log-group-name "$LG" 2>/dev/null
    done
    echo -e "${GREEN}✓ Deleted canary log groups${NC}"
else
    echo -e "${YELLOW}No canary log groups found${NC}"
fi
echo ""

# Step 5: Verify cleanup
echo -e "${YELLOW}Step 5: Verifying cleanup${NC}"

# Verify policy is detached
ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
    --user-name $STARTING_USER \
    --query 'AttachedPolicies[?PolicyArn==`'$POLICY_ARN'`].PolicyArn' \
    --output text)

if [ -z "$ATTACHED_POLICIES" ]; then
    echo -e "${GREEN}✓ AdministratorAccess policy successfully detached${NC}"
else
    echo -e "${YELLOW}Warning: AdministratorAccess policy still attached to $STARTING_USER${NC}"
fi

# Verify canary is deleted
CANARY_CHECK=$(aws synthetics get-canary \
    --region $CURRENT_REGION \
    --name "$CANARY_NAME" \
    --query 'Canary.Status.State' \
    --output text 2>/dev/null)

if [ -z "$CANARY_CHECK" ] || [ "$CANARY_CHECK" == "None" ]; then
    echo -e "${GREEN}✓ Canary successfully deleted${NC}"
else
    echo -e "${YELLOW}Warning: Canary still exists (state: $CANARY_CHECK)${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess policy from $STARTING_USER"
echo "- Stopped and deleted Synthetics canary: $CANARY_NAME"
echo "- Deleted canary CloudWatch log groups"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, and S3 buckets) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
