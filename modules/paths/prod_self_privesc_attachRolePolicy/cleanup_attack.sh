#!/bin/bash

# Cleanup script for prod_self_privesc_attachRolePolicy module
# This script removes any changes made by the demo_attack.sh script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Pathfinder-labs Self-Privilege Escalation Cleanup (AttachRolePolicy) ===${NC}"
echo "This script cleans up any changes made by the demo_attack.sh script"
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    exit 1
fi

# Configuration
PROFILE="pl-admin-cleanup-prod"
ROLE_NAME="pl-prod-self-privesc-attachRolePolicy-role-1"

echo -e "${YELLOW}Step 1: Checking if role exists${NC}"
if aws iam get-role --role-name "$ROLE_NAME" --profile $PROFILE &> /dev/null; then
    echo -e "${GREEN}✓ Role $ROLE_NAME exists${NC}"
else
    echo -e "${RED}✗ Role $ROLE_NAME not found. Nothing to clean up.${NC}"
    exit 0
fi

echo "Using admin cleanup profile: $PROFILE"

echo ""
echo -e "${YELLOW}Step 2: Verifying admin access${NC}"
# Verify we have admin access
aws sts get-caller-identity --profile $PROFILE
echo -e "${GREEN}✓ Admin access verified${NC}"

echo ""
echo -e "${YELLOW}Step 3: Checking for AdministratorAccess policy${NC}"
# Check if the AdministratorAccess policy is attached
if aws iam list-attached-role-policies --role-name "$ROLE_NAME" --profile $PROFILE --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`]' --output text | grep -q "AdministratorAccess"; then
    echo -e "${YELLOW}Found AdministratorAccess policy, detaching it...${NC}"
    
    # Detach the AdministratorAccess policy
    aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess" --profile $PROFILE
    echo -e "${GREEN}✓ Successfully detached AdministratorAccess policy${NC}"
else
    echo -e "${GREEN}✓ No AdministratorAccess policy found (already clean)${NC}"
fi

echo ""
echo -e "${YELLOW}Step 4: Checking for other potentially dangerous policies${NC}"
# List all attached managed policies on the role
ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --profile $PROFILE --query 'AttachedPolicies[].PolicyArn' --output text)

if [ -n "$ATTACHED_POLICIES" ] && [ "$ATTACHED_POLICIES" != "None" ]; then
    echo "Found attached managed policies:"
    aws iam list-attached-role-policies --role-name "$ROLE_NAME" --profile $PROFILE --output table
    
    # Check each policy for dangerous permissions
    for policy_arn in $ATTACHED_POLICIES; do
        policy_name=$(echo "$policy_arn" | cut -d'/' -f2)
        echo "Checking policy: $policy_name ($policy_arn)"
        
        # Skip the original policy that should remain
        if [ "$policy_arn" = "arn:aws:iam::$(aws sts get-caller-identity --profile $PROFILE --query Account --output text):policy/pl-prod-self-privesc-attachRolePolicy-policy" ]; then
            echo -e "${GREEN}✓ Skipping original policy: $policy_name${NC}"
            continue
        fi
        
        # Check if it's a dangerous AWS managed policy
        if [[ "$policy_arn" == "arn:aws:iam::aws:policy/"* ]]; then
            if [[ "$policy_name" == "AdministratorAccess" ]] || [[ "$policy_name" == "PowerUserAccess" ]] || [[ "$policy_name" == "IAMFullAccess" ]]; then
                echo -e "${YELLOW}Found potentially dangerous AWS managed policy: $policy_name${NC}"
                
                # Ask for confirmation before detaching
                read -p "Do you want to detach this policy? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$policy_arn" --profile $PROFILE
                    echo -e "${GREEN}✓ Detached policy: $policy_name${NC}"
                else
                    echo -e "${YELLOW}⚠ Skipped detachment of policy: $policy_name${NC}"
                fi
            else
                echo -e "${GREEN}✓ Policy $policy_name appears safe${NC}"
            fi
        else
            echo -e "${GREEN}✓ Policy $policy_name appears to be a custom policy${NC}"
        fi
    done
else
    echo -e "${GREEN}✓ No attached managed policies found${NC}"
fi

echo ""
echo -e "${YELLOW}Step 5: Verifying cleanup${NC}"
# Verify the role is back to its original state
echo "Current attached managed policies:"
aws iam list-attached-role-policies --role-name "$ROLE_NAME" --profile $PROFILE

echo ""
echo "Current inline policies:"
aws iam list-role-policies --role-name "$ROLE_NAME" --profile $PROFILE

echo ""
echo -e "${GREEN}✓ Cleanup complete!${NC}"
echo "The role should now be back to its original state with only the intended policy attached."

echo ""
echo -e "${YELLOW}Step 6: Final verification${NC}"
# Show the current attached policy document
echo "Current attached policy document:"
POLICY_ARN=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --profile $PROFILE --query 'AttachedPolicies[0].PolicyArn' --output text)
aws iam get-policy --policy-arn "$POLICY_ARN" --profile $PROFILE --query 'Policy.DefaultVersionId' --output text | xargs -I {} aws iam get-policy-version --policy-arn "$POLICY_ARN" --version-id {} --profile $PROFILE --query 'PolicyVersion.Document' --output json | jq '.'

echo ""
echo -e "${GREEN}=== Cleanup Complete ===${NC}"
echo "The role has been restored to its original state."
echo "Only the intended 'pl-prod-self-privesc-attachRolePolicy-policy' should remain attached."
