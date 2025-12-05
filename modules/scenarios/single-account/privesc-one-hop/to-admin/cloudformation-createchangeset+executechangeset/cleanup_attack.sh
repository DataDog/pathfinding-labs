#!/bin/bash

# Cleanup script for cloudformation:CreateChangeSet and ExecuteChangeSet privilege escalation demo
# This script removes the escalated role and restores the stack to its original state

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STACK_NAME="pl-prod-cfcs-to-admin-target-stack"
CHANGESET_NAME="pl-prod-cfcs-escalation-changeset"
ESCALATED_ROLE_NAME="pl-prod-cfcs-to-admin-escalated-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: CloudFormation CreateChangeSet+ExecuteChangeSet${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials and region from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Disable OTEL to prevent terraform output issues
export OTEL_TRACES_EXPORTER=""

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

# Get account ID and resource suffix for template restoration
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
RESOURCE_SUFFIX=$(terraform output -raw resource_suffix 2>/dev/null)

echo "Account ID: $ACCOUNT_ID"
echo "Resource Suffix: $RESOURCE_SUFFIX"
echo ""

# Navigate back to scenario directory
cd - > /dev/null

# Step 2: Delete any pending ChangeSets
echo -e "${YELLOW}Step 2: Checking for pending ChangeSets${NC}"
echo "ChangeSet name: $CHANGESET_NAME"

if aws cloudformation describe-change-set \
    --region $CURRENT_REGION \
    --stack-name $STACK_NAME \
    --change-set-name $CHANGESET_NAME &> /dev/null; then

    echo "Found ChangeSet, deleting..."
    aws cloudformation delete-change-set \
        --region $CURRENT_REGION \
        --stack-name $STACK_NAME \
        --change-set-name $CHANGESET_NAME

    echo -e "${GREEN}✓ Deleted ChangeSet: $CHANGESET_NAME${NC}"
else
    echo -e "${YELLOW}No ChangeSet found (may have already been executed or deleted)${NC}"
fi
echo ""

# Step 3: Restore CloudFormation stack to original benign state
echo -e "${YELLOW}Step 3: Restoring CloudFormation stack to original state${NC}"
echo "Stack name: $STACK_NAME"
echo ""

# Check if stack exists and what state it's in
if ! aws cloudformation describe-stacks --region $CURRENT_REGION --stack-name $STACK_NAME &> /dev/null; then
    echo -e "${YELLOW}Stack $STACK_NAME not found (may have been deleted manually)${NC}"
else
    echo "Creating original benign template..."

    # Recreate the original benign template
    ORIGINAL_TEMPLATE=$(cat <<EOF
{
  "AWSTemplateFormatVersion": "2010-09-09",
  "Description": "Initial benign template for CloudFormation CreateChangeSet+ExecuteChangeSet scenario",
  "Resources": {
    "InitialBucket": {
      "Type": "AWS::S3::Bucket",
      "Properties": {
        "BucketName": "pl-prod-cfcs-to-admin-initial-bucket-${ACCOUNT_ID}-${RESOURCE_SUFFIX}",
        "Tags": [
          {
            "Key": "Name",
            "Value": "pl-prod-cfcs-to-admin-initial-bucket"
          },
          {
            "Key": "Environment",
            "Value": "prod"
          },
          {
            "Key": "Scenario",
            "Value": "cloudformation-createchangeset-executechangeset"
          },
          {
            "Key": "Purpose",
            "Value": "initial-benign-resource"
          }
        ]
      }
    }
  },
  "Outputs": {
    "BucketName": {
      "Description": "Name of the initial S3 bucket",
      "Value": {
        "Ref": "InitialBucket"
      }
    }
  }
}
EOF
)

    # Save the original template
    echo "$ORIGINAL_TEMPLATE" > /tmp/original-changeset-template.json
    echo "Original template saved to: /tmp/original-changeset-template.json"
    echo ""

    # Check if the escalated role exists in the stack
    CURRENT_RESOURCES=$(aws cloudformation list-stack-resources \
        --region $CURRENT_REGION \
        --stack-name $STACK_NAME \
        --query 'StackResourceSummaries[?LogicalResourceId==`EscalatedAdminRole`].LogicalResourceId' \
        --output text)

    if [ -n "$CURRENT_RESOURCES" ]; then
        echo "Escalated role found in stack, creating ChangeSet to remove it..."

        # Create a ChangeSet to restore the original template
        CLEANUP_CHANGESET_NAME="pl-prod-cfcs-cleanup-changeset-$(date +%s)"

        aws cloudformation create-change-set \
            --region $CURRENT_REGION \
            --stack-name $STACK_NAME \
            --change-set-name $CLEANUP_CHANGESET_NAME \
            --template-body file:///tmp/original-changeset-template.json \
            --capabilities CAPABILITY_NAMED_IAM \
            --change-set-type UPDATE \
            --description "Cleanup - remove escalated role"

        echo "Waiting for cleanup ChangeSet to be ready..."
        sleep 10

        # Execute the cleanup ChangeSet
        echo "Executing cleanup ChangeSet..."
        aws cloudformation execute-change-set \
            --region $CURRENT_REGION \
            --stack-name $STACK_NAME \
            --change-set-name $CLEANUP_CHANGESET_NAME

        echo "Waiting for stack update to complete..."
        aws --region $CURRENT_REGION cloudformation wait stack-update-complete --stack-name $STACK_NAME
        echo -e "${GREEN}✓ Stack restored to original state${NC}"
    else
        echo -e "${YELLOW}Stack is already in original state (no escalated role found)${NC}"
    fi
