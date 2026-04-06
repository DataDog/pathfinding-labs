#!/bin/bash

# Cleanup script for iam:PassRole + apprunner:CreateService privilege escalation demo
# This script removes the App Runner service and detaches the admin policy


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
STARTING_USER="pl-prod-apprunner-001-to-admin-starting-user"
APP_RUNNER_SERVICE_NAME="pl-privesc-apprunner-demo"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + App Runner CreateService Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 0: Get admin credentials from Terraform
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
export AWS_REGION="$AWS_REGION"
unset AWS_SESSION_TOKEN

echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

# Get region from Terraform
CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$CURRENT_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    CURRENT_REGION="us-east-1"
fi

echo "Region from Terraform: $CURRENT_REGION"
export AWS_REGION="$CURRENT_REGION"

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"

cd - > /dev/null  # Return to scenario directory
echo ""

# Step 1: Detach AdministratorAccess policy from starting user
echo -e "${YELLOW}Step 1: Detaching AdministratorAccess policy from starting user${NC}"
echo "User: $STARTING_USER"
echo "Policy: arn:aws:iam::aws:policy/AdministratorAccess"

# Check if the policy is attached
POLICY_ATTACHED=$(aws iam list-attached-user-policies \
    --user-name "$STARTING_USER" \
    --query "AttachedPolicies[?PolicyArn=='arn:aws:iam::aws:policy/AdministratorAccess'].PolicyArn" \
    --output text 2>/dev/null || echo "")

if [ -n "$POLICY_ATTACHED" ]; then
    echo "Found AdministratorAccess policy attached to user"

    aws iam detach-user-policy \
        --user-name "$STARTING_USER" \
        --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"

    echo -e "${GREEN}✓ Detached AdministratorAccess policy${NC}"
else
    echo -e "${YELLOW}AdministratorAccess policy not found (may already be detached)${NC}"
fi
echo ""

# Step 2: Find and delete App Runner service
echo -e "${YELLOW}Step 2: Finding and deleting App Runner service${NC}"
echo "Service name: $APP_RUNNER_SERVICE_NAME"
echo "Region: $CURRENT_REGION"
echo ""

# List services to find our service ARN
SERVICE_ARN=$(aws apprunner list-services \
    --region $CURRENT_REGION \
    --query "ServiceSummaryList[?ServiceName=='${APP_RUNNER_SERVICE_NAME}'].ServiceArn" \
    --output text 2>/dev/null || echo "")

if [ -z "$SERVICE_ARN" ] || [ "$SERVICE_ARN" = "None" ]; then
    echo -e "${YELLOW}App Runner service $APP_RUNNER_SERVICE_NAME not found (may already be deleted)${NC}"
