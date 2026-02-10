#!/bin/bash

# Cleanup script for airflow:UpdateEnvironment privilege escalation demo (mwaa-002)
# This script restores the MWAA environment to its original state and detaches
# the AdministratorAccess policy from the starting user.
#
# Attack being cleaned up:
# - Attacker changed the MWAA environment's DAG source bucket to attacker-controlled bucket
# - Attacker triggered malicious DAG that attached AdministratorAccess to starting user
#
# This cleanup will:
# - Detach AdministratorAccess from the starting user
# - Restore the original DAG source bucket on the MWAA environment
#
# Note: This does NOT delete the MWAA environment - Terraform manages that.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-mwaa-002-to-admin-starting-user"
MWAA_ENVIRONMENT="pl-prod-mwaa-002-to-admin-env"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}MWAA UpdateEnvironment Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${YELLOW}This cleanup will:${NC}"
echo "  1. Detach AdministratorAccess from the starting user"
echo "  2. Restore the original DAG source bucket on the MWAA environment"
echo ""
echo -e "${BLUE}Note: Restoring the source bucket requires an environment update${NC}"
echo -e "${BLUE}which takes approximately 10-30 minutes.${NC}"
echo ""

# Step 1: Get admin credentials and configuration from Terraform
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

# Get the module output for environment configuration
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_mwaa_002_airflow_updateenvironment.value // empty')

if [ -n "$MODULE_OUTPUT" ] && [ "$MODULE_OUTPUT" != "null" ]; then
    MWAA_ENV_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.mwaa_environment_name // empty')
    STARTING_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_name // empty')
    # Get the original bucket and DAG path for restoration
    ORIGINAL_BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.original_bucket_name // empty')
    ORIGINAL_DAG_PATH=$(echo "$MODULE_OUTPUT" | jq -r '.original_dag_path // empty')
fi

# Use defaults if not found in output
MWAA_ENV_NAME=${MWAA_ENV_NAME:-$MWAA_ENVIRONMENT}
STARTING_USER_NAME=${STARTING_USER_NAME:-$STARTING_USER}

echo "MWAA Environment: $MWAA_ENV_NAME"
echo "Starting User: $STARTING_USER_NAME"

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"

cd - > /dev/null  # Return to scenario directory
echo ""

# Step 2: Detach AdministratorAccess policy from starting user
echo -e "${YELLOW}Step 2: Detaching AdministratorAccess policy from starting user${NC}"
echo "User: $STARTING_USER_NAME"

