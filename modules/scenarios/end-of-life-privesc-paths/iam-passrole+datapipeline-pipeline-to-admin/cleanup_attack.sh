#!/bin/bash

# Cleanup script for iam:PassRole + datapipeline privilege escalation demo
# This script removes the Data Pipeline and policy attachment created during the demo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-datapipeline-001-to-admin-starting-user"
PIPELINE_NAME="pl-privesc-datapipeline-demo"
PIPELINE_DEFINITION_FILE="/tmp/pipeline_definition.json"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + Data Pipeline Demo Cleanup${NC}"
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
echo -e "${YELLOW}Step 2: Detaching AdministratorAccess policy from user${NC}"
echo "User: $STARTING_USER"

# Check if the policy is attached
if aws iam list-attached-user-policies \
    --user-name $STARTING_USER \
    --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`]' \
    --output text | grep -q "AdministratorAccess"; then

    echo "Found AdministratorAccess policy attached to $STARTING_USER"

    # Detach the policy
    aws iam detach-user-policy \
        --user-name $STARTING_USER \
        --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

    echo -e "${GREEN}✓ Detached AdministratorAccess policy from $STARTING_USER${NC}"
else
    echo -e "${YELLOW}AdministratorAccess policy not attached to $STARTING_USER (may already be detached)${NC}"
fi
echo ""

# Step 3: Find and delete Data Pipeline(s)
echo -e "${YELLOW}Step 3: Finding and deleting Data Pipelines${NC}"
echo "Searching for pipelines with name pattern: $PIPELINE_NAME"

# List all pipelines and find ones matching our pattern
PIPELINE_IDS=$(aws datapipeline list-pipelines \
    --region $CURRENT_REGION \
    --query "pipelineIdList[?name=='$PIPELINE_NAME'].id" \
    --output text)

if [ -n "$PIPELINE_IDS" ]; then
    echo "Found pipelines to delete:"
    for PIPELINE_ID in $PIPELINE_IDS; do
        echo "  Pipeline ID: $PIPELINE_ID"

        # Delete the pipeline
        aws datapipeline delete-pipeline \
            --region $CURRENT_REGION \
            --pipeline-id "$PIPELINE_ID"

        echo -e "${GREEN}✓ Deleted pipeline: $PIPELINE_ID${NC}"
    done
else
    echo -e "${YELLOW}No pipelines found with name: $PIPELINE_NAME (may already be deleted)${NC}"
fi
echo ""

# Step 4: Terminate any EC2 instances created by the pipeline
echo -e "${YELLOW}Step 4: Finding and terminating EC2 instances created by Data Pipeline${NC}"
echo "Searching for instances created by Data Pipeline in region: $CURRENT_REGION"
echo ""

# Find instances with Data Pipeline tags
# Data Pipeline creates instances with tags like @pipelineId
INSTANCE_IDS=$(aws ec2 describe-instances \
    --region $CURRENT_REGION \
    --filters "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[*].Instances[?Tags[?Key==`@pipelineId`]].InstanceId' \
    --output text)

if [ -n "$INSTANCE_IDS" ]; then
    echo "Found Data Pipeline EC2 instances:"
    for INSTANCE_ID in $INSTANCE_IDS; do
        echo "  Instance ID: $INSTANCE_ID"

        # Terminate the instance
        aws ec2 terminate-instances \
            --region $CURRENT_REGION \
            --instance-ids "$INSTANCE_ID" \
            --output text > /dev/null

        echo -e "${GREEN}✓ Terminated instance: $INSTANCE_ID${NC}"
    done

    echo ""
    echo "Waiting for instances to terminate (this may take a minute)..."
    for INSTANCE_ID in $INSTANCE_IDS; do
        aws ec2 wait instance-terminated \
            --region $CURRENT_REGION \
            --instance-ids "$INSTANCE_ID" 2>/dev/null || true
    done
    echo -e "${GREEN}✓ All instances terminated${NC}"
else
    echo -e "${YELLOW}No Data Pipeline EC2 instances found (may already be terminated)${NC}"
fi
echo ""

# Step 5: Clean up local files
echo -e "${YELLOW}Step 5: Cleaning up local files${NC}"
if [ -f "$PIPELINE_DEFINITION_FILE" ]; then
    rm -f "$PIPELINE_DEFINITION_FILE"
    echo -e "${GREEN}✓ Removed pipeline definition file${NC}"
else
    echo -e "${YELLOW}Pipeline definition file not found (may already be deleted)${NC}"
fi
echo ""

# Step 6: Verify cleanup
echo -e "${YELLOW}Step 6: Verifying cleanup${NC}"

# Check that the policy is detached
if aws iam list-attached-user-policies \
    --user-name $STARTING_USER \
    --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`]' \
    --output text | grep -q "AdministratorAccess"; then
    echo -e "${YELLOW}⚠ Warning: AdministratorAccess policy still attached to $STARTING_USER${NC}"
else
    echo -e "${GREEN}✓ AdministratorAccess policy successfully detached${NC}"
fi

# Check that pipelines are deleted
REMAINING_PIPELINES=$(aws datapipeline list-pipelines \
    --region $CURRENT_REGION \
    --query "pipelineIdList[?name=='$PIPELINE_NAME'].id" \
    --output text)

if [ -n "$REMAINING_PIPELINES" ]; then
    echo -e "${YELLOW}⚠ Warning: Some pipelines may still exist${NC}"
else
    echo -e "${GREEN}✓ All demo pipelines successfully deleted${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess policy from: $STARTING_USER"
echo "- Deleted Data Pipeline(s): $PIPELINE_NAME"
echo "- Terminated EC2 instances created by Data Pipeline"
echo "- Cleaned up local files"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