else
    echo "Found service ARN: $SERVICE_ARN"

    # Check current service status
    CURRENT_STATUS=$(aws apprunner describe-service \
        --region $CURRENT_REGION \
        --service-arn "$SERVICE_ARN" \
        --query 'Service.Status' \
        --output text 2>/dev/null || echo "UNKNOWN")

    echo "Current service status: $CURRENT_STATUS"

    # Wait for service to reach a deletable state if it's in OPERATION_IN_PROGRESS
    if [ "$CURRENT_STATUS" = "OPERATION_IN_PROGRESS" ]; then
        echo -e "${YELLOW}Service is in OPERATION_IN_PROGRESS state. Waiting for it to stabilize before deletion...${NC}"

        MAX_WAIT=600  # 10 minutes
        WAIT_TIME=0

        while [ $WAIT_TIME -lt $MAX_WAIT ]; do
            CURRENT_STATUS=$(aws apprunner describe-service \
                --region $CURRENT_REGION \
                --service-arn "$SERVICE_ARN" \
                --query 'Service.Status' \
                --output text 2>/dev/null || echo "UNKNOWN")

            echo "Service status: $CURRENT_STATUS (waited ${WAIT_TIME}s)"

            if [ "$CURRENT_STATUS" != "OPERATION_IN_PROGRESS" ]; then
                echo -e "${GREEN}✓ Service has reached stable state: $CURRENT_STATUS${NC}"
                break
            fi

            sleep 15
            WAIT_TIME=$((WAIT_TIME + 15))
        done

        if [ "$CURRENT_STATUS" = "OPERATION_IN_PROGRESS" ]; then
            echo -e "${RED}Warning: Service still in OPERATION_IN_PROGRESS after ${WAIT_TIME}s${NC}"
            echo "You may need to wait longer and run this cleanup script again later."
            echo "Service ARN: $SERVICE_ARN"
            exit 1
        fi
        echo ""
    fi

    echo "Deleting App Runner service..."

    # Delete the service
    DELETE_RESULT=$(aws apprunner delete-service \
        --region $CURRENT_REGION \
        --service-arn "$SERVICE_ARN" \
        --output json 2>&1)

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Initiated deletion of App Runner service${NC}"
    else
        echo -e "${RED}Error deleting service:${NC}"
        echo "$DELETE_RESULT"
        exit 1
    fi
    echo ""

    # Wait for service deletion
    echo -e "${YELLOW}Waiting for service deletion to complete (this may take 2-3 minutes)...${NC}"

    MAX_WAIT=300  # 5 minutes
    WAIT_TIME=0
    SERVICE_DELETED=false

    while [ $WAIT_TIME -lt $MAX_WAIT ]; do
        # Check if service still exists
        SERVICE_STATUS=$(aws apprunner describe-service \
            --region $CURRENT_REGION \
            --service-arn "$SERVICE_ARN" \
            --query 'Service.Status' \
            --output text 2>/dev/null || echo "DELETED")

        if [ "$SERVICE_STATUS" = "DELETED" ] || [ -z "$SERVICE_STATUS" ]; then
            echo -e "${GREEN}✓ App Runner service successfully deleted${NC}"
            SERVICE_DELETED=true
            break
        fi

        echo "Service status: $SERVICE_STATUS (waited ${WAIT_TIME}s)"
        sleep 15
        WAIT_TIME=$((WAIT_TIME + 15))
    done

    if [ "$SERVICE_DELETED" = false ]; then
        echo -e "${YELLOW}Warning: Service deletion taking longer than expected${NC}"
        echo "Service ARN: $SERVICE_ARN"
        echo "You can check status with:"
        echo "  aws apprunner describe-service --service-arn $SERVICE_ARN --region $CURRENT_REGION"
    fi
fi
echo ""

# Step 3: Clean up local temporary files
echo -e "${YELLOW}Step 3: Cleaning up local temporary files${NC}"
LOCAL_FILES=("/tmp/apprunner-config.json")

FILES_CLEANED=0
for FILE in "${LOCAL_FILES[@]}"; do
    if [ -f "$FILE" ]; then
        rm -f "$FILE"
        echo "Removed: $FILE"
        FILES_CLEANED=$((FILES_CLEANED + 1))
    fi
done

if [ $FILES_CLEANED -gt 0 ]; then
    echo -e "${GREEN}✓ Cleaned up $FILES_CLEANED local file(s)${NC}"
else
    echo -e "${YELLOW}No local files to clean up${NC}"
fi
echo ""

# Step 4: Verify cleanup
echo -e "${YELLOW}Step 4: Verifying cleanup${NC}"

# Check that policy is detached
POLICY_CHECK=$(aws iam list-attached-user-policies \
    --user-name "$STARTING_USER" \
    --query "AttachedPolicies[?PolicyArn=='arn:aws:iam::aws:policy/AdministratorAccess'].PolicyArn" \
    --output text 2>/dev/null || echo "")

if [ -z "$POLICY_CHECK" ]; then
    echo -e "${GREEN}✓ AdministratorAccess policy successfully detached${NC}"
else
    echo -e "${YELLOW}⚠ Warning: AdministratorAccess policy may still be attached${NC}"
fi

# Check that service is deleted
SERVICE_CHECK=$(aws apprunner list-services \
    --region $CURRENT_REGION \
    --query "ServiceSummaryList[?ServiceName=='${APP_RUNNER_SERVICE_NAME}'].ServiceArn" \
    --output text 2>/dev/null || echo "")

if [ -z "$SERVICE_CHECK" ]; then
    echo -e "${GREEN}✓ App Runner service successfully deleted${NC}"
else
    echo -e "${YELLOW}⚠ Warning: App Runner service may still exist${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess policy from $STARTING_USER"
echo "- Deleted App Runner service: $APP_RUNNER_SERVICE_NAME"
echo "- Cleaned up local temporary files"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
