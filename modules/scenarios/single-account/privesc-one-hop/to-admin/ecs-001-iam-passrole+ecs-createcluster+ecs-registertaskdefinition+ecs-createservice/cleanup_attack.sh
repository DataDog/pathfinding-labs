#!/bin/bash

# Cleanup script for iam-passrole+ecs-createcluster+ecs-registertaskdefinition+ecs-createservice privilege escalation demo
# This script removes the ECS cluster, service, task definitions, and IAM policy attachment


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-ecs-001-to-admin-starting-user"
CLUSTER_NAME="pl-prod-ecs-001-attack-cluster"
TASK_FAMILY="pl-ecs-001-admin-escalation"
SERVICE_NAME="pl-prod-ecs-001-attack-service"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: ECS Service PassRole Escalation${NC}"
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

if aws iam list-attached-user-policies --user-name $STARTING_USER --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`]' --output text | grep -q AdministratorAccess; then
    aws iam detach-user-policy \
        --user-name $STARTING_USER \
        --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
    echo -e "${GREEN}✓ Detached AdministratorAccess policy${NC}"
else
    echo -e "${YELLOW}AdministratorAccess policy not attached (may already be removed)${NC}"
fi
echo ""

# Step 3: Scale service to 0 desired count
echo -e "${YELLOW}Step 3: Scaling ECS service to 0 desired count${NC}"

if aws ecs describe-services \
    --region $CURRENT_REGION \
    --cluster $CLUSTER_NAME \
    --services $SERVICE_NAME \
    --query 'services[0].serviceName' \
    --output text 2>/dev/null | grep -q "$SERVICE_NAME"; then

    aws ecs update-service \
        --region $CURRENT_REGION \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --desired-count 0 \
        --output json > /dev/null

    echo -e "${GREEN}✓ Scaled service to 0${NC}"

    # Wait for tasks to stop
    echo "Waiting for tasks to stop..."
    sleep 15
else
    echo -e "${YELLOW}Service $SERVICE_NAME not found (may already be deleted)${NC}"
fi
echo ""

# Step 4: Delete the ECS service
echo -e "${YELLOW}Step 4: Deleting ECS service${NC}"

if aws ecs describe-services \
    --region $CURRENT_REGION \
    --cluster $CLUSTER_NAME \
    --services $SERVICE_NAME \
    --query 'services[0].serviceName' \
    --output text 2>/dev/null | grep -q "$SERVICE_NAME"; then

    aws ecs delete-service \
        --region $CURRENT_REGION \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --force \
        --output json > /dev/null

    echo -e "${GREEN}✓ Deleted service: $SERVICE_NAME${NC}"

    # Wait for service deletion
    echo "Waiting for service deletion to complete..."
    sleep 10
else
    echo -e "${YELLOW}Service $SERVICE_NAME not found (may already be deleted)${NC}"
fi
echo ""

# Step 5: Stop any remaining running tasks
echo -e "${YELLOW}Step 5: Stopping any remaining tasks${NC}"

RUNNING_TASKS=$(aws ecs list-tasks \
    --region $CURRENT_REGION \
    --cluster $CLUSTER_NAME \
    --query 'taskArns[*]' \
    --output text 2>/dev/null || echo "")

if [ -n "$RUNNING_TASKS" ]; then
    for TASK_ARN in $RUNNING_TASKS; do
        echo "Stopping task: $TASK_ARN"
        aws ecs stop-task \
            --region $CURRENT_REGION \
            --cluster $CLUSTER_NAME \
            --task $TASK_ARN \
            --output json > /dev/null
    done
    echo -e "${GREEN}✓ Stopped all running tasks${NC}"
else
    echo -e "${YELLOW}No running tasks found${NC}"
fi
echo ""

# Step 6: Delete the ECS cluster
echo -e "${YELLOW}Step 6: Deleting ECS cluster${NC}"

if aws ecs describe-clusters \
    --region $CURRENT_REGION \
    --clusters $CLUSTER_NAME \
    --query 'clusters[0].clusterName' \
    --output text 2>/dev/null | grep -q "$CLUSTER_NAME"; then

    aws ecs delete-cluster \
        --region $CURRENT_REGION \
        --cluster $CLUSTER_NAME \
        --output json > /dev/null

    echo -e "${GREEN}✓ Deleted cluster: $CLUSTER_NAME${NC}"
else
    echo -e "${YELLOW}Cluster $CLUSTER_NAME not found (may already be deleted)${NC}"
fi
echo ""

# Step 7: Deregister task definitions
echo -e "${YELLOW}Step 7: Deregistering task definitions${NC}"

# List all task definition revisions
TASK_DEFS=$(aws ecs list-task-definitions \
    --region $CURRENT_REGION \
    --family-prefix $TASK_FAMILY \
    --query 'taskDefinitionArns[*]' \
    --output text 2>/dev/null || echo "")

if [ -n "$TASK_DEFS" ]; then
    for TASK_DEF_ARN in $TASK_DEFS; do
        echo "Deregistering: $TASK_DEF_ARN"
        aws ecs deregister-task-definition \
            --region $CURRENT_REGION \
            --task-definition $TASK_DEF_ARN \
            --output json > /dev/null
    done
    echo -e "${GREEN}✓ Deregistered all task definitions${NC}"
else
    echo -e "${YELLOW}No task definitions found for family: $TASK_FAMILY${NC}"
fi
echo ""

# Step 8: Delete CloudWatch log group (if exists)
echo -e "${YELLOW}Step 8: Deleting CloudWatch log group${NC}"
LOG_GROUP_NAME="/ecs/pl-ecs-001-escalation"

if aws logs describe-log-groups \
    --region $CURRENT_REGION \
    --log-group-name-prefix $LOG_GROUP_NAME \
    --query 'logGroups[0].logGroupName' \
    --output text 2>/dev/null | grep -q "$LOG_GROUP_NAME"; then

    aws logs delete-log-group \
        --region $CURRENT_REGION \
        --log-group-name $LOG_GROUP_NAME

    echo -e "${GREEN}✓ Deleted log group: $LOG_GROUP_NAME${NC}"
else
    echo -e "${YELLOW}Log group not found (may not have been created)${NC}"
fi
echo ""

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess from starting user"
echo "- Deleted ECS service: $SERVICE_NAME"
echo "- Deleted ECS cluster: $CLUSTER_NAME"
echo "- Deregistered task definitions for: $TASK_FAMILY"
echo "- Deleted CloudWatch log group"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