# Check if the policy is attached
if aws iam list-attached-user-policies \
    --user-name "$STARTING_USER_NAME" \
    --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`]' \
    --output text 2>/dev/null | grep -q "AdministratorAccess"; then

    echo "Found AdministratorAccess policy attached to user"
    aws iam detach-user-policy \
        --user-name "$STARTING_USER_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"

    echo -e "${GREEN}OK Detached AdministratorAccess policy from $STARTING_USER_NAME${NC}"
else
    echo -e "${YELLOW}AdministratorAccess policy not attached to user (may already be detached)${NC}"
fi
echo ""

# Step 3: Check current MWAA environment status and restore original DAG source bucket
echo -e "${YELLOW}Step 3: Checking MWAA environment status${NC}"
echo "Environment: $MWAA_ENV_NAME"
echo ""

# Get current environment info
ENV_EXISTS=$(aws mwaa get-environment \
    --region "$CURRENT_REGION" \
    --name "$MWAA_ENV_NAME" \
    --output json 2>/dev/null || echo "")

if [ -z "$ENV_EXISTS" ]; then
    echo -e "${YELLOW}MWAA environment not found (may not be deployed or already deleted)${NC}"
    echo "Skipping source bucket restoration."
else
    CURRENT_STATUS=$(echo "$ENV_EXISTS" | jq -r '.Environment.Status')
    CURRENT_SOURCE_BUCKET=$(echo "$ENV_EXISTS" | jq -r '.Environment.SourceBucketArn')
    CURRENT_DAG_PATH=$(echo "$ENV_EXISTS" | jq -r '.Environment.DagS3Path // "dags/"')

    echo "Current Status: $CURRENT_STATUS"
    echo "Current Source Bucket: $CURRENT_SOURCE_BUCKET"
    echo "Current DAG Path: $CURRENT_DAG_PATH"
    echo ""

    # If we have original bucket info, restore it
    if [ -n "$ORIGINAL_BUCKET_NAME" ] && [ "$ORIGINAL_BUCKET_NAME" != "null" ]; then

        ORIGINAL_BUCKET_ARN="arn:aws:s3:::$ORIGINAL_BUCKET_NAME"

        # Check if the bucket has already been restored
        if [ "$CURRENT_SOURCE_BUCKET" = "$ORIGINAL_BUCKET_ARN" ]; then
            echo -e "${GREEN}Source bucket already pointing to original bucket${NC}"
            echo "No restoration needed."
        else
            echo -e "${YELLOW}Step 4: Restoring original DAG source bucket${NC}"
            echo "Original Bucket: $ORIGINAL_BUCKET_NAME"
            echo "Original DAG Path: ${ORIGINAL_DAG_PATH:-dags/}"
            echo ""

            if [ "$CURRENT_STATUS" = "AVAILABLE" ]; then
                echo "Updating environment to restore original source bucket..."
                echo -e "${BLUE}This will take 10-30 minutes...${NC}"
                echo ""

                aws mwaa update-environment \
                    --region "$CURRENT_REGION" \
                    --name "$MWAA_ENV_NAME" \
                    --source-bucket-arn "$ORIGINAL_BUCKET_ARN" \
                    --dag-s3-path "${ORIGINAL_DAG_PATH:-dags/}" > /dev/null

                echo -e "${GREEN}OK Initiated environment update to restore original source bucket${NC}"
                echo ""

                # Wait for update to complete
                echo -e "${YELLOW}Waiting for MWAA environment update to complete...${NC}"
                echo -e "${BLUE}This typically takes 10-30 minutes. Please be patient...${NC}"
                echo ""

                MAX_WAIT=2400  # 40 minutes maximum
                ELAPSED=0
                CHECK_INTERVAL=60  # Check every minute

                while [ $ELAPSED -lt $MAX_WAIT ]; do
                    STATUS=$(aws mwaa get-environment \
                        --region "$CURRENT_REGION" \
                        --name "$MWAA_ENV_NAME" \
                        --query 'Environment.Status' \
                        --output text 2>/dev/null)

                    MINUTES=$((ELAPSED / 60))
                    echo "  [${MINUTES}m] Environment status: $STATUS"

                    if [ "$STATUS" = "AVAILABLE" ] && [ $ELAPSED -gt 0 ]; then
                        echo ""
                        echo -e "${GREEN}OK MWAA environment update complete!${NC}"
                        break
                    elif [ "$STATUS" = "UPDATE_FAILED" ]; then
                        echo ""
                        echo -e "${YELLOW}Warning: MWAA environment update failed${NC}"
                        echo "The environment may need manual intervention."
                        break
                    fi

                    sleep $CHECK_INTERVAL
                    ELAPSED=$((ELAPSED + CHECK_INTERVAL))
                done

                if [ $ELAPSED -ge $MAX_WAIT ]; then
                    echo -e "${YELLOW}Warning: Timeout waiting for environment update${NC}"
                    echo "The update may still be in progress. Check the AWS console."
                fi
            else
                echo -e "${YELLOW}Environment is not in AVAILABLE state (current: $CURRENT_STATUS)${NC}"
                echo "Cannot update environment until it is available."
                echo "Please wait for the environment to be available and run cleanup again."
            fi
        fi
    else
        echo -e "${YELLOW}Step 4: Skipping source bucket restoration${NC}"
        echo "Original bucket information not available in Terraform outputs."
        echo ""
        echo "To manually restore the source bucket:"
        echo "  1. Go to the MWAA console"
        echo "  2. Select environment: $MWAA_ENV_NAME"
        echo "  3. Edit and restore the original source bucket configuration"
        echo ""
        echo "Alternatively, you can destroy and recreate the scenario with Terraform:"
        echo "  terraform apply -replace=module.single_account_privesc_one_hop_to_admin_mwaa_002_airflow_updateenvironment"
    fi
fi
echo ""

# Step 5: Clean up orphaned ENIs in MWAA subnets
# MWAA creates ENIs that can persist and block Terraform from deleting subnets during destroy
echo -e "${YELLOW}Step 5: Cleaning up orphaned ENIs in MWAA subnets${NC}"

cd ../../../../../..  # Go to project root
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_mwaa_002_airflow_updateenvironment.value // empty')

if [ -n "$MODULE_OUTPUT" ] && [ "$MODULE_OUTPUT" != "null" ]; then
    SUBNET_IDS=$(echo "$MODULE_OUTPUT" | jq -r '.private_subnet_ids // [] | .[]' 2>/dev/null)
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

        # Also check for in-use ENIs
        IN_USE_ENIS=$(aws ec2 describe-network-interfaces \
            --filters "Name=subnet-id,Values=$SUBNET_ID" \
            --query 'NetworkInterfaces[?Status==`in-use`].[NetworkInterfaceId,Description]' \
            --output text 2>/dev/null || echo "")

        if [ -n "$IN_USE_ENIS" ] && [ "$IN_USE_ENIS" != "None" ]; then
            echo -e "    ${YELLOW}Note: Some ENIs are still in-use (may be from active MWAA environment):${NC}"
            echo "$IN_USE_ENIS" | while read line; do
                echo "      $line"
            done
        fi
    done

    echo -e "${GREEN}OK ENI cleanup complete${NC}"
else
    echo -e "${YELLOW}Could not retrieve subnet IDs from Terraform output${NC}"
    echo "If you encounter subnet deletion errors during terraform destroy, manually delete orphaned ENIs"
fi
echo ""

# Step 6: Verify cleanup
echo -e "${YELLOW}Step 6: Verifying cleanup${NC}"

# Check that AdministratorAccess is detached
if aws iam list-attached-user-policies \
    --user-name "$STARTING_USER_NAME" \
    --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`]' \
    --output text 2>/dev/null | grep -q "AdministratorAccess"; then
    echo -e "${YELLOW}Warning: AdministratorAccess still attached to $STARTING_USER_NAME${NC}"
