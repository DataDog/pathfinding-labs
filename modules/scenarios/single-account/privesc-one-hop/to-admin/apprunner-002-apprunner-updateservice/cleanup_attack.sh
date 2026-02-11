#!/bin/bash

# Cleanup script for apprunner:UpdateService privilege escalation demo
# This script restores the App Runner service to its original configuration and detaches the admin policy

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-apprunner-002-to-admin-starting-user"
TARGET_SERVICE_NAME="pl-prod-apprunner-002-to-admin-target-service"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}App Runner UpdateService Demo Cleanup${NC}"
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

# Get region from Terraform
CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

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

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"

cd - > /dev/null  # Return to scenario directory
echo ""

# Step 2: Detach AdministratorAccess policy from starting user
echo -e "${YELLOW}Step 2: Detaching AdministratorAccess policy from starting user${NC}"
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

# Step 3: Restore App Runner service to original configuration
echo -e "${YELLOW}Step 3: Restoring App Runner service to original configuration${NC}"
echo "Service name: $TARGET_SERVICE_NAME"
echo "Region: $CURRENT_REGION"
echo ""

# Check if we have the backup file
if [ ! -f "/tmp/apprunner-original-config.json" ]; then
    echo -e "${YELLOW}Warning: Original configuration backup not found at /tmp/apprunner-original-config.json${NC}"
    echo "The service cannot be automatically restored to its original state."
    echo ""
    echo "You can manually check the service configuration with:"
    echo "  aws apprunner describe-service --service-arn <service-arn> --region $CURRENT_REGION"
    echo ""
else
    echo "Found original configuration backup"

    # Read the original configuration
    ORIGINAL_CONFIG=$(cat /tmp/apprunner-original-config.json)
    SERVICE_ARN=$(echo "$ORIGINAL_CONFIG" | jq -r '.ServiceArn')

    echo "Service ARN: $SERVICE_ARN"

    # Check current service status before updating
    CURRENT_STATUS=$(aws apprunner describe-service \
        --region $CURRENT_REGION \
        --service-arn "$SERVICE_ARN" \
        --query 'Service.Status' \
        --output text 2>/dev/null || echo "UNKNOWN")

    echo "Current service status: $CURRENT_STATUS"

    # Wait for service to reach a stable state if it's in OPERATION_IN_PROGRESS
    if [ "$CURRENT_STATUS" = "OPERATION_IN_PROGRESS" ]; then
        echo -e "${YELLOW}Service is in OPERATION_IN_PROGRESS state. Waiting for it to stabilize before restoration...${NC}"

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

    # Prepare the restore configuration
    RESTORE_CONFIG=$(echo "$ORIGINAL_CONFIG" | jq '{
        ServiceArn: .ServiceArn,
        SourceConfiguration: .SourceConfiguration
    }')

    # Save to temp file
    echo "$RESTORE_CONFIG" > /tmp/apprunner-restore-config.json

    echo "Restoring service to original configuration..."
    RESTORE_RESULT=$(aws apprunner update-service \
        --region $CURRENT_REGION \
        --cli-input-json file:///tmp/apprunner-restore-config.json \
        --output json 2>&1)

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Initiated service restoration${NC}"
    else
        echo -e "${RED}Error restoring service:${NC}"
        echo "$RESTORE_RESULT"
        exit 1
    fi
    echo ""

    # Wait for service restoration
    echo -e "${YELLOW}Waiting for service restoration to complete (this may take 3-5 minutes)...${NC}"

    MAX_WAIT=420  # 7 minutes
    WAIT_TIME=0
    SERVICE_RESTORED=false

    while [ $WAIT_TIME -lt $MAX_WAIT ]; do
        # Check service status
        SERVICE_STATUS=$(aws apprunner describe-service \
            --region $CURRENT_REGION \
            --service-arn "$SERVICE_ARN" \
            --query 'Service.Status' \
            --output text 2>/dev/null || echo "UNKNOWN")

        echo "Service status: $SERVICE_STATUS (waited ${WAIT_TIME}s)"

        if [ "$SERVICE_STATUS" = "RUNNING" ]; then
            echo -e "${GREEN}✓ App Runner service successfully restored${NC}"
            SERVICE_RESTORED=true
            break
        elif [ "$SERVICE_STATUS" = "UPDATE_FAILED" ]; then
            echo -e "${RED}Error: Service restoration failed${NC}"
            echo "You may need to manually check and fix the service configuration"
            break
        fi

        sleep 15
        WAIT_TIME=$((WAIT_TIME + 15))
    done

    if [ "$SERVICE_RESTORED" = false ] && [ "$SERVICE_STATUS" != "UPDATE_FAILED" ]; then
        echo -e "${YELLOW}Warning: Service restoration taking longer than expected${NC}"
        echo "Service ARN: $SERVICE_ARN"
        echo "You can check status with:"
        echo "  aws apprunner describe-service --service-arn $SERVICE_ARN --region $CURRENT_REGION"
    fi
    echo ""
fi

# Step 4: Clean up local temporary files
echo -e "${YELLOW}Step 4: Cleaning up local temporary files${NC}"
LOCAL_FILES=(
    "/tmp/apprunner-original-config.json"
    "/tmp/apprunner-update-config.json"
    "/tmp/apprunner-restore-config.json"
)

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

# Step 5: Verify cleanup
echo -e "${YELLOW}Step 5: Verifying cleanup${NC}"

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

# Check service configuration if we have the service ARN
if [ -n "$SERVICE_ARN" ] && [ "$SERVICE_ARN" != "null" ]; then
    CURRENT_IMAGE=$(aws apprunner describe-service \
        --region $CURRENT_REGION \
        --service-arn "$SERVICE_ARN" \
        --query 'Service.SourceConfiguration.ImageRepository.ImageIdentifier' \
        --output text 2>/dev/null || echo "")

    if [[ ! $CURRENT_IMAGE == *"aws-cli"* ]]; then
        echo -e "${GREEN}✓ Service no longer using malicious AWS CLI image${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: Service may still be using AWS CLI image${NC}"
    fi
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess policy from $STARTING_USER"
echo "- Restored App Runner service to original configuration"
echo "- Cleaned up local temporary files"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, and service) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
