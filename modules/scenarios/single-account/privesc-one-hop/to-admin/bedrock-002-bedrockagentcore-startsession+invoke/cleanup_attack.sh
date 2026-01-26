#!/bin/bash

# Cleanup script for bedrockagentcore-startsession+invoke privilege escalation demo (bedrock-002)
# This script stops active code interpreter sessions and removes temporary files
# Note: The code interpreter itself is managed by Terraform and is NOT deleted here

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PYTHON_SCRIPT="/tmp/bedrock_extract_credentials.py"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Bedrock Code Interpreter Demo Cleanup${NC}"
echo -e "${GREEN}Scenario: bedrockagentcore-startsession+invoke (bedrock-002)${NC}"
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

# Step 2: Find the code interpreter
echo -e "${YELLOW}Step 2: Finding existing code interpreter${NC}"
echo "Listing code interpreters in region: $CURRENT_REGION"
echo ""

# List all code interpreters
INTERPRETERS=$(aws bedrock-agentcore-control list-code-interpreters \
    --region $CURRENT_REGION \
    --output json 2>&1)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error listing code interpreters:${NC}"
    echo "$INTERPRETERS"
    echo ""
    echo -e "${YELLOW}Skipping session cleanup${NC}"
    INTERPRETER_ID=""
else
    # Parse the interpreter list
    INTERPRETER_COUNT=$(echo "$INTERPRETERS" | jq -r '.codeInterpreters | length' 2>/dev/null || echo "0")
    echo "Found $INTERPRETER_COUNT code interpreter(s)"

    if [ "$INTERPRETER_COUNT" -eq 0 ]; then
        echo -e "${YELLOW}No code interpreters found${NC}"
        echo "The code interpreter may not exist or has already been deleted"
        INTERPRETER_ID=""
    else
        # Get the first interpreter (should be ours)
        INTERPRETER_ID=$(echo "$INTERPRETERS" | jq -r '.codeInterpreters[0].codeInterpreterIdentifier' 2>/dev/null)
        echo "Code interpreter ID: $INTERPRETER_ID"
        echo -e "${GREEN}✓ Found code interpreter${NC}"
    fi
fi
echo ""

# Step 3: Stop active sessions if interpreter exists
if [ -n "$INTERPRETER_ID" ]; then
    echo -e "${YELLOW}Step 3: Stopping active code interpreter sessions${NC}"
    echo "Checking for active sessions on: $INTERPRETER_ID"
    echo ""

    # List ALL sessions to see what we have
    ALL_SESSIONS=$(aws bedrock-agentcore list-code-interpreter-sessions \
        --region "$CURRENT_REGION" \
        --code-interpreter-identifier "$INTERPRETER_ID" \
        --output json 2>&1)

    SESSION_LIST_EXIT_CODE=$?

    if [ $SESSION_LIST_EXIT_CODE -ne 0 ]; then
        echo -e "${YELLOW}Warning: Could not list sessions${NC}"
        echo "Error: $ALL_SESSIONS"
        echo ""
    else
        echo "Session list retrieved successfully"

        # Filter for ACTIVE or READY sessions (both need to be stopped)
        ACTIVE_SESSIONS=$(echo "$ALL_SESSIONS" | jq -r '.items[]? | select(.status=="ACTIVE" or .status=="READY") | .sessionId' 2>/dev/null)

        if [ -n "$ACTIVE_SESSIONS" ]; then
            echo "Found active sessions to stop:"
            echo "$ACTIVE_SESSIONS"
            echo ""

            # Stop each session
            for SESSION_ID in $ACTIVE_SESSIONS; do
                echo "Stopping session: $SESSION_ID"
                STOP_OUTPUT=$(aws bedrock-agentcore stop-code-interpreter-session \
                    --region "$CURRENT_REGION" \
                    --code-interpreter-identifier "$INTERPRETER_ID" \
                    --session-id "$SESSION_ID" 2>&1)

                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✓ Stopped session: $SESSION_ID${NC}"
                else
                    echo -e "${YELLOW}⚠ Warning: Could not stop session: $SESSION_ID${NC}"
                    echo "Error: $STOP_OUTPUT"
                fi
            done
            echo ""
            echo -e "${GREEN}✓ Processed all active sessions${NC}"

            # Wait for sessions to terminate
            echo "Waiting 5 seconds for sessions to terminate..."
            sleep 5
            echo -e "${GREEN}✓ Sessions should be stopped${NC}"
        else
            echo "No active sessions found (or all already stopped)"
            echo -e "${GREEN}✓ No sessions to clean up${NC}"
        fi
    fi
else
    echo -e "${YELLOW}Step 3: Skipping session cleanup (no interpreter found)${NC}"
fi
echo ""

# Step 4: Clean up local temporary files
echo -e "${YELLOW}Step 4: Cleaning up local temporary files${NC}"
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

# Step 5: Verify cleanup
echo -e "${YELLOW}Step 5: Verifying cleanup${NC}"

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

# Check sessions if interpreter exists
if [ -n "$INTERPRETER_ID" ]; then
    REMAINING_SESSIONS=$(aws bedrock-agentcore list-code-interpreter-sessions \
        --region "$CURRENT_REGION" \
        --code-interpreter-identifier "$INTERPRETER_ID" \
        --output json 2>/dev/null | jq -r '.items[]? | select(.status=="ACTIVE" or .status=="READY") | .sessionId' 2>/dev/null)

    if [ -n "$REMAINING_SESSIONS" ]; then
        echo -e "${YELLOW}⚠ Warning: Some active sessions may still exist${NC}"
        echo "Remaining sessions: $REMAINING_SESSIONS"
    else
        echo -e "${GREEN}✓ No active sessions remaining${NC}"
    fi
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Stopped all active code interpreter sessions"
echo "- Cleaned up local temporary files"
echo ""
echo -e "${BLUE}Note: The code interpreter itself is managed by Terraform${NC}"
echo -e "${BLUE}It will remain deployed until you run: terraform destroy${NC}"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, and code interpreter) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
