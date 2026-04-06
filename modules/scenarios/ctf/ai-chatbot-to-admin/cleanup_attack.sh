#!/bin/bash

# Cleanup script for CTF-001: AI Chatbot Prompt Injection to Admin
#
# The ctf-001 attack only reads environment variables from the Lambda execution
# environment via prompt injection. No AWS resources are modified. Cleanup
# removes any local credential files the participant may have created.

export AWS_PAGER=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source demo permissions library (restores any temporary restriction policies)
source "$SCRIPT_DIR/../../../../scripts/lib/demo_permissions.sh"
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: CTF-001 AI Chatbot to Admin${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${YELLOW}Step 1: Checking for local credential files${NC}"
LOCAL_FILES=(
    "/tmp/ctf_creds.env"
    "/tmp/ctf001_creds"
    "$HOME/.aws/credentials.ctf001.bak"
)

CLEANED_COUNT=0
for FILE in "${LOCAL_FILES[@]}"; do
    if [ -f "$FILE" ]; then
        rm -f "$FILE"
        echo "Removed: $FILE"
        CLEANED_COUNT=$((CLEANED_COUNT + 1))
    fi
done

if [ $CLEANED_COUNT -gt 0 ]; then
    echo -e "${GREEN}Cleaned up $CLEANED_COUNT local file(s)${NC}"
else
    echo "No local credential files found (this is expected)"
fi
echo ""

echo -e "${YELLOW}Step 2: Verifying chatbot infrastructure is intact${NC}"

cd "../../../../" || exit 1

CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)

if [ -n "$ADMIN_ACCESS_KEY" ] && [ "$ADMIN_ACCESS_KEY" != "null" ]; then
    export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
    export AWS_REGION="$CURRENT_REGION"
    unset AWS_SESSION_TOKEN

    if aws lambda get-function \
        --region "$CURRENT_REGION" \
        --function-name pl-prod-ctf-001-acmebot &>/dev/null; then
        echo -e "${GREEN}Chatbot Lambda is intact (as expected - attack is read-only)${NC}"
    else
        echo -e "${YELLOW}Warning: Chatbot Lambda not found. Was it deleted?${NC}"
    fi
else
    echo -e "${YELLOW}Admin credentials not available - skipping infrastructure check${NC}"
fi

cd - > /dev/null

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Summary:${NC}"
echo "- CTF-001 attack is read-only: only environment variables were read"
echo "- No AWS resources were modified during the exploit"
echo "- Infrastructure remains deployed and ready for another attempt"
echo ""
echo -e "${YELLOW}To remove all infrastructure:${NC}"
echo "  Set enable_ctf_ai_chatbot_to_admin = false in terraform.tfvars and run terraform apply"
echo ""

rm -f "$(dirname "$0")/.demo_active"