fi
echo ""

# Step 4: Ensure escalated role is deleted (if it somehow exists outside the stack)
echo -e "${YELLOW}Step 4: Verifying escalated role is removed${NC}"
echo "Checking for role: $ESCALATED_ROLE_NAME"

if aws iam get-role --role-name $ESCALATED_ROLE_NAME &> /dev/null; then
    echo -e "${YELLOW}Warning: Escalated role still exists, attempting manual deletion...${NC}"

    # Detach managed policies
    echo "Detaching managed policies..."
    ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
        --role-name $ESCALATED_ROLE_NAME \
        --query 'AttachedPolicies[*].PolicyArn' \
        --output text)

    for POLICY_ARN in $ATTACHED_POLICIES; do
        echo "  Detaching: $POLICY_ARN"
        aws iam detach-role-policy \
            --role-name $ESCALATED_ROLE_NAME \
            --policy-arn $POLICY_ARN
    done

    # Delete inline policies
    echo "Deleting inline policies..."
    INLINE_POLICIES=$(aws iam list-role-policies \
        --role-name $ESCALATED_ROLE_NAME \
        --query 'PolicyNames[*]' \
        --output text)

    for POLICY_NAME in $INLINE_POLICIES; do
        echo "  Deleting: $POLICY_NAME"
        aws iam delete-role-policy \
            --role-name $ESCALATED_ROLE_NAME \
            --policy-name $POLICY_NAME
    done

    # Delete the role
    echo "Deleting role..."
    aws iam delete-role --role-name $ESCALATED_ROLE_NAME
    echo -e "${GREEN}✓ Manually deleted escalated role${NC}"
else
    echo -e "${GREEN}✓ Escalated role not found (successfully removed)${NC}"
fi
echo ""

# Step 5: Clean up temporary files
echo -e "${YELLOW}Step 5: Cleaning up temporary files${NC}"
if [ -f /tmp/malicious-changeset-template.json ]; then
    rm -f /tmp/malicious-changeset-template.json
    echo "Removed: /tmp/malicious-changeset-template.json"
fi
if [ -f /tmp/original-changeset-template.json ]; then
    rm -f /tmp/original-changeset-template.json
    echo "Removed: /tmp/original-changeset-template.json"
fi
echo -e "${GREEN}✓ Temporary files cleaned up${NC}\n"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Deleted any pending ChangeSets"
echo "- Restored CloudFormation stack to original benign state"
echo "- Removed escalated admin role: $ESCALATED_ROLE_NAME"
echo "- Cleaned up temporary template files"
echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (stack, users, and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
