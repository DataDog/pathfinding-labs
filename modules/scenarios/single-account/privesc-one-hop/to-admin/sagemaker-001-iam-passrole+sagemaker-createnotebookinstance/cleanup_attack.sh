#!/bin/bash

# Cleanup script for iam-passrole+sagemaker-createnotebookinstance privilege escalation demo
# This script removes demo artifacts: deletes notebook instances and detaches admin policy from starting user

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-sagemaker-001-to-admin-starting-user"
DEMO_NOTEBOOK_PREFIX="pl-demo-notebook-"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: SageMaker CreateNotebookInstance${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials and region from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get admin cleanup user credentials from root terraform output
ADMIN_ACCESS_KEY=$(OTEL_TRACES_EXPORTER= terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(OTEL_TRACES_EXPORTER= terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)
CURRENT_REGION=$(OTEL_TRACES_EXPORTER= terraform output -raw aws_region 2>/dev/null || echo "")

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

# Step 2: Find and delete demo notebook instances
echo -e "${YELLOW}Step 2: Finding and deleting demo notebook instances${NC}"
echo "Searching for notebooks with prefix: $DEMO_NOTEBOOK_PREFIX"
echo ""

# List all notebook instances that match our demo prefix
NOTEBOOK_INSTANCES=$(aws sagemaker list-notebook-instances \
    --region $CURRENT_REGION \
    --name-contains $DEMO_NOTEBOOK_PREFIX \
    --query 'NotebookInstances[*].NotebookInstanceName' \
    --output text)

if [ -z "$NOTEBOOK_INSTANCES" ]; then
    echo -e "${YELLOW}No demo notebook instances found (may already be deleted)${NC}"
else
    echo "Found notebook instances to delete:"
    for NOTEBOOK in $NOTEBOOK_INSTANCES; do
        echo "  - $NOTEBOOK"
    done
    echo ""

    # Stop and delete each notebook instance
    for NOTEBOOK in $NOTEBOOK_INSTANCES; do
        echo "Processing notebook: $NOTEBOOK"

        # Check current status
        STATUS=$(aws sagemaker describe-notebook-instance \
            --region $CURRENT_REGION \
            --notebook-instance-name $NOTEBOOK \
            --query 'NotebookInstanceStatus' \
            --output text 2>/dev/null || echo "NotFound")

        if [ "$STATUS" == "NotFound" ]; then
            echo -e "${YELLOW}  Notebook not found (may already be deleted)${NC}"
            continue
        fi

        echo "  Current status: $STATUS"

        # Stop the notebook if it's running
        if [ "$STATUS" == "InService" ] || [ "$STATUS" == "Pending" ]; then
            echo "  Stopping notebook..."
            aws sagemaker stop-notebook-instance \
                --region $CURRENT_REGION \
                --notebook-instance-name $NOTEBOOK 2>/dev/null || true

            # Wait for notebook to stop
            echo "  Waiting for notebook to stop..."
            MAX_ATTEMPTS=20  # 20 attempts * 15 seconds = 5 minutes
            ATTEMPT=0

            while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
                STATUS=$(aws sagemaker describe-notebook-instance \
                    --region $CURRENT_REGION \
                    --notebook-instance-name $NOTEBOOK \
                    --query 'NotebookInstanceStatus' \
                    --output text 2>/dev/null || echo "NotFound")

                if [ "$STATUS" == "Stopped" ]; then
                    echo -e "${GREEN}  ✓ Notebook stopped${NC}"
                    break
                elif [ "$STATUS" == "NotFound" ]; then
                    echo -e "${YELLOW}  Notebook disappeared (already deleted)${NC}"
                    break
                fi

                ATTEMPT=$((ATTEMPT + 1))
                echo "  Status: $STATUS (attempt $ATTEMPT/$MAX_ATTEMPTS)"
                sleep 15
            done
        fi

        # Delete the notebook
        if [ "$STATUS" == "Stopped" ]; then
            echo "  Deleting notebook..."
            aws sagemaker delete-notebook-instance \
                --region $CURRENT_REGION \
                --notebook-instance-name $NOTEBOOK

            # Wait for deletion to complete
            echo "  Waiting for deletion to complete..."
            MAX_ATTEMPTS=20  # 20 attempts * 15 seconds = 5 minutes
            ATTEMPT=0

            while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
                if ! aws sagemaker describe-notebook-instance \
                    --region $CURRENT_REGION \
                    --notebook-instance-name $NOTEBOOK \
                    --query 'NotebookInstanceStatus' \
                    --output text &>/dev/null; then
                    echo -e "${GREEN}  ✓ Notebook deleted${NC}"
                    break
                fi

                ATTEMPT=$((ATTEMPT + 1))
                echo "  Deleting... (attempt $ATTEMPT/$MAX_ATTEMPTS)"
                sleep 15
            done
        fi

        echo ""
    done

    echo -e "${GREEN}✓ Processed all demo notebook instances${NC}"
fi
echo ""

# Step 3: Detach AdministratorAccess policy from starting user
echo -e "${YELLOW}Step 3: Removing AdministratorAccess policy from starting user${NC}"
echo "User: $STARTING_USER"

# Check if the policy is attached
if aws iam list-attached-user-policies --user-name $STARTING_USER --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`]' --output text | grep -q "AdministratorAccess"; then
    echo "Detaching AdministratorAccess policy..."
    aws iam detach-user-policy \
        --user-name $STARTING_USER \
        --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

    echo -e "${GREEN}✓ Detached AdministratorAccess policy${NC}"
else
    echo -e "${YELLOW}AdministratorAccess policy not attached (may already be removed)${NC}"
fi
echo ""

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Stopped and deleted all demo SageMaker notebook instances"
echo "- Removed AdministratorAccess policy from starting user"
echo "- Starting user restored to original permissions"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
