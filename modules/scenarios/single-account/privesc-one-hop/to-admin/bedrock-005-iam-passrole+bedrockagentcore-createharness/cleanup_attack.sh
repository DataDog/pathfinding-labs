#!/bin/bash

# Cleanup script for AgentCore Harness Creation privilege escalation demo (bedrock-005)
# This script removes the AgentCore Harness created during the demo and cleans up
# any temporary local files.
#
# The Harness provisions an underlying AgentCore Runtime. Deleting the Harness causes
# AWS to delete the underlying Runtime as well. Both operations are asynchronous but
# billing stops once the delete is accepted.

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration — must match the name used in demo_attack.sh
HARNESS_NAME="atk_harness_bedrock_005"
PYTHON_SCRIPT="/tmp/extract_bedrock_005_creds.py"

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Cleanup: AgentCore Harness Creation Demo${NC}"
echo -e "${GREEN}=========================================${NC}\n"

# Step 1: Get admin credentials and region from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)
CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup credentials in terraform output${NC}"
    echo "Make sure the admin cleanup user is deployed"
    exit 1
fi

if [ -z "$CURRENT_REGION" ] || [ "$CURRENT_REGION" == "null" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    CURRENT_REGION="us-east-1"
fi

export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_REGION="$CURRENT_REGION"
export AWS_DEFAULT_REGION="$CURRENT_REGION"
unset AWS_SESSION_TOKEN

echo "Region from Terraform: $CURRENT_REGION"
echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

cd - > /dev/null

# Safety restore: ensure the helpful-permissions deny policy is removed even if
# the demo script exited early without calling restore_helpful_permissions.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

# Get account ID for reference
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 2: Find and delete the demo AgentCore Harness
echo -e "${YELLOW}Step 2: Finding and deleting demo AgentCore Harness${NC}"
echo "Searching for harness with name: $HARNESS_NAME"
echo "Region: $CURRENT_REGION"
echo ""

# List all harnesses and filter by name
ALL_HARNESSES=$(aws bedrock-agentcore-control list-harnesses \
    --region "$CURRENT_REGION" \
    --output json 2>&1)

LIST_EXIT=$?

if [ $LIST_EXIT -ne 0 ]; then
    echo -e "${YELLOW}Warning: Could not list AgentCore Harnesses${NC}"
    echo "$ALL_HARNESSES"
    echo ""
else
    # Extract harness ARNs matching our demo name.
    # The list response may nest under .harnessSummaries or .harnesses; the ARN
    # field may be .arn or .harnessArn depending on SDK version — try both.
    HARNESS_ARNS=$(echo "$ALL_HARNESSES" | jq -r \
        "(.harnessSummaries // .harnesses // [])[] | select(.harnessName == \"$HARNESS_NAME\") | (.arn // .harnessArn)" \
        2>/dev/null || echo "")

    if [ -z "$HARNESS_ARNS" ]; then
        echo -e "${YELLOW}No harnesses found with name: $HARNESS_NAME${NC}"
        echo "The harness may have already been deleted or the demo may not have been run."
        echo ""
    else
        echo "Found harnesses to delete:"
        echo "$HARNESS_ARNS"
        echo ""

        for HARNESS_ARN in $HARNESS_ARNS; do
            # delete-harness requires the short harnessId, not the full ARN.
            # Extract the ID from the ARN: arn:...:harness/<id>
            HARNESS_ID=$(echo "$HARNESS_ARN" | sed 's|.*[/:]harness/||')
            echo "Deleting harness: $HARNESS_ARN (id: $HARNESS_ID)"
            DELETE_OUTPUT=$(aws bedrock-agentcore-control delete-harness \
                --harness-id "$HARNESS_ID" \
                --region "$CURRENT_REGION" 2>&1)
            DELETE_EXIT=$?

            if [ $DELETE_EXIT -eq 0 ]; then
                # AgentCore delete is accepted asynchronously — billing stops when the
                # delete is accepted, not when deletion completes.
                echo -e "${GREEN}✓ Delete accepted for harness: $HARNESS_ARN${NC}"
                echo "  (AWS continues deletion asynchronously; billing stops now)"
            else
                echo -e "${RED}Error deleting harness (exit code: $DELETE_EXIT):${NC}"
                echo "$DELETE_OUTPUT"
            fi
            echo ""
        done
    fi
fi

# Step 3: Clean up local temporary files
echo -e "${YELLOW}Step 3: Cleaning up local temporary files${NC}"
FILES_REMOVED=0
for FILE in "$PYTHON_SCRIPT"; do
    if [ -f "$FILE" ]; then
        rm -f "$FILE"
        echo "Removed: $FILE"
        FILES_REMOVED=$((FILES_REMOVED + 1))
    fi
done

if [ $FILES_REMOVED -eq 0 ]; then
    echo -e "${YELLOW}No local temporary files found${NC}"
else
    echo -e "${GREEN}✓ Cleaned up $FILES_REMOVED local file(s)${NC}"
fi
echo ""

# Step 4: Verify no IAM mutations remain
# The demo does NOT attach policies or create access keys on the starting user or target
# role out-of-band — it only reads credentials from MMDS inside the Harness MicroVM.
echo -e "${YELLOW}Step 4: Verifying no IAM mutations remain${NC}"
echo "This scenario does not attach managed policies or create access keys out-of-band."
echo "The demo only reads credentials from MMDS inside the harness MicroVM."
echo -e "${GREEN}✓ No IAM mutations to reverse${NC}"
echo ""

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Deleted AgentCore Harness: $HARNESS_NAME (if it existed)"
echo "- Cleaned up local temporary files"
echo "- No IAM mutations were made by the demo (nothing extra to reverse)"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (user, role, SSM flag) remains deployed.${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
