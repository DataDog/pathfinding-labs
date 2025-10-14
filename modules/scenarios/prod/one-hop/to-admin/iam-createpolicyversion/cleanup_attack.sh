#!/bin/bash

# Cleanup script for prod_self_privesc_createPolicyVersion module
# This script removes any changes made by the demo_attack.sh script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Pathfinder-labs Self-Privilege Escalation Cleanup (CreatePolicyVersion) ===${NC}"
echo "This script cleans up any changes made by the demo_attack.sh script"
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    exit 1
fi

# Check if the role exists
ROLE_NAME="pl-prod-self-privesc-createPolicyVersion-role-1"
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
echo -e "${YELLOW}Step 3: Getting policy information${NC}"
# Get the policy ARN
POLICY_ARN=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --profile "$PROFILE" --query 'AttachedPolicies[0].PolicyArn' --output text)
echo "Policy ARN: $POLICY_ARN"

echo ""
echo -e "${YELLOW}Step 4: Checking current policy versions${NC}"
# List current policy versions
echo "Current policy versions:"
aws iam list-policy-versions --policy-arn "$POLICY_ARN" --profile "$PROFILE"

echo ""
echo -e "${YELLOW}Step 5: Cleaning up policy versions (keeping only the first one)${NC}"
# Get all policy versions sorted by creation date
VERSIONS=$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" --profile "$PROFILE" --query 'sort_by(Versions, &CreateDate)[].VersionId' --output text)

if [ -n "$VERSIONS" ] && [ "$VERSIONS" != "None" ]; then
    echo "Found policy versions: $VERSIONS"
    
    # Find the version that has the correct permissions (not the admin version)
    KEEP_VERSION=""
    for version in $VERSIONS; do
        POLICY_DOC=$(aws iam get-policy-version --policy-arn "$POLICY_ARN" --version-id "$version" --profile "$PROFILE" --query 'PolicyDocument' --output json)
        
        # Check if this version has the correct permissions (not admin access)
        if echo "$POLICY_DOC" | jq -e '.Statement[] | select(.Effect == "Allow" and (.Action | type == "array" and contains(["iam:CreatePolicyVersion", "iam:SetDefaultPolicyVersion", "iam:ListPolicyVersions"])))' &> /dev/null; then
            # Check that it doesn't have admin access
            if ! echo "$POLICY_DOC" | jq -e '.Statement[] | select(.Effect == "Allow" and (.Action == "*" or (.Action | type == "array" and contains(["*"]))))' &> /dev/null; then
                KEEP_VERSION="$version"
                break
            fi
        fi
    done
    
    # If no suitable version found, keep the first one
    if [ -z "$KEEP_VERSION" ]; then
        VERSION_ARRAY=($VERSIONS)
        KEEP_VERSION="${VERSION_ARRAY[0]}"
    fi
    
    echo "Keeping version with correct permissions: $KEEP_VERSION"
    
    # Set the keep version as default to ensure it's safe to delete others
    echo "Setting keep version as default..."
    aws iam set-default-policy-version --policy-arn "$POLICY_ARN" --version-id "$KEEP_VERSION" --profile "$PROFILE"
    echo -e "${GREEN}✓ Set keep version as default${NC}"
    
    # Delete all other versions
    for version in $VERSIONS; do
        if [ "$version" != "$KEEP_VERSION" ]; then
            echo "Deleting policy version: $version"
            aws iam delete-policy-version --policy-arn "$POLICY_ARN" --version-id "$version" --profile "$PROFILE"
            echo -e "${GREEN}✓ Deleted policy version: $version${NC}"
        fi
    done
else
    echo -e "${GREEN}✓ No policy versions found${NC}"
fi

echo ""
echo -e "${YELLOW}Step 6: Verifying cleanup${NC}"
# Verify the policy is back to its original state
echo "Current policy versions:"
aws iam list-policy-versions --policy-arn "$POLICY_ARN" --profile "$PROFILE"

echo ""
echo "Current default policy version:"
DEFAULT_VERSION=$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" --profile "$PROFILE" --query 'Versions[?IsDefaultVersion==`true`].VersionId' --output text)
aws iam get-policy-version --policy-arn "$POLICY_ARN" --version-id "$DEFAULT_VERSION" --profile "$PROFILE"

echo ""
echo -e "${GREEN}✓ Cleanup complete!${NC}"
echo "The policy should now be back to its original state with only safe versions."

echo ""
echo -e "${YELLOW}Step 7: Final verification${NC}"
# Show the current policy document
echo "Current policy document:"
aws iam get-policy-version --policy-arn "$POLICY_ARN" --version-id "$DEFAULT_VERSION" --profile "$PROFILE" --query 'PolicyDocument' --output json | jq '.'

echo ""
echo -e "${GREEN}=== Cleanup Complete ===${NC}"
echo "The policy has been restored to its original state."
echo "Only safe policy versions should remain."
