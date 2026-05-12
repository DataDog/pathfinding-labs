#!/bin/bash

# Cleanup script for iam:PassRole + emr-serverless:CreateApplication + emr-serverless:StartJobRun privilege escalation demo
# This script detaches AdministratorAccess from the starting user, stops and deletes the EMR Serverless
# application, and removes exfiltrated credentials from S3.

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-emr-serverless-001-to-admin-starting-user"
EMR_APP_NAME="pl-prod-emr-serverless-001-to-admin-app"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: PassRole + EMR Serverless CreateApplication + StartJobRun${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials and region from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get admin cleanup user credentials from root terraform output
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)
CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

# Also get S3 bucket name from the scenario output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_emr_serverless_001_iam_passrole_emr_serverless_createapplication_emr_serverless_startjobrun.value // empty')
S3_BUCKET_NAME=""
if [ -n "$MODULE_OUTPUT" ]; then
    S3_BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.attacker_bucket_name // empty')
fi

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
echo "S3 Bucket: ${S3_BUCKET_NAME:-not found}"
echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

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
    echo -e "${GREEN}✓ Detached AdministratorAccess from $STARTING_USER${NC}"
else
    echo -e "${YELLOW}AdministratorAccess not attached to $STARTING_USER (may already be detached)${NC}"
fi
echo ""

# Step 3: Stop and delete ALL EMR Serverless applications for this scenario
echo -e "${YELLOW}Step 3: Finding and deleting EMR Serverless applications${NC}"
echo "Looking for applications matching: $EMR_APP_NAME"

# Find ALL non-terminated applications matching our scenario name
APPLICATION_IDS=$(aws emr-serverless list-applications \
    --region $CURRENT_REGION \
    --query "applications[?starts_with(name, '$EMR_APP_NAME') && state!='TERMINATED'].id" \
    --output text 2>/dev/null)

if [ -n "$APPLICATION_IDS" ] && [ "$APPLICATION_IDS" != "None" ]; then
    for APPLICATION_ID in $APPLICATION_IDS; do
        echo ""
        echo "Processing application: $APPLICATION_ID"

        # Check application state
        APP_STATE=$(aws emr-serverless get-application \
            --region $CURRENT_REGION \
            --application-id "$APPLICATION_ID" \
            --query 'application.state' \
            --output text 2>/dev/null)

        echo "Application state: $APP_STATE"

        # Cancel any running job runs first
        RUNNING_JOBS=$(aws emr-serverless list-job-runs \
            --region $CURRENT_REGION \
            --application-id "$APPLICATION_ID" \
            --query "jobRuns[?state=='PENDING' || state=='SCHEDULED' || state=='RUNNING'].jobRunId" \
            --output text 2>/dev/null)

        if [ -n "$RUNNING_JOBS" ] && [ "$RUNNING_JOBS" != "None" ]; then
            for JOB_ID in $RUNNING_JOBS; do
                echo "Cancelling job run: $JOB_ID"
                aws emr-serverless cancel-job-run \
                    --region $CURRENT_REGION \
                    --application-id "$APPLICATION_ID" \
                    --job-run-id "$JOB_ID" 2>/dev/null || true
            done
            echo "Waiting 15 seconds for job cancellations to process..."
            sleep 15
        fi

        # Stop the application if it's started
        if [ "$APP_STATE" == "STARTED" ] || [ "$APP_STATE" == "STARTING" ]; then
            echo "Stopping application..."
            aws emr-serverless stop-application \
                --region $CURRENT_REGION \
                --application-id "$APPLICATION_ID" 2>/dev/null || true

            # Wait for application to stop
            echo "Waiting for application to stop..."
            MAX_WAIT=180
            ELAPSED=0
            while [ $ELAPSED -lt $MAX_WAIT ]; do
                APP_STATE=$(aws emr-serverless get-application \
                    --region $CURRENT_REGION \
                    --application-id "$APPLICATION_ID" \
                    --query 'application.state' \
                    --output text 2>/dev/null)

                if [ "$APP_STATE" == "STOPPED" ] || [ "$APP_STATE" == "CREATED" ]; then
                    break
                fi
                sleep 10
                ELAPSED=$((ELAPSED + 10))
            done
        fi

        # Delete the application (transitions to TERMINATED)
        echo "Deleting application: $APPLICATION_ID"
        aws emr-serverless delete-application \
            --region $CURRENT_REGION \
            --application-id "$APPLICATION_ID" 2>/dev/null

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Deleted EMR Serverless application: $APPLICATION_ID${NC}"
        else
            echo -e "${YELLOW}⚠ Could not delete application $APPLICATION_ID (may need manual cleanup)${NC}"
        fi
    done
else
    echo -e "${YELLOW}No active EMR Serverless applications found matching: $EMR_APP_NAME${NC}"
fi
echo ""

# Step 4: Remove exfiltrated credentials from S3
echo -e "${YELLOW}Step 4: Removing exfiltrated credentials from S3${NC}"

if [ -n "$S3_BUCKET_NAME" ]; then
    echo "Cleaning exfiltrated credentials from s3://$S3_BUCKET_NAME/exfil/"

    OBJECTS=$(aws s3 ls "s3://$S3_BUCKET_NAME/exfil/" --region $CURRENT_REGION --recursive 2>/dev/null)
    if [ -n "$OBJECTS" ]; then
        aws s3 rm "s3://$S3_BUCKET_NAME/exfil/" \
            --region $CURRENT_REGION \
            --recursive
        echo -e "${GREEN}✓ Removed exfiltrated credentials from S3 bucket${NC}"
    else
        echo -e "${YELLOW}No exfiltrated credentials found in S3 bucket (may already be cleaned)${NC}"
    fi
else
    echo -e "${YELLOW}S3 bucket name not available, skipping S3 cleanup${NC}"
fi
echo ""

# Step 5: Clean up local temporary files
echo -e "${YELLOW}Step 5: Cleaning up local temporary files${NC}"
LOCAL_FILES=("/tmp/stolen_creds.json")

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

echo -e "${GREEN}✓ Cleaned up local files${NC}"
echo ""

# Step 6: Verify cleanup
echo -e "${YELLOW}Step 6: Verifying cleanup${NC}"

# Check that AdministratorAccess is detached
if aws iam list-attached-user-policies --user-name "$STARTING_USER" --query "AttachedPolicies[?PolicyArn=='$ADMIN_POLICY_ARN'].PolicyName" --output text 2>/dev/null | grep -q "AdministratorAccess"; then
    echo -e "${YELLOW}⚠ Warning: AdministratorAccess still attached to $STARTING_USER${NC}"
else
    echo -e "${GREEN}✓ AdministratorAccess successfully detached from $STARTING_USER${NC}"
fi

# Check that all applications are terminated
REMAINING_APPS=$(aws emr-serverless list-applications \
    --region $CURRENT_REGION \
    --query "applications[?starts_with(name, '$EMR_APP_NAME') && state!='TERMINATED'].{id:id,state:state}" \
    --output text 2>/dev/null)

if [ -z "$REMAINING_APPS" ] || [ "$REMAINING_APPS" == "None" ]; then
    echo -e "${GREEN}✓ All EMR Serverless applications terminated${NC}"
else
    echo -e "${YELLOW}⚠ Some applications still active:${NC}"
    echo "$REMAINING_APPS"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess from $STARTING_USER"
echo "- Stopped and deleted EMR Serverless application(s)"
echo "- Removed exfiltrated credentials from S3"
echo "- Cleaned up local temporary files"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
