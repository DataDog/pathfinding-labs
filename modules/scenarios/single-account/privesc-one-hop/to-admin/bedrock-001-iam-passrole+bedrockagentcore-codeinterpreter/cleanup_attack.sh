#!/bin/bash

# Cleanup script for Bedrock Code Interpreter privilege escalation demo
# This script removes code interpreters created during the demo


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Source demo permissions library for safety restore
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Safety: remove any orphaned restriction policies
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

# Configuration
INTERPRETER_NAME="privesc_demo_interpreter"
PYTHON_SCRIPT="/tmp/extract_bedrock_creds.py"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Bedrock Code Interpreter Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials and region from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get admin cleanup user credentials from root terraform output
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

# Set admin credentials
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_REGION="$CURRENT_REGION"
unset AWS_SESSION_TOKEN

echo "Region from Terraform: $CURRENT_REGION"
echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 2: Find and delete code interpreters
echo -e "${YELLOW}Step 2: Finding and deleting demo code interpreters${NC}"
echo "Searching for code interpreters with name: $INTERPRETER_NAME"
echo "Region: $CURRENT_REGION"
echo ""

# First, list ALL code interpreters to see what's there
echo "Listing all code interpreters..."
ALL_INTERPRETERS=$(aws bedrock-agentcore-control list-code-interpreters \
    --region $CURRENT_REGION \
    --output json 2>&1)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error listing code interpreters:${NC}"
    echo "$ALL_INTERPRETERS"
    echo ""
    echo -e "${YELLOW}Trying alternate approach - looking for interpreter by ID from demo...${NC}"
else
    echo "Raw output:"
    echo "$ALL_INTERPRETERS" | jq '.' 2>/dev/null || echo "$ALL_INTERPRETERS"
    echo ""
fi

# List all code interpreters and filter by name
INTERPRETER_IDS=$(aws bedrock-agentcore-control list-code-interpreters \
    --region $CURRENT_REGION \
    --query "codeInterpreterSummaries[?name=='${INTERPRETER_NAME}'].codeInterpreterId" \
    --output text 2>/dev/null || echo "")

if [ -z "$INTERPRETER_IDS" ]; then
    echo -e "${YELLOW}No code interpreters found with name: $INTERPRETER_NAME${NC}"
    echo "They may have already been deleted or have a different name."
    echo ""
else
    echo "Found code interpreters to delete:"
    echo "$INTERPRETER_IDS"
    echo ""

    # Delete each interpreter
    for INTERPRETER_ID in $INTERPRETER_IDS; do
        echo "Processing code interpreter: $INTERPRETER_ID"
        echo ""

        # Step 2a: List and stop any active sessions first
        echo "Checking for active sessions..."

        # First, list ALL sessions to see what we have
        ALL_SESSIONS=$(aws bedrock-agentcore list-code-interpreter-sessions \
            --region "$CURRENT_REGION" \
            --code-interpreter-identifier "$INTERPRETER_ID" \
            --output json 2>&1)

        echo "All sessions (raw):"
        echo "$ALL_SESSIONS" | jq '.' 2>/dev/null || echo "$ALL_SESSIONS"
        echo ""

        # Now filter for ACTIVE or READY sessions (both need to be stopped)
        SESSIONS=$(echo "$ALL_SESSIONS" | jq -r '.items[]? | select(.status=="ACTIVE" or .status=="READY") | .sessionId' 2>/dev/null)

        if [ -n "$SESSIONS" ]; then
            echo "Found active sessions to stop:"
            echo "$SESSIONS"
            echo ""

            for SESSION_ID in $SESSIONS; do
                echo "  Stopping session: $SESSION_ID"
                STOP_OUTPUT=$(aws bedrock-agentcore stop-code-interpreter-session \
                    --region "$CURRENT_REGION" \
                    --code-interpreter-identifier "$INTERPRETER_ID" \
                    --session-id "$SESSION_ID" 2>&1)

                if [ $? -eq 0 ]; then
                    echo -e "    ${GREEN}✓ Stopped${NC}"
                else
                    echo -e "    ${YELLOW}⚠ Warning: $STOP_OUTPUT${NC}"
                fi
            done
            echo -e "${GREEN}✓ Processed all active sessions${NC}"
            echo ""

            # Wait for sessions to terminate
            echo "Waiting 5 seconds for sessions to terminate..."
            sleep 5
        else
            echo "No active sessions found (or all already stopped)"
            echo ""
        fi

        # Step 2b: Now delete the code interpreter
        echo "Deleting code interpreter: $INTERPRETER_ID"
        DELETE_OUTPUT=$(aws bedrock-agentcore-control delete-code-interpreter \
            --region "$CURRENT_REGION" \
            --code-interpreter-id "$INTERPRETER_ID" 2>&1)
        DELETE_EXIT_CODE=$?

        if [ $DELETE_EXIT_CODE -eq 0 ]; then
            echo -e "${GREEN}✓ Deleted code interpreter: $INTERPRETER_ID${NC}"
        else
            echo -e "${RED}Error deleting interpreter (exit code: $DELETE_EXIT_CODE):${NC}"
            echo "$DELETE_OUTPUT"
        fi
        echo ""
    done
    echo ""
fi

# Step 3: Clean up local temporary files
echo -e "${YELLOW}Step 3: Cleaning up local temporary files${NC}"
LOCAL_FILES=("$PYTHON_SCRIPT")

FILES_REMOVED=0
for FILE in "${LOCAL_FILES[@]}"; do
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

# Step 4: Verify cleanup
echo -e "${YELLOW}Step 4: Verifying cleanup${NC}"

# Check that code interpreters are deleted
REMAINING_INTERPRETERS=$(aws bedrock-agentcore-control list-code-interpreters \
    --region $CURRENT_REGION \
    --query "codeInterpreters[?name=='${INTERPRETER_NAME}'].codeInterpreterId" \
    --output text 2>/dev/null || echo "")

if [ -n "$REMAINING_INTERPRETERS" ]; then
    echo -e "${YELLOW}⚠ Warning: Some code interpreters may still exist${NC}"
    echo "Remaining: $REMAINING_INTERPRETERS"
else
    echo -e "${GREEN}✓ All demo code interpreters have been deleted${NC}"
fi

# Check that local files are cleaned up
FILES_REMAINING=false
for FILE in "${LOCAL_FILES[@]}"; do
    if [ -f "$FILE" ]; then
        echo -e "${YELLOW}⚠ Warning: Local file still exists: $FILE${NC}"
        FILES_REMAINING=true
    fi
done

if [ "$FILES_REMAINING" = false ]; then
    echo -e "${GREEN}✓ All local temporary files cleaned up${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Deleted code interpreters with name: $INTERPRETER_NAME"
echo "- Cleaned up local temporary files"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
