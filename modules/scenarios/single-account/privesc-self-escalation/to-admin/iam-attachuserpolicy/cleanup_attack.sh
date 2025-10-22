#!/bin/bash

# Cleanup script for iam:AttachUserPolicy privilege escalation demo
# This script removes the managed policy attached during the demo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
MANAGED_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"
STARTING_USER="pl-pathfinder-starting-user-prod"
PRIVESC_USER="pl-aup-user"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM AttachUserPolicy Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Determine which user to clean up
echo -e "${YELLOW}Which user's attached managed policy should be removed?${NC}"
echo "1. pl-pathfinder-starting-user-prod (role-based attack path)"
echo "2. pl-aup-user (user-based attack path)"
echo "3. Both users"
read -p "Enter choice (1, 2, or 3): " choice

cleanup_user() {
    local USER=$1
    local PROFILE=$2

    echo -e "${YELLOW}Checking for attached managed policies on $USER${NC}"

    # List attached policies for the user
    POLICIES=$(aws iam list-attached-user-policies --user-name $USER --profile $PROFILE --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null || echo "")

    if [ -z "$POLICIES" ]; then
        echo -e "${GREEN}No attached managed policies found for $USER${NC}"
    else
        echo "Found attached policies: $POLICIES"

        # Check specifically for AdministratorAccess policy
        if echo "$POLICIES" | grep -q "$MANAGED_POLICY_ARN"; then
            echo -e "${YELLOW}Detaching managed policy: AdministratorAccess${NC}"
            aws iam detach-user-policy \
                --user-name $USER \
                --policy-arn $MANAGED_POLICY_ARN \
                --profile $PROFILE
            echo -e "${GREEN}✓ Detached managed policy: AdministratorAccess from $USER${NC}"
        else
            echo -e "${YELLOW}Policy AdministratorAccess not found on $USER${NC}"
        fi

        # Check for any other attached policies
        REMAINING=$(aws iam list-attached-user-policies --user-name $USER --profile $PROFILE --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null || echo "")
        if [ ! -z "$REMAINING" ]; then
            echo -e "${YELLOW}Warning: Other managed policies still attached to $USER:${NC}"
            echo "$REMAINING"
            echo "These were not created by this demo and were left in place."
        fi
    fi
}

# Determine which profile to use for cleanup
echo -e "\n${YELLOW}Which AWS profile has permissions to detach user policies?${NC}"
echo "1. pl-pathfinder-starting-user-prod (if it still has admin from the demo)"
echo "2. pl-admin-cleanup-prod (dedicated admin profile)"
echo "3. Other profile"
read -p "Enter choice (1, 2, or 3): " profile_choice

case $profile_choice in
    1)
        CLEANUP_PROFILE="pl-pathfinder-starting-user-prod"
        ;;
    2)
        CLEANUP_PROFILE="pl-admin-cleanup-prod"
        ;;
    3)
        read -p "Enter profile name: " CLEANUP_PROFILE
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo -e "\n${GREEN}Using profile: $CLEANUP_PROFILE${NC}\n"

# Perform cleanup based on user choice
case $choice in
    1)
        cleanup_user "$STARTING_USER" "$CLEANUP_PROFILE"
        ;;
    2)
        cleanup_user "$PRIVESC_USER" "$CLEANUP_PROFILE"
        ;;
    3)
        cleanup_user "$STARTING_USER" "$CLEANUP_PROFILE"
        echo ""
        cleanup_user "$PRIVESC_USER" "$CLEANUP_PROFILE"
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Managed policies have been detached${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
