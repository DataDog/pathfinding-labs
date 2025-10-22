#!/bin/bash

# Cleanup script for iam:AttachGroupPolicy privilege escalation demo
# This script detaches the AdministratorAccess policy from the group

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROFILE="pl-admin-cleanup-prod"
GROUP_NAME="pl-prod-one-hop-agp-group"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM AttachGroupPolicy Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: List attached managed policies
echo -e "${YELLOW}Step 1: Listing attached managed policies for $GROUP_NAME${NC}"
ATTACHED_POLICIES=$(aws iam list-attached-group-policies --group-name $GROUP_NAME --profile $PROFILE --query 'AttachedPolicies[*].PolicyArn' --output text)

if [ -z "$ATTACHED_POLICIES" ]; then
    echo -e "${GREEN}No managed policies attached to $GROUP_NAME${NC}"
else
    echo "Found attached policies: $ATTACHED_POLICIES"

    # Step 2: Detach the AdministratorAccess policy specifically
    echo -e "${YELLOW}Step 2: Detaching AdministratorAccess policy${NC}"
    ADMIN_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

    if echo "$ATTACHED_POLICIES" | grep -q "$ADMIN_POLICY_ARN"; then
        echo "Detaching policy: $ADMIN_POLICY_ARN"
        aws iam detach-group-policy \
            --group-name $GROUP_NAME \
            --policy-arn $ADMIN_POLICY_ARN \
            --profile $PROFILE
        echo -e "${GREEN}✓ Detached AdministratorAccess policy${NC}"
    else
        echo -e "${YELLOW}AdministratorAccess policy not attached to group${NC}"
    fi
fi


echo -e "${GREEN}✓ Cleanup complete${NC}\n"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AdministratorAccess policy has been detached from $GROUP_NAME${NC}"
echo -e "${YELLOW}The infrastructure (users and groups) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
