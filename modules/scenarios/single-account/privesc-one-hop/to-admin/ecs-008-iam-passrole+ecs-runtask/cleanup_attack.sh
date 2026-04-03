#!/bin/bash

# Cleanup script for iam:PassRole + ecs:RunTask privilege escalation demo (ECS-008)
# This script detaches the AdministratorAccess policy from the starting user
# and stops any running tasks in the cluster

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
STARTING_USER="pl-prod-ecs-008-to-admin-starting-user"
EXISTING_TASK_FAMILY="pl-prod-ecs-008-existing-task"
ADMIN_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: PassRole + ECS RunTask (Command Override)${NC}"
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

# Get account ID and cluster name
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"

# Get cluster name from terraform outputs
cd ../../../../../..
CLUSTER_NAME=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_ecs_008_iam_passrole_ecs_runtask.value.cluster_name // empty')
cd - > /dev/null

if [ -z "$CLUSTER_NAME" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve ECS cluster name from Terraform${NC}"
    CLUSTER_NAME="pl-prod-ecs-008-cluster"
fi

echo "ECS Cluster: $CLUSTER_NAME"
echo ""

# Step 2: Stop any running tasks
echo -e "${YELLOW}Step 2: Stopping any running ECS tasks${NC}"
echo "Checking for running tasks in cluster: $CLUSTER_NAME"

# List all running tasks in the cluster
RUNNING_TASKS=$(aws ecs list-tasks \
    --region $CURRENT_REGION \
    --cluster $CLUSTER_NAME \
    --query 'taskArns[*]' \
    --output text 2>/dev/null || echo "")

if [ -n "$RUNNING_TASKS" ] && [ "$RUNNING_TASKS" != "None" ]; then
    echo "Found running tasks. Stopping them..."
    for TASK_ARN in $RUNNING_TASKS; do
        echo "Stopping task: $TASK_ARN"
        aws ecs stop-task \
            --region $CURRENT_REGION \
            --cluster $CLUSTER_NAME \
            --task $TASK_ARN \
            --output text > /dev/null 2>&1 || true
        echo -e "${GREEN}✓ Stopped task: $TASK_ARN${NC}"
    done
else
    echo -e "${YELLOW}No running tasks found (may already be stopped)${NC}"
fi
echo ""

# Step 3: Detach AdministratorAccess policy from starting user
echo -e "${YELLOW}Step 3: Detaching AdministratorAccess policy from starting user${NC}"
echo "User: $STARTING_USER"
echo "Policy: $ADMIN_POLICY_ARN"

# Check if the policy is attached
ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
    --user-name $STARTING_USER \
    --query 'AttachedPolicies[*].PolicyArn' \
    --output text)

if echo "$ATTACHED_POLICIES" | grep -q "$ADMIN_POLICY_ARN"; then
    echo "AdministratorAccess policy is attached. Detaching..."
    aws iam detach-user-policy \
        --user-name $STARTING_USER \
        --policy-arn $ADMIN_POLICY_ARN

    echo -e "${GREEN}✓ Detached AdministratorAccess policy from $STARTING_USER${NC}"
else
    echo -e "${YELLOW}AdministratorAccess policy not found attached to user (may already be detached)${NC}"
fi
echo ""

# Step 4: Verify cleanup
echo -e "${YELLOW}Step 4: Verifying cleanup${NC}"

# Verify no running tasks
REMAINING_TASKS=$(aws ecs list-tasks \
    --region $CURRENT_REGION \
    --cluster $CLUSTER_NAME \
    --query 'taskArns[*]' \
    --output text 2>/dev/null || echo "")

if [ -z "$REMAINING_TASKS" ] || [ "$REMAINING_TASKS" == "None" ]; then
    echo -e "${GREEN}✓ No running tasks found${NC}"
else
    echo -e "${YELLOW}Warning: Some tasks may still be running${NC}"
fi

# Verify policy is detached
ATTACHED_POLICIES_AFTER=$(aws iam list-attached-user-policies \
    --user-name $STARTING_USER \
    --query 'AttachedPolicies[*].PolicyArn' \
    --output text)

if echo "$ATTACHED_POLICIES_AFTER" | grep -q "$ADMIN_POLICY_ARN"; then
    echo -e "${YELLOW}Warning: AdministratorAccess policy still attached to user${NC}"
else
    echo -e "${GREEN}✓ AdministratorAccess policy successfully detached${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Stopped any running ECS tasks in cluster: $CLUSTER_NAME"
echo "- Detached AdministratorAccess policy from: $STARTING_USER"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, ECS cluster, and task definition) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
