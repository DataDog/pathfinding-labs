#!/bin/bash

# Cleanup script for iam:PassRole + ecs:RegisterTaskDefinition + ecs:RunTask privilege escalation demo
# This script removes the ECS task definition and detaches the admin policy from the starting user

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-ecs-004-to-admin-starting-user"
TASK_DEFINITION_FAMILY="pl-ecs-004-admin-escalation"
ADMIN_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: PassRole + ECS RegisterTaskDefinition + RunTask${NC}"
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
ECS_CLUSTER_NAME=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_ecs_004_iam_passrole_ecs_registertaskdefinition_ecs_runtask.value.ecs_cluster_name // empty')
cd - > /dev/null

if [ -z "$ECS_CLUSTER_NAME" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve ECS cluster name from Terraform${NC}"
    ECS_CLUSTER_NAME="pl-prod-ecs-004-cluster"
fi

echo "ECS Cluster: $ECS_CLUSTER_NAME"
echo ""

# Step 2: Stop any running tasks
echo -e "${YELLOW}Step 2: Stopping any running ECS tasks${NC}"
echo "Checking for running tasks in family: $TASK_DEFINITION_FAMILY"

# List tasks in the cluster with our task definition family
RUNNING_TASKS=$(aws ecs list-tasks \
    --region $CURRENT_REGION \
    --cluster $ECS_CLUSTER_NAME \
    --family $TASK_DEFINITION_FAMILY \
    --query 'taskArns[*]' \
    --output text)

if [ -n "$RUNNING_TASKS" ]; then
    echo "Found running tasks. Stopping them..."
    for TASK_ARN in $RUNNING_TASKS; do
        echo "Stopping task: $TASK_ARN"
        aws ecs stop-task \
            --region $CURRENT_REGION \
            --cluster $ECS_CLUSTER_NAME \
            --task $TASK_ARN \
            --output text > /dev/null
        echo -e "${GREEN}✓ Stopped task: $TASK_ARN${NC}"
    done
else
    echo -e "${YELLOW}No running tasks found (may already be stopped)${NC}"
fi
echo ""

# Step 3: Deregister task definitions
echo -e "${YELLOW}Step 3: Deregistering ECS task definitions${NC}"
echo "Looking for task definitions in family: $TASK_DEFINITION_FAMILY"

# List all task definition revisions
TASK_DEFINITIONS=$(aws ecs list-task-definitions \
    --region $CURRENT_REGION \
    --family-prefix $TASK_DEFINITION_FAMILY \
    --query 'taskDefinitionArns[*]' \
    --output text)

if [ -n "$TASK_DEFINITIONS" ]; then
    echo "Found task definitions. Deregistering them..."
    for TASK_DEF_ARN in $TASK_DEFINITIONS; do
        echo "Deregistering: $TASK_DEF_ARN"
        aws ecs deregister-task-definition \
            --region $CURRENT_REGION \
            --task-definition $TASK_DEF_ARN \
            --output text > /dev/null
        echo -e "${GREEN}✓ Deregistered: $TASK_DEF_ARN${NC}"
    done
else
    echo -e "${YELLOW}No task definitions found (may already be deregistered)${NC}"
fi
echo ""

# Step 4: Detach AdministratorAccess policy from starting user
echo -e "${YELLOW}Step 4: Detaching AdministratorAccess policy from starting user${NC}"
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

# Step 5: Verify cleanup
echo -e "${YELLOW}Step 5: Verifying cleanup${NC}"

# Verify no running tasks
REMAINING_TASKS=$(aws ecs list-tasks \
    --region $CURRENT_REGION \
    --cluster $ECS_CLUSTER_NAME \
    --family $TASK_DEFINITION_FAMILY \
    --query 'taskArns[*]' \
    --output text)

if [ -z "$REMAINING_TASKS" ]; then
    echo -e "${GREEN}✓ No running tasks found${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Some tasks may still be running${NC}"
fi

# Verify task definitions are deregistered
# Note: Deregistered task definitions still appear in lists but with INACTIVE status
ACTIVE_TASK_DEFS=$(aws ecs list-task-definitions \
    --region $CURRENT_REGION \
    --family-prefix $TASK_DEFINITION_FAMILY \
    --status ACTIVE \
    --query 'taskDefinitionArns[*]' \
    --output text)

if [ -z "$ACTIVE_TASK_DEFS" ]; then
    echo -e "${GREEN}✓ All task definitions deregistered${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Some task definitions may still be active${NC}"
fi

# Verify policy is detached
ATTACHED_POLICIES_AFTER=$(aws iam list-attached-user-policies \
    --user-name $STARTING_USER \
    --query 'AttachedPolicies[*].PolicyArn' \
    --output text)

if echo "$ATTACHED_POLICIES_AFTER" | grep -q "$ADMIN_POLICY_ARN"; then
    echo -e "${YELLOW}⚠ Warning: AdministratorAccess policy still attached to user${NC}"
else
    echo -e "${GREEN}✓ AdministratorAccess policy successfully detached${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Stopped any running ECS tasks"
echo "- Deregistered task definitions in family: $TASK_DEFINITION_FAMILY"
echo "- Detached AdministratorAccess policy from: $STARTING_USER"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, and ECS cluster) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