else
    echo -e "${GREEN}OK AdministratorAccess successfully detached from user${NC}"
fi

# Check MWAA environment status if it exists
if [ -n "$ENV_EXISTS" ]; then
    FINAL_STATUS=$(aws mwaa get-environment \
        --region "$CURRENT_REGION" \
        --name "$MWAA_ENV_NAME" \
        --query 'Environment.Status' \
        --output text 2>/dev/null || echo "UNKNOWN")

    echo "MWAA Environment Status: $FINAL_STATUS"

    if [ "$FINAL_STATUS" = "AVAILABLE" ]; then
        FINAL_SOURCE_BUCKET=$(aws mwaa get-environment \
            --region "$CURRENT_REGION" \
            --name "$MWAA_ENV_NAME" \
            --query 'Environment.SourceBucketArn' \
            --output text 2>/dev/null || echo "unknown")
        echo "Current Source Bucket: $FINAL_SOURCE_BUCKET"
    fi
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess policy from starting user"
if [ -n "$ORIGINAL_BUCKET_NAME" ] && [ "$ORIGINAL_BUCKET_NAME" != "null" ]; then
    echo "- Restored original DAG source bucket on MWAA environment"
else
    echo "- Source bucket restoration: Manual action may be required (see above)"
fi
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo ""
echo -e "${YELLOW}The MWAA infrastructure (environment, VPC, buckets) remains deployed.${NC}"
echo -e "${YELLOW}MWAA costs ~\$37/month while running.${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply.${NC}"
echo ""
