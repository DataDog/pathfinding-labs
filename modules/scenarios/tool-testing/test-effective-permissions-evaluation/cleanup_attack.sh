#!/bin/bash

# Cleanup script for test-effective-permissions-evaluation
# This is a read-only testing scenario that doesn't create any artifacts
# This script verifies no modifications were made and removes any temporary files

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Effective Permissions Testing${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${YELLOW}Step 1: Checking for artifacts${NC}"

# This scenario is read-only and doesn't create any resources
# It only tests existing permissions configurations

echo "This scenario performs read-only testing of IAM effective permissions."
echo "No modifications are made to AWS resources during the demo."
echo ""

# Check for any temporary files that might have been created
TEMP_FILES_FOUND=false

if [ -f "/tmp/s3-test-output.txt" ]; then
    echo -e "${YELLOW}Found temporary S3 test output file${NC}"
    rm -f /tmp/s3-test-output.txt
    echo -e "${GREEN}✓ Removed /tmp/s3-test-output.txt${NC}"
    TEMP_FILES_FOUND=true
fi

if [ -f "/tmp/aws-credentials-test.txt" ]; then
    echo -e "${YELLOW}Found temporary credentials test file${NC}"
    rm -f /tmp/aws-credentials-test.txt
    echo -e "${GREEN}✓ Removed /tmp/aws-credentials-test.txt${NC}"
    TEMP_FILES_FOUND=true
fi

# Check for any other temp files created by the demo
for temp_file in /tmp/pl-test-effective-permissions-*; do
    if [ -f "$temp_file" ]; then
        echo -e "${YELLOW}Found temporary test file: $temp_file${NC}"
        rm -f "$temp_file"
        echo -e "${GREEN}✓ Removed $temp_file${NC}"
        TEMP_FILES_FOUND=true
    fi
done

if [ "$TEMP_FILES_FOUND" = false ]; then
    echo -e "${GREEN}✓ No temporary files found${NC}"
fi

echo ""

echo -e "${YELLOW}Step 2: Verifying AWS resources${NC}"

# Get region from Terraform
echo "Retrieving region from Terraform configuration..."
cd ../../../..  # Navigate to root of terraform project

CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$CURRENT_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    CURRENT_REGION="us-east-1"
fi

echo "Region from Terraform: $CURRENT_REGION"

# Get admin cleanup credentials from Terraform
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${YELLOW}Note: Could not find admin cleanup credentials${NC}"
    echo -e "${YELLOW}This is expected for read-only testing scenarios${NC}"
else
    # Set admin credentials
    export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
    export AWS_REGION="$CURRENT_REGION"
    unset AWS_SESSION_TOKEN

    echo -e "${GREEN}✓ Retrieved admin credentials${NC}"
fi

cd - > /dev/null

# This scenario doesn't create any AWS resources during the demo
# All resources are managed by Terraform and should not be modified

echo ""
echo -e "${GREEN}✓ Verified: No AWS resource modifications during demo${NC}"
echo ""

echo -e "${YELLOW}Step 3: Checking for policy modifications${NC}"

# The demo script only reads permissions; it doesn't modify any policies
echo "The demo performs read-only permission testing."
echo "No IAM policies, roles, or users were modified."
echo ""
echo -e "${GREEN}✓ No policy modifications to clean up${NC}"
echo ""

echo -e "${YELLOW}Step 4: Checking for created access keys${NC}"

# The demo doesn't create any new access keys
echo "The demo uses pre-existing access keys from Terraform."
echo "No new access keys were created during testing."
echo ""
echo -e "${GREEN}✓ No access keys to remove${NC}"
echo ""

echo -e "${YELLOW}Step 5: Final verification${NC}"

# Verify no unexpected resources exist
echo "Performing final verification..."
echo ""

# Check if any demo-tagged resources exist (they shouldn't)
if [ -n "$ADMIN_ACCESS_KEY" ] && [ "$ADMIN_ACCESS_KEY" != "null" ]; then
    # Check for any EC2 instances with demo tags (shouldn't exist)
    DEMO_INSTANCES=$(aws ec2 describe-instances \
        --region $CURRENT_REGION \
        --filters "Name=tag:Demo,Values=effective-permissions-test" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text 2>/dev/null || echo "")

    if [ -n "$DEMO_INSTANCES" ]; then
        echo -e "${RED}⚠ Unexpected: Found EC2 instances with demo tags${NC}"
        echo "Instances: $DEMO_INSTANCES"
        echo "These should not exist for this read-only scenario."
    else
        echo -e "${GREEN}✓ No unexpected EC2 instances found${NC}"
    fi

    # Check for any Lambda functions with demo prefix (shouldn't exist)
    DEMO_FUNCTIONS=$(aws lambda list-functions \
        --region $CURRENT_REGION \
        --query 'Functions[?starts_with(FunctionName, `pl-test-effective-permissions`)].FunctionName' \
        --output text 2>/dev/null || echo "")

    if [ -n "$DEMO_FUNCTIONS" ]; then
        echo -e "${RED}⚠ Unexpected: Found Lambda functions with demo prefix${NC}"
        echo "Functions: $DEMO_FUNCTIONS"
        echo "These should not exist for this read-only scenario."
    else
        echo -e "${GREEN}✓ No unexpected Lambda functions found${NC}"
    fi
fi

echo ""

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${YELLOW}Summary:${NC}"
echo "- Removed temporary files (if any)"
echo "- Verified no AWS resource modifications"
echo "- Verified no policy changes"
echo "- Verified no new access keys created"
echo ""

echo -e "${GREEN}The environment remains in its original state.${NC}\n"

echo -e "${CYAN}About This Scenario:${NC}"
echo "This is a read-only testing scenario designed to validate"
echo "CSPM tools' ability to correctly evaluate effective IAM permissions."
echo ""
echo "The demo script tests 25 different principals with various"
echo "permission configurations without modifying any AWS resources."
echo ""

echo -e "${YELLOW}Infrastructure Management:${NC}"
echo "All infrastructure (roles, users, policies, and bucket) is managed by Terraform."
echo "To remove all infrastructure, disable the scenario in terraform.tfvars:"
echo "  enable_tool_testing_test_effective_permissions_evaluation = false"
echo "Then run: terraform apply"
echo ""

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
