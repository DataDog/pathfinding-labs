#!/bin/bash

# Cleanup script for iam:PassRole + ecs:CreateCluster + ecs:RegisterTaskDefinition + ecs:RunTask privilege escalation demo
# This script removes the ECS cluster, task definitions, and IAM policy attachment created during the demo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-preccrt-to-admin-starting-user"
CLUSTER_NAME="pl-prod-preccrt-attack-cluster"
TASK_FAMILY="pl-preccrt-admin-escalation"
ADMIN_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: ECS PassRole + CreateCluster + RegisterTaskDefinition + RunTask${NC}"
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

# Step 2: Detach AdministratorAccess policy from starting user
echo -e "${YELLOW}Step 2: Detaching AdministratorAccess policy from starting user${NC}"
echo "User: $STARTING_USER"
echo "Policy: $ADMIN_POLICY_ARN"

# Check if the policy is attached
ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
    --user-name "$STARTING_USER" \
    --query 'AttachedPolicies[?PolicyArn==`'$ADMIN_POLICY_ARN'`].PolicyArn' \
    --output text)

if [ -n "$ATTACHED_POLICIES" ]; then
    aws iam detach-user-policy \
        --user-name "$STARTING_USER" \
        --policy-arn "$ADMIN_POLICY_ARN"
    echo -e "${GREEN}✓ Detached AdministratorAccess policy from $STARTING_USER${NC}"
else
    echo -e "${YELLOW}AdministratorAccess policy not attached to $STARTING_USER (may already be detached)${NC}"
fi
echo ""

# Step 3: Stop any running tasks in the cluster
echo -e "${YELLOW}Step 3: Stopping any running ECS tasks${NC}"
echo "Cluster: $CLUSTER_NAME"

# Check if cluster exists
if aws ecs describe-clusters \
    --region $CURRENT_REGION \
    --clusters "$CLUSTER_NAME" \
    --query 'clusters[0].status' \
    --output text 2>/dev/null | grep -q "ACTIVE"; then

    echo "Found cluster: $CLUSTER_NAME"

    # List running tasks
    RUNNING_TASKS=$(aws ecs list-tasks \
        --region $CURRENT_REGION \
        --cluster "$CLUSTER_NAME" \
        --desired-status RUNNING \
        --query 'taskArns[]' \
        --output text)

    if [ -n "$RUNNING_TASKS" ]; then
        echo "Found running tasks, stopping them..."
        for TASK_ARN in $RUNNING_TASKS; do
            echo "Stopping task: $TASK_ARN"
            aws ecs stop-task \
                --region $CURRENT_REGION \
                --cluster "$CLUSTER_NAME" \
                --task "$TASK_ARN" \
                --reason "Cleanup script" \
                --output json > /dev/null
        done
        echo -e "${GREEN}✓ Stopped running tasks${NC}"

        # Wait for tasks to stop
        echo "Waiting for tasks to stop..."
        sleep 10
    else
        echo "No running tasks found"
    fi
else
    echo -e "${YELLOW}Cluster $CLUSTER_NAME not found (may already be deleted)${NC}"
fi
echo ""

# Step 4: Delete the ECS cluster
echo -e "${YELLOW}Step 4: Deleting ECS cluster${NC}"
echo "Cluster: $CLUSTER_NAME"

# Check again if cluster exists before deletion
if aws ecs describe-clusters \
    --region $CURRENT_REGION \
    --clusters "$CLUSTER_NAME" \
    --query 'clusters[0].status' \
    --output text 2>/dev/null | grep -q "ACTIVE"; then

    aws ecs delete-cluster \
        --region $CURRENT_REGION \
        --cluster "$CLUSTER_NAME" \
        --output json > /dev/null

    echo -e "${GREEN}✓ Deleted ECS cluster: $CLUSTER_NAME${NC}"
else
    echo -e "${YELLOW}Cluster $CLUSTER_NAME not found (may already be deleted)${NC}"
fi
echo ""

# Step 5: Deregister task definitions
echo -e "${YELLOW}Step 5: Deregistering ECS task definitions${NC}"
echo "Task Family: $TASK_FAMILY"

