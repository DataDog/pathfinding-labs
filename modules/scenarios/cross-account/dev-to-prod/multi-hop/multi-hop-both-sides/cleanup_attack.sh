#!/bin/bash

# Cleanup script for x-account-from-dev-to-prod-multi-hop-privesc-both-sides attack path
# This script removes any login profiles that may have been created during the attack demo


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Multi-Hop Cross-Account Privilege Escalation Attack Cleanup ===${NC}"
echo "This script cleans up any login profiles created during the attack demo."
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

echo -e "${YELLOW}Step 1: Checking for login profiles that may need cleanup${NC}"

# Check if Josh user has a login profile
echo "Checking for pl-Josh login profile in dev account..."
if aws iam get-login-profile --user-name "pl-Josh" --output json 2>/dev/null; then
    echo "Found login profile for pl-Josh user"
    echo ""
    
    echo -e "${YELLOW}Step 2: Removing Josh's login profile${NC}"
    echo "Deleting login profile for pl-Josh user..."
    
    if aws iam delete-login-profile --user-name "pl-Josh" 2>/dev/null; then
        echo -e "${GREEN}✓ Successfully deleted login profile for pl-Josh${NC}"
    else
        echo -e "${RED}✗ Failed to delete login profile for pl-Josh${NC}"
        echo "This could be because:"
        echo "1. Insufficient permissions to delete login profiles"
        echo "2. The login profile is protected by additional policies"
        echo "3. The user doesn't exist"
    fi
else
    echo -e "${GREEN}✓ No login profile found for pl-Josh user${NC}"
fi

echo ""
echo -e "${YELLOW}Step 3: Checking Jeremy's login profile status${NC}"
echo "Checking for pl-Jeremy login profile in prod account..."

# Check if Jeremy user has a login profile
if JEREMY_PROFILE=$(aws iam get-login-profile --user-name "pl-Jeremy" --output json 2>/dev/null); then
    echo "Found login profile for pl-Jeremy user"
    echo "Profile details:"
    echo "$JEREMY_PROFILE" | jq '.'
    echo ""
    
    echo -e "${YELLOW}Step 4: Resetting Jeremy's login profile to original password${NC}"
    echo "Resetting pl-Jeremy's login profile to original password..."
    
    if aws iam update-login-profile --user-name "pl-Jeremy" --password "InitialPassword123!" --no-password-reset-required 2>/dev/null; then
        echo -e "${GREEN}✓ Successfully reset Jeremy's login profile to original password${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: Could not reset Jeremy's login profile${NC}"
        echo "This could be because:"
        echo "1. Insufficient permissions to update login profiles"
        echo "2. The login profile is protected by additional policies"
        echo "3. The user doesn't exist"
    fi
else
    echo -e "${YELLOW}⚠ Warning: Could not find login profile for pl-Jeremy user${NC}"
    echo "This could be because:"
    echo "1. The user doesn't exist"
    echo "2. The user doesn't have a login profile"
    echo "3. Insufficient permissions to check login profiles"
fi

echo ""
echo -e "${YELLOW}Step 5: Additional cleanup checks${NC}"

# Check for any other users that might have been affected
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

# Check for any roles that might have been affected
echo ""
echo "Checking for any roles with 'pl-' prefix that might need cleanup..."

if ROLES=$(aws iam list-roles --output json 2>/dev/null); then
    PL_ROLES=$(echo "$ROLES" | jq -r '.Roles[] | select(.RoleName | startswith("pl-")) | .RoleName')
    if [ -n "$PL_ROLES" ]; then
        echo "Found roles with 'pl-' prefix:"
        echo "$PL_ROLES" | while read -r role; do
            echo "  - $role"
        done
    else
        echo "No roles with 'pl-' prefix found"
    fi
else
    echo -e "${YELLOW}⚠ Warning: Could not list roles (insufficient permissions)${NC}"
fi

echo ""
echo -e "${GREEN}=== CLEANUP COMPLETE ===${NC}"
echo "Cleanup process completed. Any login profiles created during the attack demo"
echo "should have been removed or reset. Users and roles are preserved to avoid"
echo "breaking dependencies."
echo ""

# Output standardized cleanup results
echo "CLEANUP_RESULT:x-account-from-dev-to-prod-multi-hop-privesc-both-sides:SUCCESS"
echo "CLEANUP_DETAILS:x-account-from-dev-to-prod-multi-hop-privesc-both-sides:Login profiles cleanup completed"
echo "CLEANUP_METRICS:x-account-from-dev-to-prod-multi-hop-privesc-both-sides:cleanup_completed=true"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
