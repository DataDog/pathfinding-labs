#!/bin/bash

# Cleanup script for ssm:StartSession privilege escalation demo (to-bucket)
# This scenario does not create persistent artifacts - it's a read-only attack
# This script cleans up any local files and environment variables

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SSM StartSession to S3 Bucket Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get region from Terraform
echo -e "${YELLOW}Step 1: Getting region from Terraform configuration${NC}"
cd ../../../../../..  # Navigate to root of terraform project

CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$CURRENT_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    CURRENT_REGION="us-east-1"
fi

echo "Region from Terraform: $CURRENT_REGION"
echo ""

# Get module output to find instance ID (informational only)
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_bucket_ssm_001_ssm_startsession.value // empty')
INSTANCE_ID=$(echo "$MODULE_OUTPUT" | jq -r '.ec2_instance_id // empty')

# Navigate back to scenario directory
cd - > /dev/null

# Step 2: Check for SSM session history (informational only)
echo -e "${YELLOW}Step 2: Checking for SSM session history${NC}"
echo "Note: SSM sessions are automatically logged in CloudTrail and Session Manager"

if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "null" ]; then
    echo "Target instance: $INSTANCE_ID"
    echo -e "${BLUE}SSM sessions are recorded in:${NC}"
    echo "  - AWS CloudTrail (ssm:StartSession events)"
    echo "  - AWS Systems Manager Session Manager"
    echo ""
    echo -e "${YELLOW}Session history is maintained by AWS and does not require cleanup${NC}"
else
    echo -e "${YELLOW}Could not retrieve instance ID from Terraform output${NC}"
fi
echo ""

# Step 3: Clean up any local files (if demo created any)
echo -e "${YELLOW}Step 3: Cleaning up local files${NC}"
if [ -f "sensitive-data.txt" ]; then
    rm -f sensitive-data.txt
    echo -e "${GREEN}✓ Removed downloaded sensitive-data.txt${NC}"
else
    echo -e "${GREEN}✓ No local files to clean up${NC}"
fi
echo ""

# Step 4: Clean up environment variables
echo -e "${YELLOW}Step 4: Cleaning up environment variables${NC}"
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
echo "- Verified SSM session history (automatically logged by AWS)"
echo "- Cleaned up any downloaded files"
echo "- Cleared environment variables"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (EC2 instance, IAM roles, S3 bucket, and users) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}"
echo ""
echo -e "${BLUE}Note: This scenario does not create persistent artifacts that require cleanup.${NC}"
echo -e "${BLUE}The ssm:StartSession attack is read-only and only extracts existing credentials.${NC}"
echo -e "${BLUE}Session activity is logged in CloudTrail with the following events:${NC}"
echo -e "${BLUE}  - StartSession (when session starts)${NC}"
echo -e "${BLUE}  - TerminateSession (when session ends)${NC}"
echo -e "${BLUE}  - ResumeSession (if session is resumed)${NC}\n"