# List all task definition revisions
TASK_DEFINITIONS=$(aws ecs list-task-definitions \
    --region $CURRENT_REGION \
    --family-prefix "$TASK_FAMILY" \
    --query 'taskDefinitionArns[]' \
    --output text)

if [ -n "$TASK_DEFINITIONS" ]; then
    echo "Found task definitions to deregister:"
    DEREGISTERED_COUNT=0
    for TASK_DEF_ARN in $TASK_DEFINITIONS; do
        echo "  - $TASK_DEF_ARN"
        aws ecs deregister-task-definition \
            --region $CURRENT_REGION \
            --task-definition "$TASK_DEF_ARN" \
            --output json > /dev/null
        DEREGISTERED_COUNT=$((DEREGISTERED_COUNT + 1))
    done
    echo -e "${GREEN}✓ Deregistered $DEREGISTERED_COUNT task definition(s)${NC}"
else
    echo -e "${YELLOW}No task definitions found for family: $TASK_FAMILY (may already be deregistered)${NC}"
fi
echo ""

# Step 6: Clean up CloudWatch log groups
echo -e "${YELLOW}Step 6: Cleaning up CloudWatch log groups${NC}"
LOG_GROUP_NAME="/ecs/$TASK_FAMILY"

# Check if log group exists
if aws logs describe-log-groups \
    --region $CURRENT_REGION \
    --log-group-name-prefix "$LOG_GROUP_NAME" \
    --query 'logGroups[?logGroupName==`'$LOG_GROUP_NAME'`].logGroupName' \
    --output text 2>/dev/null | grep -q "$LOG_GROUP_NAME"; then

    aws logs delete-log-group \
        --region $CURRENT_REGION \
        --log-group-name "$LOG_GROUP_NAME"

    echo -e "${GREEN}✓ Deleted CloudWatch log group: $LOG_GROUP_NAME${NC}"
else
    echo -e "${YELLOW}Log group $LOG_GROUP_NAME not found (may not have been created or already deleted)${NC}"
fi
echo ""

# Step 7: Verify cleanup
echo -e "${YELLOW}Step 7: Verifying cleanup${NC}"

# Check that the policy is detached
ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
    --user-name "$STARTING_USER" \
    --query 'AttachedPolicies[?PolicyArn==`'$ADMIN_POLICY_ARN'`].PolicyArn' \
    --output text)

if [ -z "$ATTACHED_POLICIES" ]; then
    echo -e "${GREEN}✓ AdministratorAccess policy successfully detached from user${NC}"
else
    echo -e "${YELLOW}⚠ Warning: AdministratorAccess policy still attached to $STARTING_USER${NC}"
fi

# Check that the cluster no longer exists
CLUSTER_STATUS=$(aws ecs describe-clusters \
    --region $CURRENT_REGION \
    --clusters "$CLUSTER_NAME" \
    --query 'clusters[0].status' \
    --output text 2>/dev/null || echo "INACTIVE")

if [ "$CLUSTER_STATUS" == "INACTIVE" ] || [ "$CLUSTER_STATUS" == "None" ]; then
    echo -e "${GREEN}✓ ECS cluster successfully deleted${NC}"
else
    echo -e "${YELLOW}⚠ Warning: ECS cluster may still exist with status: $CLUSTER_STATUS${NC}"
fi

# Check task definitions
REMAINING_TASKS=$(aws ecs list-task-definitions \
    --region $CURRENT_REGION \
    --family-prefix "$TASK_FAMILY" \
    --status ACTIVE \
    --query 'taskDefinitionArns[]' \
    --output text)

if [ -z "$REMAINING_TASKS" ]; then
    echo -e "${GREEN}✓ All task definitions successfully deregistered${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Some task definitions may still be active${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess policy from: $STARTING_USER"
echo "- Stopped any running ECS tasks"
echo "- Deleted ECS cluster: $CLUSTER_NAME"
echo "- Deregistered task definitions: $TASK_FAMILY"
echo "- Cleaned up CloudWatch log groups"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
