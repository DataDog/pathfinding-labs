#!/bin/bash
set -e

# Cleanup script for cross-account variant of iam:PassRole + kinesisanalytics:CreateApplication + kinesisanalytics:StartApplication
# This script detaches AdministratorAccess from the starting user, stops and deletes the
# Managed Apache Flink application, deletes the attacker S3 bucket, and cleans up local temporary files.

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
STARTING_USER="pl-prod-kinesisanalytics-001-to-admin-starting-user"
APP_NAME="pl-prod-kinesisanalytics-001-to-admin-app"
ATTACKER_PROFILE="demo-attacker.AWSAdministratorAccess"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: PassRole + Kinesis Analytics CreateApplication + StartApplication${NC}"
echo -e "${GREEN}(Cross-Account Attacker Bucket Variant)${NC}"
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
echo -e "${GREEN}Retrieved admin credentials${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

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
    echo -e "${GREEN}Detached AdministratorAccess from $STARTING_USER${NC}"
else
    echo -e "${YELLOW}AdministratorAccess not attached to $STARTING_USER (may already be detached)${NC}"
fi
echo ""

# Step 3: Stop and delete Managed Apache Flink applications for this scenario
echo -e "${YELLOW}Step 3: Finding and deleting Managed Apache Flink applications${NC}"
echo "Looking for application: $APP_NAME"

# Check if the application exists
APP_DETAILS=$(aws kinesisanalyticsv2 describe-application \
    --region $CURRENT_REGION \
    --application-name "$APP_NAME" \
    --output json 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$APP_DETAILS" ]; then
    APP_STATUS=$(echo "$APP_DETAILS" | jq -r '.ApplicationDetail.ApplicationStatus')
    APP_VERSION=$(echo "$APP_DETAILS" | jq -r '.ApplicationDetail.ApplicationVersionId')
    APP_CREATE_TIMESTAMP=$(echo "$APP_DETAILS" | jq -r '.ApplicationDetail.CreateTimestamp')

    echo "Found application: $APP_NAME"
    echo "Status: $APP_STATUS"
    echo "Version: $APP_VERSION"

    # Stop the application if it's running
    if [ "$APP_STATUS" == "RUNNING" ] || [ "$APP_STATUS" == "STARTING" ] || [ "$APP_STATUS" == "UPDATING" ]; then
        echo "Stopping application..."
        aws kinesisanalyticsv2 stop-application \
            --region $CURRENT_REGION \
            --application-name "$APP_NAME" \
            --force true 2>/dev/null || \
        aws kinesisanalyticsv2 stop-application \
            --region $CURRENT_REGION \
            --application-name "$APP_NAME" 2>/dev/null || true

        # Wait for application to stop
        echo "Waiting for application to stop..."
        MAX_WAIT=180
        ELAPSED=0
        while [ $ELAPSED -lt $MAX_WAIT ]; do
            APP_STATUS=$(aws kinesisanalyticsv2 describe-application \
                --region $CURRENT_REGION \
                --application-name "$APP_NAME" \
                --query 'ApplicationDetail.ApplicationStatus' \
                --output text 2>/dev/null)

            echo "Application status: $APP_STATUS (${ELAPSED}s elapsed)"

            if [ "$APP_STATUS" == "READY" ] || [ "$APP_STATUS" == "FORCE_STOPPING" ]; then
                if [ "$APP_STATUS" == "READY" ]; then
                    break
                fi
            fi

            sleep 15
            ELAPSED=$((ELAPSED + 15))
        done

        # Re-fetch the version after stopping (it may have incremented)
        APP_DETAILS=$(aws kinesisanalyticsv2 describe-application \
            --region $CURRENT_REGION \
            --application-name "$APP_NAME" \
            --output json 2>/dev/null)
        APP_VERSION=$(echo "$APP_DETAILS" | jq -r '.ApplicationDetail.ApplicationVersionId')
        APP_CREATE_TIMESTAMP=$(echo "$APP_DETAILS" | jq -r '.ApplicationDetail.CreateTimestamp')
    fi

    # Delete the application
    echo "Deleting application: $APP_NAME (version: $APP_VERSION)"
    aws kinesisanalyticsv2 delete-application \
        --region $CURRENT_REGION \
        --application-name "$APP_NAME" \
        --create-timestamp "$APP_CREATE_TIMESTAMP" 2>/dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Deleted Flink application: $APP_NAME${NC}"
    else
        echo -e "${YELLOW}Warning: Could not delete application $APP_NAME (may need manual cleanup)${NC}"
        echo "  Try: aws kinesisanalyticsv2 delete-application --region $CURRENT_REGION --application-name $APP_NAME --create-timestamp $APP_CREATE_TIMESTAMP"
    fi
else
    echo -e "${YELLOW}Application $APP_NAME not found (may already be deleted)${NC}"
fi
echo ""

# Step 4: Delete attacker S3 bucket
echo -e "${YELLOW}Step 4: Deleting attacker S3 bucket${NC}"

# Derive attacker account ID
ATTACKER_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text --profile "$ATTACKER_PROFILE" 2>/dev/null)

