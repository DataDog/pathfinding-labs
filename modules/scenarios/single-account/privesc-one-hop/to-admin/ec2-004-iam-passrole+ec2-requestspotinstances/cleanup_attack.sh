#!/bin/bash

# Cleanup script for iam:PassRole + ec2:RequestSpotInstances privilege escalation demo
# This script cancels spot requests, terminates spot instances, and restores the original state

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-ec2-004-to-admin-starting-user"
ADMIN_ROLE="pl-prod-ec2-004-to-admin-target-role"
DEMO_INSTANCE_TAG="pl-ec2-004-to-admin-demo-spot-instance"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + EC2 RequestSpotInstances Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Go to project root

# Get admin cleanup user credentials from root terraform output
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup credentials in terraform output${NC}"
    echo "Make sure the admin cleanup user is deployed"
    exit 1
fi

# Set admin credentials
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
unset AWS_SESSION_TOKEN

echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

# Get region from Terraform
CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$CURRENT_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    CURRENT_REGION="us-east-1"
fi

echo "Region from Terraform: $CURRENT_REGION"

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"

cd - > /dev/null  # Return to scenario directory
echo ""

# Step 2: Find and cancel spot instance requests
echo -e "${YELLOW}Step 2: Finding and canceling spot instance requests${NC}"
echo "Searching for spot requests in region: $CURRENT_REGION"
echo ""

# Find spot requests associated with our demo instances
SPOT_REQUEST_IDS=$(aws ec2 describe-spot-instance-requests \
    --region $CURRENT_REGION \
    --filters "Name=tag:Name,Values=$DEMO_INSTANCE_TAG" "Name=state,Values=open,active" \
    --query 'SpotInstanceRequests[*].SpotInstanceRequestId' \
    --output text 2>/dev/null || echo "")

if [ -n "$SPOT_REQUEST_IDS" ]; then
    echo "Found active spot requests: $SPOT_REQUEST_IDS"

    for SPOT_REQUEST_ID in $SPOT_REQUEST_IDS; do
        echo "Canceling spot request: $SPOT_REQUEST_ID"
        aws ec2 cancel-spot-instance-requests \
            --region $CURRENT_REGION \
            --spot-instance-request-ids $SPOT_REQUEST_ID \
            --output text > /dev/null
        echo -e "${GREEN}✓ Canceled spot request: $SPOT_REQUEST_ID${NC}"
    done
else
    echo -e "${YELLOW}No active spot requests found (may already be canceled)${NC}"
fi
echo ""

# Step 3: Find and terminate spot instances
echo -e "${YELLOW}Step 3: Finding and terminating demo spot instances${NC}"
echo "Searching for instances with tag: Name=$DEMO_INSTANCE_TAG"
echo "Searching in region: $CURRENT_REGION"
echo ""

# Find instances by tag (first search all states to see if any exist)
ALL_INSTANCES=$(aws ec2 describe-instances \
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
            --region $CURRENT_REGION \
            --instance-ids $INSTANCE_ID \
            --output text > /dev/null
        echo -e "${GREEN}✓ Terminated instance: $INSTANCE_ID${NC}"
    done

    echo ""
    echo "Waiting for instances to terminate (this may take a minute)..."
    for INSTANCE_ID in $INSTANCE_IDS; do
        aws ec2 wait instance-terminated \
            --region $CURRENT_REGION \
            --instance-ids $INSTANCE_ID 2>/dev/null || true
    done
    echo -e "${GREEN}✓ All instances terminated${NC}"
fi
echo ""

# Step 4: Detach AdministratorAccess policy from starting user
echo -e "${YELLOW}Step 4: Detaching AdministratorAccess policy from starting user${NC}"
echo "Removing AdministratorAccess policy from: $STARTING_USER"

# Check if the policy is attached
ATTACHED_POLICIES=$(aws iam list-attached-user-policies --user-name $STARTING_USER --query 'AttachedPolicies[?PolicyName==`AdministratorAccess`].PolicyName' --output text 2>/dev/null || echo "")

if [ "$ATTACHED_POLICIES" == "AdministratorAccess" ]; then
    aws iam detach-user-policy \
        --user-name $STARTING_USER \
        --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
    echo -e "${GREEN}✓ Detached AdministratorAccess policy${NC}"
else
    echo -e "${YELLOW}AdministratorAccess policy not attached (may already be detached)${NC}"
fi
echo ""

# Step 5: Verify cleanup
echo -e "${YELLOW}Step 5: Verifying cleanup${NC}"

# Check if AdministratorAccess is still attached
ATTACHED_POLICIES=$(aws iam list-attached-user-policies --user-name $STARTING_USER --query 'AttachedPolicies[?PolicyName==`AdministratorAccess`].PolicyName' --output text 2>/dev/null || echo "")

if [ -z "$ATTACHED_POLICIES" ]; then
    echo -e "${GREEN}✓ AdministratorAccess policy successfully removed${NC}"
else
    echo -e "${RED}⚠ Warning: AdministratorAccess policy may still be attached${NC}"
fi

# Check that no demo instances are running
REMAINING_INSTANCES=$(aws ec2 describe-instances \
    --region $CURRENT_REGION \
    --filters "Name=tag:Name,Values=$DEMO_INSTANCE_TAG" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text)

if [ -z "$REMAINING_INSTANCES" ]; then
    echo -e "${GREEN}✓ No demo instances remaining${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Some instances may still exist: $REMAINING_INSTANCES${NC}"
fi

# Check for remaining spot requests
REMAINING_SPOT_REQUESTS=$(aws ec2 describe-spot-instance-requests \
    --region $CURRENT_REGION \
    --filters "Name=tag:Name,Values=$DEMO_INSTANCE_TAG" "Name=state,Values=open,active" \
    --query 'SpotInstanceRequests[*].SpotInstanceRequestId' \
    --output text 2>/dev/null || echo "")

if [ -z "$REMAINING_SPOT_REQUESTS" ]; then
    echo -e "${GREEN}✓ No active spot requests remaining${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Some spot requests may still be active: $REMAINING_SPOT_REQUESTS${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Canceled all demo spot instance requests"
echo "- Terminated all demo spot instances"
echo "- Detached AdministratorAccess policy from starting user"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
