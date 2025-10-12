#!/bin/bash

# Cleanup script for prod_self_privesc_putRolePolicy module
# This script removes any changes made by the demo_attack.sh script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Pathfinder-labs Self-Privilege Escalation Cleanup ===${NC}"
echo "This script cleans up any changes made by the demo_attack.sh script"
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    exit 1
fi

# Check if the role exists
ROLE_NAME="pl-prod-self-privesc-putRolePolicy-role-1"
echo -e "${YELLOW}Step 1: Checking if role exists${NC}"
if aws iam get-role --role-name "$ROLE_NAME" --profile pl-admin-cleanup-prod &> /dev/null; then
    echo -e "${GREEN}✓ Role $ROLE_NAME exists${NC}"
else
    echo -e "${RED}✗ Role $ROLE_NAME not found. Nothing to clean up.${NC}"
    exit 0
fi

# Use admin cleanup profile directly
PROFILE="pl-admin-cleanup-prod"
echo "Using admin cleanup profile: $PROFILE"

echo ""
echo -e "${YELLOW}Step 2: Verifying admin access${NC}"
# Verify we have admin access
aws sts get-caller-identity --profile "$PROFILE"
echo -e "${GREEN}✓ Admin access verified${NC}"

echo ""
echo -e "${YELLOW}Step 3: Checking for self-admin-policy${NC}"
# Check if the self-admin-policy exists
if aws iam get-role-policy --role-name "$ROLE_NAME" --policy-name "self-admin-policy" --profile "$PROFILE" &> /dev/null; then
    echo -e "${YELLOW}Found self-admin-policy, removing it...${NC}"
    
    # Delete the self-admin-policy
    aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "self-admin-policy" --profile "$PROFILE"
    echo -e "${GREEN}✓ Successfully removed self-admin-policy${NC}"
else
    echo -e "${GREEN}✓ No self-admin-policy found (already clean)${NC}"
fi

echo ""
echo -e "${YELLOW}Step 4: Checking for other potentially dangerous policies${NC}"
# List all inline policies on the role
POLICIES=$(aws iam list-role-policies --role-name "$ROLE_NAME" --profile "$PROFILE" --query 'PolicyNames' --output text)

if [ -n "$POLICIES" ] && [ "$POLICIES" != "None" ]; then
    echo "Found inline policies: $POLICIES"
    
    # Check each policy for dangerous permissions
    for policy in $POLICIES; do
        echo "Checking policy: $policy"
        
        # Get the policy document
        POLICY_DOC=$(aws iam get-role-policy --role-name "$ROLE_NAME" --policy-name "$policy" --profile "$PROFILE" --query 'PolicyDocument' --output json)
        
        # Check if the policy contains dangerous permissions
        if echo "$POLICY_DOC" | jq -e '.Statement[] | select(.Effect == "Allow" and (.Action == "*" or (.Action | type == "array" and contains(["*"]))))' &> /dev/null; then
            echo -e "${YELLOW}Found potentially dangerous policy: $policy${NC}"
            echo "Policy content:"
            echo "$POLICY_DOC" | jq '.'
            
            # Ask for confirmation before deleting
            read -p "Do you want to delete this policy? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$policy" --profile "$PROFILE"
                echo -e "${GREEN}✓ Deleted policy: $policy${NC}"
            else
                echo -e "${YELLOW}⚠ Skipped deletion of policy: $policy${NC}"
            fi
        else
            echo -e "${GREEN}✓ Policy $policy appears safe${NC}"
        fi
    done
else
    echo -e "${GREEN}✓ No inline policies found${NC}"
fi

echo ""
echo -e "${YELLOW}Step 5: Verifying cleanup${NC}"
# Verify the role is back to its original state
echo "Current role policies:"
aws iam list-role-policies --role-name "$ROLE_NAME" --profile "$PROFILE"

echo ""
echo "Current attached managed policies:"
aws iam list-attached-role-policies --role-name "$ROLE_NAME" --profile "$PROFILE"

echo ""
echo -e "${GREEN}✓ Cleanup complete!${NC}"
echo "The role should now be back to its original state with only the intended policy attached."

echo ""
echo -e "${YELLOW}Step 6: Final verification${NC}"
# Show the current attached policy document
echo "Current attached policy document:"
POLICY_ARN=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --profile "$PROFILE" --query 'AttachedPolicies[0].PolicyArn' --output text)
aws iam get-policy --policy-arn "$POLICY_ARN" --profile "$PROFILE" --query 'Policy.DefaultVersionId' --output text | xargs -I {} aws iam get-policy-version --policy-arn "$POLICY_ARN" --version-id {} --profile "$PROFILE" --query 'PolicyVersion.Document' --output json | jq '.'

echo ""
echo -e "${GREEN}=== Cleanup Complete ===${NC}"
echo "The role has been restored to its original state."
echo "Only the intended 'pl-prod-self-privesc-putRolePolicy-policy' should remain attached."