if [ -z "$ATTACKER_ACCOUNT_ID" ] || [ "$ATTACKER_ACCOUNT_ID" == "null" ]; then
    echo -e "${YELLOW}Warning: Could not get attacker account ID using profile '$ATTACKER_PROFILE'${NC}"
    echo "Skipping attacker bucket cleanup"
else
    ATTACKER_BUCKET_NAME="pl-attacker-kinesisanalytics-001-exploit-${ATTACKER_ACCOUNT_ID}"
    echo "Attacker bucket: $ATTACKER_BUCKET_NAME"

    # Check if bucket exists
    if aws s3api head-bucket --bucket "$ATTACKER_BUCKET_NAME" --profile "$ATTACKER_PROFILE" 2>/dev/null; then
        echo "Removing objects from attacker bucket..."
        aws s3 rm "s3://$ATTACKER_BUCKET_NAME" --recursive --profile "$ATTACKER_PROFILE" 2>/dev/null

        echo "Deleting attacker bucket..."
        aws s3api delete-bucket --bucket "$ATTACKER_BUCKET_NAME" --profile "$ATTACKER_PROFILE" 2>/dev/null

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Deleted attacker bucket: $ATTACKER_BUCKET_NAME${NC}"
        else
            echo -e "${YELLOW}Warning: Could not delete attacker bucket $ATTACKER_BUCKET_NAME${NC}"
            echo "  Manual cleanup: aws s3 rb s3://$ATTACKER_BUCKET_NAME --force --profile $ATTACKER_PROFILE"
        fi
    else
        echo -e "${YELLOW}Attacker bucket $ATTACKER_BUCKET_NAME not found (may already be deleted)${NC}"
    fi
fi
echo ""

# Step 5: Clean up local temporary files
echo -e "${YELLOW}Step 5: Cleaning up local temporary files${NC}"
LOCAL_FILES=("/tmp/kinesisanalytics-001-app-config.json")

FILES_DELETED=false

for FILE in "${LOCAL_FILES[@]}"; do
    if [ -f "$FILE" ]; then
        rm -f "$FILE"
        echo "Removed: $FILE"
        FILES_DELETED=true
    fi
done

if [ "$FILES_DELETED" = false ]; then
    echo "No local temporary files found"
fi

echo -e "${GREEN}Cleaned up local files${NC}"
echo ""

# Step 6: Verify cleanup
echo -e "${YELLOW}Step 6: Verifying cleanup${NC}"

# Check that AdministratorAccess is detached
if aws iam list-attached-user-policies --user-name "$STARTING_USER" --query "AttachedPolicies[?PolicyArn=='$ADMIN_POLICY_ARN'].PolicyName" --output text 2>/dev/null | grep -q "AdministratorAccess"; then
    echo -e "${YELLOW}Warning: AdministratorAccess still attached to $STARTING_USER${NC}"
else
    echo -e "${GREEN}AdministratorAccess successfully detached from $STARTING_USER${NC}"
fi

# Check that application is deleted
APP_CHECK=$(aws kinesisanalyticsv2 describe-application \
    --region $CURRENT_REGION \
    --application-name "$APP_NAME" \
    --query 'ApplicationDetail.ApplicationStatus' \
    --output text 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$APP_CHECK" ]; then
    echo -e "${GREEN}Flink application deleted${NC}"
else
    echo -e "${YELLOW}Warning: Flink application still exists (status: $APP_CHECK)${NC}"
fi

# Check that attacker bucket is deleted
if [ -n "$ATTACKER_BUCKET_NAME" ]; then
    if aws s3api head-bucket --bucket "$ATTACKER_BUCKET_NAME" --profile "$ATTACKER_PROFILE" 2>/dev/null; then
        echo -e "${YELLOW}Warning: Attacker bucket still exists: $ATTACKER_BUCKET_NAME${NC}"
    else
        echo -e "${GREEN}Attacker bucket deleted${NC}"
    fi
fi

echo -e "${GREEN}Local temporary files cleaned up${NC}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess from $STARTING_USER"
echo "- Stopped and deleted Managed Apache Flink application"
echo "- Deleted attacker S3 bucket (cross-account)"
echo "- Cleaned up local temporary files"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
