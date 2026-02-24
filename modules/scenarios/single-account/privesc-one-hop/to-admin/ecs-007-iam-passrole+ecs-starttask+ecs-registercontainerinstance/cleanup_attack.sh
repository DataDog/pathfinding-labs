#!/bin/bash

# Cleanup script for iam:PassRole + ecs:StartTask + ecs:RegisterContainerInstance privilege escalation demo
# This script detaches the AdministratorAccess policy from the starting user, stops any running tasks,
# deregisters the container instance from the cluster, and resets the ECS agent to the holding cluster

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-ecs-007-to-admin-starting-user"
EXISTING_TASK_FAMILY="pl-prod-ecs-007-existing-task"
ADMIN_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"
HOLDING_CLUSTER="pl-prod-ecs-007-holding"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: PassRole + ECS StartTask Override${NC}"
echo -e "${GREEN}+ RegisterContainerInstance (ECS-007)${NC}"
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

# Get cluster name and EC2 instance ID from grouped terraform output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_ecs_007_iam_passrole_ecs_starttask_ecs_registercontainerinstance.value // empty')

if [ -n "$MODULE_OUTPUT" ]; then
    ECS_CLUSTER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.cluster_name // empty')
    EC2_INSTANCE_ID=$(echo "$MODULE_OUTPUT" | jq -r '.container_instance_id // empty')
fi

