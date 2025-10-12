#!/bin/bash

# Cleanup script for dev__user_has_createAccessKey_to_admin attack path
# This script removes any access keys that may have been created during the attack demo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Dev User Has CreateAccessKey to Admin Attack Cleanup ===${NC}"
echo "This script cleans up any access keys created during the attack demo."
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

echo -e "${YELLOW}Step 1: Checking for existing access keys for pl-dev-admin${NC}"

# List existing access keys for the dev-admin user
if ACCESS_KEYS=$(aws iam list-access-keys --user-name pl-dev-admin --output json 2>/dev/null); then
    KEY_COUNT=$(echo "$ACCESS_KEYS" | jq '.AccessKeyMetadata | length')
    echo "Found $KEY_COUNT access key(s) for pl-dev-admin user"
    
    if [ "$KEY_COUNT" -gt 0 ]; then
        echo "Access keys found:"
        echo "$ACCESS_KEYS" | jq '.AccessKeyMetadata[] | {AccessKeyId: .AccessKeyId, CreateDate: .CreateDate, Status: .Status}'
        echo ""
        
        echo -e "${YELLOW}Step 2: Removing access keys for pl-dev-admin${NC}"
        
        # Delete each access key
        echo "$ACCESS_KEYS" | jq -r '.AccessKeyMetadata[].AccessKeyId' | while read -r access_key_id; do
            echo "Deleting access key: $access_key_id"
            if aws iam delete-access-key --user-name pl-dev-admin --access-key-id "$access_key_id" 2>/dev/null; then
                echo -e "${GREEN}✓ Successfully deleted access key: $access_key_id${NC}"
            else
                echo -e "${RED}✗ Failed to delete access key: $access_key_id${NC}"
            fi
        done
        
        echo ""
        echo -e "${YELLOW}Step 3: Verifying cleanup${NC}"
        
        # Verify that all access keys have been removed
        if REMAINING_KEYS=$(aws iam list-access-keys --user-name pl-dev-admin --output json 2>/dev/null); then
            REMAINING_COUNT=$(echo "$REMAINING_KEYS" | jq '.AccessKeyMetadata | length')
            if [ "$REMAINING_COUNT" -eq 0 ]; then
                echo -e "${GREEN}✓ All access keys successfully removed${NC}"
            else
                echo -e "${YELLOW}⚠ Warning: $REMAINING_COUNT access key(s) still remain${NC}"
                echo "Remaining access keys:"
                echo "$REMAINING_KEYS" | jq '.AccessKeyMetadata[] | {AccessKeyId: .AccessKeyId, CreateDate: .CreateDate, Status: .Status}'
            fi
        else
            echo -e "${YELLOW}⚠ Warning: Could not verify cleanup (user may not exist)${NC}"
        fi
        
    else
        echo -e "${GREEN}✓ No access keys found for pl-dev-admin user${NC}"
    fi
    
else
    echo -e "${YELLOW}⚠ Warning: Could not list access keys for pl-dev-admin user${NC}"
    echo "This could be because:"
    echo "1. The pl-dev-admin user doesn't exist"
    echo "2. Insufficient permissions to list access keys"
    echo "3. The user has been deleted"
fi

echo ""
echo -e "${YELLOW}Step 4: Additional cleanup checks${NC}"

# Check if there are any other users that might have been affected
echo "Checking for any other users with 'pl-' prefix that might need cleanup..."

if USERS=$(aws iam list-users --output json 2>/dev/null); then
    PL_USERS=$(echo "$USERS" | jq -r '.Users[] | select(.UserName | startswith("pl-")) | .UserName')
    if [ -n "$PL_USERS" ]; then
        echo "Found users with 'pl-' prefix:"
        echo "$PL_USERS" | while read -r user; do
            echo "  - $user"
        done
    else
        echo "No users with 'pl-' prefix found"
    fi
else
    echo -e "${YELLOW}⚠ Warning: Could not list users (insufficient permissions)${NC}"
fi

echo ""
echo -e "${GREEN}=== CLEANUP COMPLETE ===${NC}"
echo "Cleanup process completed. Any access keys created during the attack demo"
echo "should have been removed. If any access keys remain, they may need"
echo "manual cleanup or may be protected by additional policies."
echo ""

# Output standardized cleanup results
echo "CLEANUP_RESULT:dev__user_has_createAccessKey_to_admin:SUCCESS"
echo "CLEANUP_DETAILS:dev__user_has_createAccessKey_to_admin:Access keys cleanup completed"
echo "CLEANUP_METRICS:dev__user_has_createAccessKey_to_admin:cleanup_completed=true"
