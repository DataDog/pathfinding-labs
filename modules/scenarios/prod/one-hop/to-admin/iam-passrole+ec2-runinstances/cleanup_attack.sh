#!/bin/bash

# Cleanup script for iam:PassRole + ec2:RunInstances privilege escalation demo
# This script terminates the EC2 instance and restores the admin role's trust policy

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROFILE="pl-admin-cleanup-prod"
ADMIN_ROLE="pl-prod-one-hop-prec-admin-role"
DEMO_INSTANCE_TAG="pl-prec-demo-instance"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + EC2 RunInstances Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 0: Get region from Terraform
echo -e "${YELLOW}Retrieving region from Terraform configuration${NC}"
cd ../../../../../..  # Navigate to root of terraform project

CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$CURRENT_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    CURRENT_REGION="us-east-1"
fi

echo "Region from Terraform: $CURRENT_REGION"

# Navigate back to scenario directory
cd - > /dev/null
echo ""

# Try to use the admin cleanup profile, but fall back to default credentials if not available
echo "Checking AWS credentials..."
if aws sts get-caller-identity --profile $PROFILE &> /dev/null; then
    echo "Using AWS profile: $PROFILE"
    AWS_PROFILE_FLAG="--profile $PROFILE"
elif [ -n "$AWS_ACCESS_KEY_ID" ]; then
    echo "Using AWS credentials from environment variables"
    AWS_PROFILE_FLAG=""
else
    echo -e "${RED}Error: No AWS credentials available${NC}"
    echo "Either configure the '$PROFILE' profile or set AWS environment variables"
    exit 1
fi

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity $AWS_PROFILE_FLAG --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 1: Find and terminate EC2 instances
echo -e "${YELLOW}Step 1: Finding and terminating demo EC2 instances${NC}"
echo "Searching for instances with tag: Name=$DEMO_INSTANCE_TAG"
echo "Searching in region: $CURRENT_REGION"
echo ""

# Find instances by tag (first search all states to see if any exist)
ALL_INSTANCES=$(aws ec2 describe-instances \
    $AWS_PROFILE_FLAG \
    --region $CURRENT_REGION \
    --filters "Name=tag:Name,Values=$DEMO_INSTANCE_TAG" \
    --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' \
    --output text)

if [ -n "$ALL_INSTANCES" ]; then
    echo "Found instances (all states):"
    echo "$ALL_INSTANCES"
    echo ""
fi

# Now find instances that can be terminated
INSTANCE_IDS=$(aws ec2 describe-instances \
    $AWS_PROFILE_FLAG \
    --region $CURRENT_REGION \
    --filters "Name=tag:Name,Values=$DEMO_INSTANCE_TAG" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text)

if [ -z "$INSTANCE_IDS" ]; then
    echo -e "${YELLOW}No active demo instances found (may already be terminated)${NC}"
else
    echo "Found active instances to terminate: $INSTANCE_IDS"

    # Terminate each instance
    for INSTANCE_ID in $INSTANCE_IDS; do
        echo "Terminating instance: $INSTANCE_ID"
        aws ec2 terminate-instances \
            $AWS_PROFILE_FLAG \
            --region $CURRENT_REGION \
            --instance-ids $INSTANCE_ID \
            --output text > /dev/null
        echo -e "${GREEN}✓ Terminated instance: $INSTANCE_ID${NC}"
    done

    echo ""
    echo "Waiting for instances to terminate (this may take a minute)..."
    for INSTANCE_ID in $INSTANCE_IDS; do
        aws ec2 wait instance-terminated \
            $AWS_PROFILE_FLAG \
            --region $CURRENT_REGION \
            --instance-ids $INSTANCE_ID 2>/dev/null || true
    done
    echo -e "${GREEN}✓ All instances terminated${NC}"
fi
echo ""

# Step 2: Restore admin role trust policy
echo -e "${YELLOW}Step 2: Restoring admin role trust policy${NC}"
echo "Resetting trust policy to only allow EC2 service..."

# Create the original trust policy (only EC2 service)
TRUST_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}'

# Update the trust policy
aws iam update-assume-role-policy \
    $AWS_PROFILE_FLAG \
    --role-name $ADMIN_ROLE \
    --policy-document "$TRUST_POLICY"

echo -e "${GREEN}✓ Restored admin role trust policy${NC}"
echo ""

# Step 3: Verify cleanup
echo -e "${YELLOW}Step 3: Verifying cleanup${NC}"

# Check trust policy
CURRENT_TRUST=$(aws iam get-role $AWS_PROFILE_FLAG --role-name $ADMIN_ROLE --query 'Role.AssumeRolePolicyDocument' --output json)

if echo "$CURRENT_TRUST" | grep -q "ec2.amazonaws.com"; then
    echo -e "${GREEN}✓ Trust policy verified - contains ec2.amazonaws.com${NC}"
else
    echo -e "${RED}⚠ Warning: Trust policy may not be correct${NC}"
fi

# Check that no demo instances are running
REMAINING_INSTANCES=$(aws ec2 describe-instances \
    $AWS_PROFILE_FLAG \
    --region $CURRENT_REGION \
    --filters "Name=tag:Name,Values=$DEMO_INSTANCE_TAG" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text)

if [ -z "$REMAINING_INSTANCES" ]; then
    echo -e "${GREEN}✓ No demo instances remaining${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Some instances may still exist: $REMAINING_INSTANCES${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Terminated all demo EC2 instances"
echo "- Restored admin role trust policy"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
