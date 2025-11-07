#!/bin/bash

# Cleanup script for ssm:StartSession privilege escalation demo
# This scenario is read-only and does not create persistent artifacts

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SSM StartSession Demo Cleanup${NC}"
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

# Step 2: Check for SSM session history (informational only)
echo -e "${YELLOW}Step 2: Checking for SSM session history${NC}"
echo "Note: SSM sessions are logged and retained for auditing purposes"

# Get module output to find instance ID
cd ../../../../../..
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_ssm_startsession.value // empty')
INSTANCE_ID=$(echo "$MODULE_OUTPUT" | jq -r '.ec2_instance_id // empty')
cd - > /dev/null

if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "null" ]; then
    echo "Checking recent SSM sessions for instance: $INSTANCE_ID"
    echo ""

    # List recent session history
    RECENT_SESSIONS=$(aws ssm describe-sessions \
        --region $CURRENT_REGION \
        --state History \
        --max-results 5 \
        --filters "key=Target,value=$INSTANCE_ID" \
        --query 'Sessions[*].[SessionId,StartDate,EndDate,Status]' \
        --output text 2>/dev/null || echo "")

    if [ -n "$RECENT_SESSIONS" ]; then
        echo "Recent SSM sessions found:"
        echo "$RECENT_SESSIONS"
        echo ""
        echo -e "${BLUE}Session Information:${NC}"
        echo "- Sessions are logged in CloudTrail (ssm:StartSession events)"
        echo "- Session logs may be stored in S3/CloudWatch (if configured)"
        echo "- Session history is retained in SSM for auditing"
        echo ""
        echo -e "${YELLOW}These sessions cannot be deleted - they are retained for compliance${NC}"
    else
        echo -e "${GREEN}✓ No recent SSM sessions found (or session history not accessible)${NC}"
    fi
else
    echo -e "${YELLOW}Could not retrieve instance ID from Terraform output${NC}"
fi
echo ""

# Step 3: Clean up environment variables
echo -e "${YELLOW}Step 3: Cleaning up environment variables${NC}"
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN
unset AWS_REGION
echo -e "${GREEN}✓ Cleared AWS environment variables${NC}"
echo ""

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Checked SSM session history (retained for auditing)"
echo "- Cleared environment variables"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (EC2 instance, IAM roles, and users) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}"
echo ""
echo -e "${BLUE}Note: This scenario does not create persistent artifacts that require cleanup.${NC}"
echo -e "${BLUE}The SSM session was interactive and read-only:${NC}"
echo "  - No commands were executed via SendCommand"
echo "  - No resources were created or modified"
echo "  - Only credentials were read from IMDS"
echo "  - Session activity is logged in SSM Session Manager and CloudTrail"
echo ""
echo -e "${BLUE}What was logged:${NC}"
echo "  - CloudTrail: ssm:StartSession API call"
echo "  - SSM Session Manager: Complete session history"
echo "  - CloudWatch Logs: Session commands (if logging enabled)"
echo ""
echo -e "${YELLOW}These logs are retained for security auditing and cannot be deleted.${NC}\n"
