#!/bin/bash

# Cleanup script for cloudformation:UpdateStackSet privilege escalation demo
# This script removes the escalated role and restores the StackSet to its original state


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
STACKSET_NAME="pl-prod-cloudformation-004-to-admin-stackset"
ADMIN_ROLE_NAME="pl-prod-cloudformation-004-to-admin-stackset-admin-role"
EXECUTION_ROLE_NAME="pl-prod-cloudformation-004-to-admin-stackset-execution-role"
ESCALATED_ROLE_NAME="pl-prod-cloudformation-004-to-admin-escalated-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: CloudFormation UpdateStackSet${NC}"
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

# Step 2: Restore CloudFormation StackSet to original benign state
echo -e "${YELLOW}Step 2: Restoring CloudFormation StackSet to original state${NC}"
echo "StackSet name: $STACKSET_NAME"
echo ""

# Check if StackSet exists
if ! aws cloudformation describe-stack-set --region $CURRENT_REGION --stack-set-name $STACKSET_NAME &> /dev/null; then
    echo -e "${YELLOW}StackSet $STACKSET_NAME not found (may have been deleted manually)${NC}"
else
    echo "Creating original benign template..."

    # Recreate the original benign template
    ORIGINAL_TEMPLATE=$(cat <<EOF
{
  "AWSTemplateFormatVersion": "2010-09-09",
  "Description": "Benign initial template - creates a simple S3 bucket",
  "Resources": {
    "BenignBucket": {
      "Type": "AWS::S3::Bucket",
      "Properties": {
        "BucketName": "pl-prod-cloudformation-004-benign-${ACCOUNT_ID}-${RESOURCE_SUFFIX}",
        "Tags": [
          {
            "Key": "Name",
            "Value": "pl-prod-cloudformation-004-benign-bucket"
          },
          {
            "Key": "Environment",
            "Value": "prod"
          },
          {
            "Key": "Scenario",
            "Value": "cloudformation-updatestackset"
          },
          {
            "Key": "Purpose",
            "Value": "benign-initial-resource"
          }
        ]
      }
    }
  },
  "Outputs": {
    "BucketName": {
      "Description": "Name of the benign S3 bucket",
      "Value": {
        "Ref": "BenignBucket"
      }
    }
  }
}
EOF
)

    # Save the original template
    echo "$ORIGINAL_TEMPLATE" > /tmp/original-stackset-template.json
    echo "Original template saved to: /tmp/original-stackset-template.json"
    echo ""

    # Check if the escalated role exists in the StackSet template
    # We do this by getting the current template and checking for the role
    CURRENT_TEMPLATE=$(aws cloudformation describe-stack-set \
        --region $CURRENT_REGION \
        --stack-set-name $STACKSET_NAME \
        --query 'StackSet.TemplateBody' \
        --output text)

    if echo "$CURRENT_TEMPLATE" | grep -q "EscalatedAdminRole"; then
        echo "Escalated role found in StackSet template, updating to remove it..."

        ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ADMIN_ROLE_NAME}"

        # Update the StackSet back to the original template
        OPERATION_ID=$(aws cloudformation update-stack-set \
            --region $CURRENT_REGION \
            --stack-set-name $STACKSET_NAME \
            --template-body file:///tmp/original-stackset-template.json \
            --administration-role-arn $ADMIN_ROLE_ARN \
            --execution-role-name $EXECUTION_ROLE_NAME \
            --capabilities CAPABILITY_NAMED_IAM \
            --query 'OperationId' \
            --output text)

        echo "StackSet update operation ID: $OPERATION_ID"
        echo ""

        # Wait for UpdateStackSet to complete
        echo "Waiting for StackSet update to complete..."
        while true; do
            STACKSET_STATUS=$(aws cloudformation describe-stack-set-operation \
                --region $CURRENT_REGION \
                --stack-set-name $STACKSET_NAME \
                --operation-id $OPERATION_ID \
                --query 'StackSetOperation.Status' \
                --output text)

            echo "StackSet update status: $STACKSET_STATUS"

            if [ "$STACKSET_STATUS" == "SUCCEEDED" ]; then
                echo -e "${GREEN}✓ StackSet update completed${NC}"
                break
            elif [ "$STACKSET_STATUS" == "FAILED" ] || [ "$STACKSET_STATUS" == "STOPPED" ]; then
                echo -e "${RED}⚠ StackSet update failed${NC}"
                break
            fi

            sleep 5
        done
        echo ""
        echo -e "${GREEN}✓ StackSet restored to original state${NC}"
    else
        echo -e "${YELLOW}StackSet is already in original state (no escalated role found)${NC}"
    fi
fi
echo ""

# Step 3: Ensure escalated role is deleted (if it somehow exists outside the StackSet)
echo -e "${YELLOW}Step 3: Verifying escalated role is removed${NC}"
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

# Step 4: Clean up temporary files
echo -e "${YELLOW}Step 4: Cleaning up temporary files${NC}"
if [ -f /tmp/malicious-stackset-template.json ]; then
    rm -f /tmp/malicious-stackset-template.json
    echo "Removed: /tmp/malicious-stackset-template.json"
fi
if [ -f /tmp/original-stackset-template.json ]; then
    rm -f /tmp/original-stackset-template.json
    echo "Removed: /tmp/original-stackset-template.json"
fi
echo -e "${GREEN}✓ Temporary files cleaned up${NC}\n"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Restored CloudFormation StackSet to original benign state"
echo "- Removed escalated admin role: $ESCALATED_ROLE_NAME"
echo "- Cleaned up temporary template files"
echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (StackSet, users, and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
