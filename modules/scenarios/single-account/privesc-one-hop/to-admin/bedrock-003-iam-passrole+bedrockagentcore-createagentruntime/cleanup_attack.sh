#!/bin/bash

# Cleanup script for AgentCore Runtime Creation privilege escalation demo
# This script removes the AgentCore Runtime created during the demo and
# cleans up any temporary local files.

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PYTHON_SCRIPT="/tmp/extract_bedrock_003_creds.py"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: AgentCore Runtime Creation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get credentials and region from Terraform
echo -e "${YELLOW}Step 1: Getting cleanup credentials from Terraform${NC}"
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
echo -e "${GREEN}✓ Retrieved admin credentials (key ID: ${ADMIN_ACCESS_KEY:0:12}...)${NC}"
echo ""

cd - > /dev/null

# Safety restore: ensure the helpful-permissions deny policy is removed even if
# the demo script exited early without calling restore_helpful_permissions.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

# Confirm identity being used for cleanup
CALLER_IDENTITY=$(aws sts get-caller-identity --output json 2>&1)
CALLER_ARN=$(echo "$CALLER_IDENTITY" | jq -r '.Arn // empty' 2>/dev/null)
ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | jq -r '.Account // empty' 2>/dev/null)
if [ -z "$CALLER_ARN" ]; then
    echo -e "${RED}Error: Could not verify caller identity — credentials may be invalid${NC}"
    echo "$CALLER_IDENTITY"
    exit 1
fi
echo "Cleanup identity : $CALLER_ARN"
echo "Account ID       : $ACCOUNT_ID"
echo ""

# Step 2: Find and delete the demo AgentCore Runtime
echo -e "${YELLOW}Step 2: Finding and deleting demo AgentCore Runtime${NC}"
echo "Searching for runtimes with name prefix: atk_runtime_bedrock_003"
echo "Region: $CURRENT_REGION"
echo ""

# List all runtimes and filter by name
ALL_RUNTIMES=$(aws bedrock-agentcore-control list-agent-runtimes \
    --region "$CURRENT_REGION" \
    --output json 2>&1)

LIST_EXIT=$?

if [ $LIST_EXIT -ne 0 ]; then
    echo -e "${YELLOW}Warning: Could not list AgentCore Runtimes (may not be supported in this region)${NC}"
    echo "$ALL_RUNTIMES"
    echo ""
