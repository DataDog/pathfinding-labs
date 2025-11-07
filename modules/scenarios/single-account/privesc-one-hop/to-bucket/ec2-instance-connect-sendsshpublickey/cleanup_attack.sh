#!/bin/bash

# Cleanup script for ec2-instance-connect:SendSSHPublicKey privilege escalation demo (to-bucket)
# This scenario creates temporary SSH keys and extracts instance credentials
# This script cleans up local files and environment variables

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SSH_KEY_FILE="/tmp/pathfinder_eic_key"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}EC2 Instance Connect to S3 Bucket Demo Cleanup${NC}"
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
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_bucket_ec2_instance_connect_sendsshpublickey.value // empty')
INSTANCE_ID=$(echo "$MODULE_OUTPUT" | jq -r '.ec2_instance_id // empty')
TARGET_BUCKET=$(echo "$MODULE_OUTPUT" | jq -r '.target_bucket_name // empty')

# Navigate back to scenario directory
cd - > /dev/null

# Step 2: Remove temporary SSH keys
echo -e "${YELLOW}Step 2: Removing temporary SSH keys${NC}"
if [ -f "${SSH_KEY_FILE}" ] || [ -f "${SSH_KEY_FILE}.pub" ]; then
    rm -f ${SSH_KEY_FILE} ${SSH_KEY_FILE}.pub
    echo -e "${GREEN}✓ Removed SSH key files:${NC}"
    echo "  - ${SSH_KEY_FILE}"
    echo "  - ${SSH_KEY_FILE}.pub"
else
    echo -e "${GREEN}✓ No SSH key files to clean up${NC}"
fi
echo ""

# Step 3: Check for SSH connection history (informational only)
echo -e "${YELLOW}Step 3: Information about SSH connection history${NC}"
echo "Note: EC2 Instance Connect actions are automatically logged"

if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "null" ]; then
    echo "Target instance: $INSTANCE_ID"
    echo -e "${BLUE}EC2 Instance Connect actions are recorded in:${NC}"
    echo "  - AWS CloudTrail (ec2-instance-connect:SendSSHPublicKey events)"
    echo "  - Instance syslog (SSH connection attempts)"
    echo "  - VPC Flow Logs (if enabled)"
    echo ""
    echo -e "${YELLOW}Connection history is maintained by AWS and does not require cleanup${NC}"
else
    echo -e "${YELLOW}Could not retrieve instance ID from Terraform output${NC}"
fi
echo ""

# Step 4: Clean up any downloaded files
echo -e "${YELLOW}Step 4: Cleaning up downloaded files${NC}"
if [ -f "sensitive-data.txt" ]; then
    rm -f sensitive-data.txt
    echo -e "${GREEN}✓ Removed downloaded sensitive-data.txt${NC}"
else
    echo -e "${GREEN}✓ No downloaded files to clean up${NC}"
fi
echo ""

# Step 5: Clean up environment variables
echo -e "${YELLOW}Step 5: Cleaning up environment variables${NC}"
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
echo "- Removed temporary SSH key files"
echo "- Verified connection history (automatically logged by AWS)"
echo "- Cleaned up any downloaded files"
echo "- Cleared environment variables"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (EC2 instance, IAM roles, S3 bucket, and users) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}"
echo ""
echo -e "${BLUE}Note: This scenario demonstrates credential theft, not persistent access changes.${NC}"
echo -e "${BLUE}The SSH public key pushed to the instance expires automatically after 60 seconds.${NC}"
echo -e "${BLUE}The extracted instance role credentials are temporary and will expire.${NC}"
echo -e "${BLUE}No persistent policy changes were made during the demo.${NC}"
echo -e "${BLUE}Connection activity is logged in CloudTrail with the following events:${NC}"
echo -e "${BLUE}  - ec2-instance-connect:SendSSHPublicKey (when key is pushed)${NC}"
echo -e "${BLUE}  - SSH connection logs (in instance syslog)${NC}"
echo -e "${BLUE}  - S3 API calls (GetObject, ListBucket) using extracted credentials${NC}\n"