if [ -z "$ECS_CLUSTER_NAME" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve ECS cluster name from Terraform${NC}"
    ECS_CLUSTER_NAME="pl-prod-ecs-007-cluster"
fi

if [ -z "$EC2_INSTANCE_ID" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve EC2 instance ID from Terraform${NC}"
fi

# Set admin credentials
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_REGION="$CURRENT_REGION"
unset AWS_SESSION_TOKEN

echo "Region from Terraform: $CURRENT_REGION"
echo "ECS Cluster: $ECS_CLUSTER_NAME"
echo "EC2 Instance ID: ${EC2_INSTANCE_ID:-N/A}"
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

# Step 3: Stop any running tasks
echo -e "${YELLOW}Step 3: Stopping any running ECS tasks${NC}"
echo "Checking for running tasks in cluster: $ECS_CLUSTER_NAME"

# List all tasks in the cluster
RUNNING_TASKS=$(aws ecs list-tasks \
    --region $CURRENT_REGION \
    --cluster $ECS_CLUSTER_NAME \
    --desired-status RUNNING \
    --query 'taskArns[*]' \
    --output text 2>/dev/null || echo "")

if [ -n "$RUNNING_TASKS" ]; then
    echo "Found running tasks. Checking if they are from the demo..."
    for TASK_ARN in $RUNNING_TASKS; do
        # Get task details to check if it used our task family
        TASK_FAMILY=$(aws ecs describe-tasks \
            --region $CURRENT_REGION \
            --cluster $ECS_CLUSTER_NAME \
            --tasks $TASK_ARN \
            --query 'tasks[0].group' \
            --output text 2>/dev/null || echo "")

        if [[ "$TASK_FAMILY" == *"$EXISTING_TASK_FAMILY"* ]]; then
            echo "Stopping task: $TASK_ARN"
            aws ecs stop-task \
                --region $CURRENT_REGION \
                --cluster $ECS_CLUSTER_NAME \
                --task $TASK_ARN \
                --output text > /dev/null 2>&1 || true
            echo -e "${GREEN}✓ Stopped task: $TASK_ARN${NC}"
        fi
    done
else
    echo -e "${YELLOW}No running tasks found (may already be stopped)${NC}"
fi
echo ""

# Step 4: Deregister container instance from the cluster
echo -e "${YELLOW}Step 4: Deregistering container instance from ECS cluster${NC}"
echo "Checking for container instances in cluster: $ECS_CLUSTER_NAME"

CONTAINER_INSTANCE_ARNS=$(aws ecs list-container-instances \
    --region $CURRENT_REGION \
    --cluster $ECS_CLUSTER_NAME \
    --query 'containerInstanceArns' \
    --output json 2>/dev/null || echo "[]")

INSTANCE_COUNT=$(echo "$CONTAINER_INSTANCE_ARNS" | jq 'length')

if [ "$INSTANCE_COUNT" != "0" ]; then
    echo "Found $INSTANCE_COUNT container instance(s) to deregister"
    for CI_ARN in $(echo "$CONTAINER_INSTANCE_ARNS" | jq -r '.[]'); do
        echo "Deregistering container instance: $CI_ARN"
        aws ecs deregister-container-instance \
            --region $CURRENT_REGION \
            --cluster $ECS_CLUSTER_NAME \
            --container-instance "$CI_ARN" \
            --force 2>/dev/null || true
        echo -e "${GREEN}✓ Deregistered container instance: $CI_ARN${NC}"
    done
else
    echo -e "${YELLOW}No container instances found in cluster (may already be deregistered)${NC}"
fi
echo ""

# Step 5: Reset the ECS agent on the EC2 instance to the holding cluster
echo -e "${YELLOW}Step 5: Resetting ECS agent to holding cluster via SSM${NC}"

if [ -n "$EC2_INSTANCE_ID" ]; then
    echo "EC2 Instance ID: $EC2_INSTANCE_ID"
    echo "Resetting ECS_CLUSTER from $ECS_CLUSTER_NAME to $HOLDING_CLUSTER"

    COMMAND_RESULT=$(aws ssm send-command \
        --instance-ids "$EC2_INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=[\"sed -i 's/$ECS_CLUSTER_NAME/$HOLDING_CLUSTER/' /etc/ecs/ecs.config && systemctl restart ecs\"]" \
        --region $CURRENT_REGION \
        --output json 2>/dev/null || echo "")

    if [ -n "$COMMAND_RESULT" ]; then
        COMMAND_ID=$(echo "$COMMAND_RESULT" | jq -r '.Command.CommandId // empty')
        if [ -n "$COMMAND_ID" ]; then
            echo "SSM Command ID: $COMMAND_ID"
            echo "Waiting for SSM command to complete..."

            MAX_SSM_ATTEMPTS=12
            SSM_ATTEMPT=0

            while [ $SSM_ATTEMPT -lt $MAX_SSM_ATTEMPTS ]; do
                SSM_ATTEMPT=$((SSM_ATTEMPT + 1))
                sleep 5

                COMMAND_STATUS=$(aws ssm get-command-invocation \
                    --command-id "$COMMAND_ID" \
                    --instance-id "$EC2_INSTANCE_ID" \
                    --region $CURRENT_REGION \
                    --query 'Status' \
                    --output text 2>/dev/null || echo "InProgress")

                if [ "$COMMAND_STATUS" == "Success" ]; then
                    echo -e "${GREEN}✓ ECS agent reset to holding cluster${NC}"
                    break
                elif [ "$COMMAND_STATUS" == "Failed" ] || [ "$COMMAND_STATUS" == "Cancelled" ] || [ "$COMMAND_STATUS" == "TimedOut" ]; then
                    echo -e "${YELLOW}Warning: SSM command $COMMAND_STATUS - agent may not have been reset${NC}"
                    break
                fi
            done

            if [ $SSM_ATTEMPT -ge $MAX_SSM_ATTEMPTS ]; then
                echo -e "${YELLOW}Warning: Timeout waiting for SSM command - agent may not have been reset${NC}"
            fi
        else
            echo -e "${YELLOW}Warning: Could not get SSM command ID${NC}"
        fi
    else
        echo -e "${YELLOW}Warning: Could not send SSM command to reset ECS agent${NC}"
        echo "You may need to manually reset /etc/ecs/ecs.config on the EC2 instance"
    fi
else
    echo -e "${YELLOW}Warning: EC2 instance ID not available - skipping ECS agent reset${NC}"
    echo "You may need to manually reset the ECS agent configuration"
fi
echo ""

# Step 6: Verify cleanup
echo -e "${YELLOW}Step 6: Verifying cleanup${NC}"

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

# Verify no container instances in cluster
REMAINING_INSTANCES=$(aws ecs list-container-instances \
    --region $CURRENT_REGION \
    --cluster $ECS_CLUSTER_NAME \
    --query 'containerInstanceArns' \
    --output json 2>/dev/null || echo "[]")

REMAINING_COUNT=$(echo "$REMAINING_INSTANCES" | jq 'length')
if [ "$REMAINING_COUNT" == "0" ]; then
    echo -e "${GREEN}✓ No container instances registered in cluster (back to original empty state)${NC}"
else
    echo -e "${YELLOW}Warning: $REMAINING_COUNT container instance(s) still registered in cluster${NC}"
fi

# Verify no running tasks from the demo
REMAINING_TASKS=$(aws ecs list-tasks \
    --region $CURRENT_REGION \
    --cluster $ECS_CLUSTER_NAME \
    --family $EXISTING_TASK_FAMILY \
    --query 'taskArns[*]' \
    --output text 2>/dev/null || echo "")

if [ -z "$REMAINING_TASKS" ]; then
    echo -e "${GREEN}✓ No running tasks found for task family${NC}"
else
    echo -e "${YELLOW}Warning: Some tasks may still be running${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess policy from: $STARTING_USER"
echo "- Stopped any running ECS tasks from the demo"
echo "- Deregistered container instance(s) from cluster: $ECS_CLUSTER_NAME"
echo "- Reset ECS agent on EC2 instance to point back to: $HOLDING_CLUSTER"
echo ""
echo -e "${YELLOW}Note: No task definitions were created during the demo (existing task${NC}"
echo -e "${YELLOW}definition was used with --overrides), so no deregistration is needed.${NC}"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, ECS cluster, and EC2 instance) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