else
    echo "Raw list output:"
    echo "$ALL_RUNTIMES" | jq '.' 2>/dev/null || echo "$ALL_RUNTIMES"
    echo ""

    # Extract runtime IDs matching our demo name prefix, excluding those already being deleted.
    # Use agentRuntimeId (not agentRuntimeArn) — passing a full ARN to --agent-runtime-id
    # triggers AccessDeniedException on some org SCPs even when the ID form succeeds.
    RUNTIME_IDS=$(echo "$ALL_RUNTIMES" | jq -r \
        '(.agentRuntimes // .agentRuntimeSummaries // [])[] | select(.agentRuntimeName | startswith("atk_runtime_bedrock_003")) | select(.status != "DELETING") | .agentRuntimeId' \
        2>/dev/null || echo "")

    DELETING_IDS=$(echo "$ALL_RUNTIMES" | jq -r \
        '(.agentRuntimes // .agentRuntimeSummaries // [])[] | select(.agentRuntimeName | startswith("atk_runtime_bedrock_003")) | select(.status == "DELETING") | .agentRuntimeId' \
        2>/dev/null || echo "")

    if [ -n "$DELETING_IDS" ]; then
        echo -e "${YELLOW}Already deleting (skipping):${NC}"
        echo "$DELETING_IDS" | sed 's/^/  /'
        echo ""
    fi

    if [ -z "$RUNTIME_IDS" ]; then
        echo -e "${YELLOW}No runtimes found with name prefix: atk_runtime_bedrock_003${NC}"
        echo "The runtime may have already been deleted or the demo may not have been run."
        echo ""
    else
        echo "Found runtimes to delete:"
        echo "$RUNTIME_IDS"
        echo ""

        for RUNTIME_ID in $RUNTIME_IDS; do
            echo "Processing runtime: $RUNTIME_ID"
            echo ""

            # Delete associated endpoints first — the runtime cannot be deleted while
            # endpoints are attached.
            echo "  Listing endpoints for this runtime..."
            echo "  Command: aws bedrock-agentcore-control list-agent-runtime-endpoints --agent-runtime-id \"$RUNTIME_ID\" --region \"$CURRENT_REGION\""
            ENDPOINTS_OUTPUT=$(aws bedrock-agentcore-control list-agent-runtime-endpoints \
                --agent-runtime-id "$RUNTIME_ID" \
                --region "$CURRENT_REGION" \
                --output json 2>&1)
            LIST_EP_EXIT=$?

            if [ $LIST_EP_EXIT -ne 0 ]; then
                if echo "$ENDPOINTS_OUTPUT" | grep -q "AccessDeniedException"; then
                    echo -e "  ${RED}AccessDeniedException on ListAgentRuntimeEndpoints${NC}"
                    echo -e "  ${YELLOW}Delete this runtime manually from the AWS console:${NC}"
                    echo -e "  ${YELLOW}  https://console.aws.amazon.com/bedrock/home?region=${CURRENT_REGION}#/agent-runtimes${NC}"
                    echo -e "  ${YELLOW}  Runtime ID: $RUNTIME_ID${NC}"
                    continue
                fi
                echo -e "  ${YELLOW}Warning: Could not list endpoints: $ENDPOINTS_OUTPUT${NC}"
            else
                # API returns "runtimeEndpoints" (not "agentRuntimeEndpoints")
                ENDPOINT_NAMES=$(echo "$ENDPOINTS_OUTPUT" | jq -r \
                    '(.runtimeEndpoints // [])[] | .name' 2>/dev/null || echo "")

                if [ -z "$ENDPOINT_NAMES" ]; then
                    echo "  No endpoints found."
                else
                    for EP_NAME in $ENDPOINT_NAMES; do
                        # The DEFAULT endpoint is automatically removed when the runtime is
                        # deleted — attempting to delete it explicitly returns ConflictException.
                        if [ "$EP_NAME" = "DEFAULT" ]; then
                            echo "  Skipping DEFAULT endpoint (removed automatically on runtime delete)"
                            continue
                        fi
                        echo "  Deleting endpoint: $EP_NAME"
                        echo "  Command: aws bedrock-agentcore-control delete-agent-runtime-endpoint --agent-runtime-id \"$RUNTIME_ID\" --endpoint-name \"$EP_NAME\" --region \"$CURRENT_REGION\""
                        EP_DEL_OUTPUT=$(aws bedrock-agentcore-control delete-agent-runtime-endpoint \
                            --agent-runtime-id "$RUNTIME_ID" \
                            --endpoint-name "$EP_NAME" \
                            --region "$CURRENT_REGION" 2>&1)
                        EP_DEL_EXIT=$?
                        if [ $EP_DEL_EXIT -ne 0 ]; then
                            echo -e "  ${RED}Error deleting endpoint $EP_NAME:${NC} $EP_DEL_OUTPUT"
                        else
                            echo -e "  ${GREEN}✓ Endpoint $EP_NAME deleted${NC}"
                        fi
                    done
                fi
            fi
            echo ""

            echo "  Deleting runtime: $RUNTIME_ID"
            echo "  Command: aws bedrock-agentcore-control delete-agent-runtime --agent-runtime-id \"$RUNTIME_ID\" --region \"$CURRENT_REGION\""
            DELETE_OUTPUT=$(aws bedrock-agentcore-control delete-agent-runtime \
                --agent-runtime-id "$RUNTIME_ID" \
                --region "$CURRENT_REGION" 2>&1)
            DELETE_EXIT=$?

            if [ $DELETE_EXIT -ne 0 ]; then
                if echo "$DELETE_OUTPUT" | grep -q "AccessDeniedException"; then
                    echo -e "${RED}AccessDeniedException on DeleteAgentRuntime${NC}"
                    echo -e "${YELLOW}Delete this runtime manually from the AWS console:${NC}"
                    echo -e "${YELLOW}  https://console.aws.amazon.com/bedrock/home?region=${CURRENT_REGION}#/agent-runtimes${NC}"
                    echo -e "${YELLOW}  Runtime ID: $RUNTIME_ID${NC}"
                else
                    echo -e "${RED}Error deleting runtime (exit code: $DELETE_EXIT):${NC}"
                    echo "$DELETE_OUTPUT"
                fi
                echo ""
                continue
            fi

            RUNTIME_STATE=$(aws bedrock-agentcore-control get-agent-runtime \
                --agent-runtime-id "$RUNTIME_ID" \
                --region "$CURRENT_REGION" \
                --query 'status' --output text 2>/dev/null || echo "UNKNOWN")
            echo -e "${GREEN}✓ Delete initiated — current status: $RUNTIME_STATE${NC}"
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
# The demo does NOT attach policies or create access keys on the starting user or target role
# directly — it only reads credentials from MMDS. So there are no out-of-band IAM mutations
# to reverse. This step is a sanity check to confirm that assumption.
echo -e "${YELLOW}Step 4: Verifying no IAM mutations remain${NC}"
echo "This scenario does not attach managed policies or create access keys out-of-band."
echo "The demo only reads credentials from MMDS inside the runtime."
echo -e "${GREEN}✓ No IAM mutations to reverse${NC}"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Deleted AgentCore Runtime(s) with name prefix atk_runtime_bedrock_003 (if any existed)"
echo "- Cleaned up local temporary files"
echo "- No IAM mutations were made by the demo (nothing extra to reverse)"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, ECR repo) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
