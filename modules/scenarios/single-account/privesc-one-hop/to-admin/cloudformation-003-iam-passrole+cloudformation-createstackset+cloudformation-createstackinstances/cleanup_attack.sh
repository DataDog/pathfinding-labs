#!/bin/bash

# Cleanup script for iam:PassRole + cloudformation:CreateStackSet + cloudformation:CreateStackInstances privilege escalation demo
# This script deletes the CloudFormation StackSet, stack instances, and removes the escalated role

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STACKSET_NAME="pl-prod-cloudformation-003-escalation-stackset"
ESCALATED_ROLE_NAME="pl-prod-cloudformation-003-to-admin-escalated-role"
TEMPLATE_FILE="/tmp/cfn-stackset-escalation-template.yaml"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + CloudFormation StackSet Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 0: Get admin credentials and region from Terraform
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

# Step 1: Check if StackSet exists
echo -e "${YELLOW}Step 2: Checking for CloudFormation StackSet${NC}"
echo "StackSet name: $STACKSET_NAME"

STACKSET_STATUS=$(aws cloudformation describe-stack-set \
    --region $CURRENT_REGION \
    --stack-set-name $STACKSET_NAME \
    --query 'StackSet.Status' \
    --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$STACKSET_STATUS" = "NOT_FOUND" ]; then
    echo -e "${YELLOW}StackSet not found (may already be deleted)${NC}"
    echo ""
else
    echo "StackSet status: $STACKSET_STATUS"
    echo -e "${GREEN}✓ Found StackSet${NC}\n"

    # Step 2: Delete stack instances
    echo -e "${YELLOW}Step 3: Deleting stack instances${NC}"
    echo "Removing instances from account: $ACCOUNT_ID, region: $CURRENT_REGION"
    echo ""

    # Check if there are any instances
    INSTANCE_COUNT=$(aws cloudformation list-stack-instances \
        --region $CURRENT_REGION \
        --stack-set-name $STACKSET_NAME \
        --query 'length(Summaries)' \
        --output text 2>/dev/null || echo "0")

    if [ "$INSTANCE_COUNT" -eq 0 ]; then
        echo -e "${YELLOW}No stack instances found${NC}"
        echo ""
    else
        echo "Found $INSTANCE_COUNT stack instance(s)"

        # Delete instances
        DELETE_OPERATION_ID=$(aws cloudformation delete-stack-instances \
            --region $CURRENT_REGION \
            --stack-set-name $STACKSET_NAME \
            --accounts $ACCOUNT_ID \
            --regions $CURRENT_REGION \
            --no-retain-stacks \
            --operation-preferences FailureToleranceCount=0,MaxConcurrentCount=1 \
            --query 'OperationId' \
            --output text 2>/dev/null || echo "")

        if [ -n "$DELETE_OPERATION_ID" ]; then
            echo "Delete operation ID: $DELETE_OPERATION_ID"
            echo -e "${GREEN}✓ Stack instance deletion initiated${NC}\n"

            # Step 3: Wait for instance deletion to complete
            echo -e "${YELLOW}Step 4: Waiting for stack instance deletion to complete${NC}"
            echo "This may take 1-2 minutes..."
            echo ""

            MAX_WAIT=300  # 5 minutes
            WAIT_TIME=0
            DELETION_COMPLETE=false

            while [ $WAIT_TIME -lt $MAX_WAIT ]; do
                DELETE_STATUS=$(aws cloudformation describe-stack-set-operation \
                    --region $CURRENT_REGION \
                    --stack-set-name $STACKSET_NAME \
                    --operation-id $DELETE_OPERATION_ID \
                    --query 'StackSetOperation.Status' \
                    --output text 2>/dev/null || echo "NOT_FOUND")

                echo "Operation status: $DELETE_STATUS"

                if [ "$DELETE_STATUS" = "SUCCEEDED" ]; then
                    echo -e "${GREEN}✓ Stack instances deleted successfully${NC}"
                    DELETION_COMPLETE=true
                    break
                elif [ "$DELETE_STATUS" = "FAILED" ] || [ "$DELETE_STATUS" = "STOPPED" ]; then
                    echo -e "${RED}Error: Stack instance deletion failed${NC}"
                    echo "Operation status: $DELETE_STATUS"
                    aws cloudformation describe-stack-set-operation \
                        --region $CURRENT_REGION \
                        --stack-set-name $STACKSET_NAME \
                        --operation-id $DELETE_OPERATION_ID \
                        --output table
                    break
                fi

                sleep 10
                WAIT_TIME=$((WAIT_TIME + 10))
            done

            if [ "$DELETION_COMPLETE" = false ] && [ "$DELETE_STATUS" != "FAILED" ]; then
                echo -e "${YELLOW}⚠ Stack instance deletion may still be in progress${NC}"
                echo "Current status: $DELETE_STATUS"
            fi
            echo ""
        else
            echo -e "${YELLOW}Could not initiate stack instance deletion${NC}"
            echo ""
        fi
    fi

    # Step 4: Delete the StackSet
    echo -e "${YELLOW}Step 5: Deleting CloudFormation StackSet${NC}"
    echo "StackSet name: $STACKSET_NAME"

    aws cloudformation delete-stack-set \
        --region $CURRENT_REGION \
        --stack-set-name $STACKSET_NAME 2>/dev/null || true

    echo -e "${GREEN}✓ StackSet deletion initiated${NC}\n"

    # Wait a moment to verify deletion
    sleep 5

    # Check if StackSet is deleted
    FINAL_STACKSET_STATUS=$(aws cloudformation describe-stack-set \
        --region $CURRENT_REGION \
        --stack-set-name $STACKSET_NAME \
        --query 'StackSet.Status' \
        --output text 2>/dev/null || echo "NOT_FOUND")

    if [ "$FINAL_STACKSET_STATUS" = "NOT_FOUND" ]; then
        echo -e "${GREEN}✓ StackSet deleted successfully${NC}"
    else
        echo -e "${YELLOW}⚠ StackSet status: $FINAL_STACKSET_STATUS${NC}"
        echo "StackSet deletion may still be in progress"
    fi
    echo ""
fi

# Step 5: Verify escalated role is deleted
echo -e "${YELLOW}Step 6: Verifying escalated role deletion${NC}"
echo "Checking for role: $ESCALATED_ROLE_NAME"

if aws iam get-role --role-name $ESCALATED_ROLE_NAME &> /dev/null; then
    echo -e "${YELLOW}⚠ Role still exists (CloudFormation StackSet should have deleted it)${NC}"
    echo "You may need to wait longer or manually delete the role"
else
    echo -e "${GREEN}✓ Escalated role has been deleted${NC}"
fi
echo ""

# Step 6: Clean up template file
echo -e "${YELLOW}Step 7: Cleaning up temporary files${NC}"

if [ -f "$TEMPLATE_FILE" ]; then
    rm -f "$TEMPLATE_FILE"
    echo -e "${GREEN}✓ Deleted template file: $TEMPLATE_FILE${NC}"
else
    echo -e "${YELLOW}Template file not found (may already be deleted)${NC}"
fi
echo ""

# Step 7: Final verification
echo -e "${YELLOW}Step 8: Verifying cleanup${NC}"

# Check StackSet status one final time
FINAL_STACKSET_CHECK=$(aws cloudformation describe-stack-set \
    --region $CURRENT_REGION \
    --stack-set-name $STACKSET_NAME \
    --query 'StackSet.Status' \
    --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$FINAL_STACKSET_CHECK" = "NOT_FOUND" ]; then
    echo -e "${GREEN}✓ CloudFormation StackSet confirmed deleted${NC}"
else
    echo -e "${YELLOW}⚠ StackSet status: $FINAL_STACKSET_CHECK${NC}"
fi

# Check role status one final time
if aws iam get-role --role-name $ESCALATED_ROLE_NAME &> /dev/null; then
    echo -e "${YELLOW}⚠ Escalated role still exists${NC}"
    echo "To manually delete the role, run:"
    echo "  aws iam delete-role --role-name $ESCALATED_ROLE_NAME"
else
    echo -e "${GREEN}✓ Escalated role confirmed deleted${NC}"
fi

# Check for temporary file
if [ -f "$TEMPLATE_FILE" ]; then
    echo -e "${YELLOW}⚠ Template file still exists${NC}"
else
    echo -e "${GREEN}✓ Temporary files removed${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Deleted stack instances from account: $ACCOUNT_ID, region: $CURRENT_REGION"
echo "- Deleted CloudFormation StackSet: $STACKSET_NAME"
echo "- Removed escalated role: $ESCALATED_ROLE_NAME (via StackSet deletion)"
echo "- Cleaned up temporary template file"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
