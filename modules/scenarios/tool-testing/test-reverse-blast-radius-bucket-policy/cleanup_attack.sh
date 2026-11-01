#!/bin/bash

# Cleanup script for test-reverse-blast-radius-bucket-policy
# Removes the probe object(s) the demo wrote to the scenario bucket under the
# rbr-bp-demo/ prefix. The demo does NOT modify sensitive-data.txt, but as a
# defensive measure this script restores it if its content ever changed.

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

DEMO_PREFIX="rbr-bp-demo"
SENSITIVE_KEY="sensitive-data.txt"
SENSITIVE_EXPECTED_CONTENT="Sensitive data for reverse-blast-radius bucket-policy testing."
PROBE_BODY_FILE="/tmp/rbr-bp-probe-body.txt"  # local file created by demo_attack.sh

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Reverse Blast Radius Bucket Policy${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin cleanup credentials, region and bucket name from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../..  # Navigate to root of terraform project

ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)
CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")
BUCKET_NAME=$(terraform output -json 2>/dev/null | jq -r '.tool_testing_test_reverse_blast_radius_bucket_policy.value.bucket_name // empty')

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup credentials in terraform output${NC}"
    echo "Make sure the admin cleanup user is deployed"
    exit 1
fi

if [ -z "$CURRENT_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    CURRENT_REGION="us-east-1"
fi

export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_REGION="$CURRENT_REGION"
unset AWS_SESSION_TOKEN

echo "Region from Terraform: $CURRENT_REGION"
echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Safety restore: ensure helpful permissions deny policy is removed
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../scripts/lib/demo_permissions.sh"
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

# The library sourcing does not change credentials, but re-assert admin creds
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_REGION="$CURRENT_REGION"
unset AWS_SESSION_TOKEN

# Step 2: Remove demo probe objects (all versions, in case bucket versioning is on)
echo -e "${YELLOW}Step 2: Removing probe objects from the scenario bucket${NC}"
FAILED=0

if [ -z "$BUCKET_NAME" ]; then
    echo -e "${YELLOW}Bucket name not available from Terraform (scenario not deployed?), skipping${NC}"
else
    echo "Bucket: $BUCKET_NAME"
    echo "Prefix: $DEMO_PREFIX/"

    VERSIONS=$(aws s3api list-object-versions \
        --region "$CURRENT_REGION" \
        --bucket "$BUCKET_NAME" \
        --prefix "$DEMO_PREFIX/" \
        --query '[Versions[].[Key,VersionId], DeleteMarkers[].[Key,VersionId]][]' \
        --output json 2>/dev/null || echo "[]")

    if [ -z "$VERSIONS" ] || [ "$VERSIONS" == "null" ] || [ "$VERSIONS" == "[]" ]; then
        echo -e "${YELLOW}No probe objects found (may already be cleaned)${NC}"
    else
        while IFS=$'\t' read -r OBJECT_KEY OBJECT_VERSION_ID; do
            [ -z "$OBJECT_KEY" ] && continue
            echo "Deleting: $OBJECT_KEY (version $OBJECT_VERSION_ID)"
            if aws s3api delete-object \
                --region "$CURRENT_REGION" \
                --bucket "$BUCKET_NAME" \
                --key "$OBJECT_KEY" \
                --version-id "$OBJECT_VERSION_ID" > /dev/null; then
                echo -e "${GREEN}✓ Deleted $OBJECT_KEY${NC}"
            else
                echo -e "${RED}✗ Failed to delete $OBJECT_KEY${NC}"
                FAILED=1
            fi
        done < <(echo "$VERSIONS" | jq -r '.[] | select(.[0] != null) | [.[0], (.[1] // "null")] | @tsv')
    fi

    # Non-versioned fallback / belt and braces
    aws s3 rm "s3://$BUCKET_NAME/$DEMO_PREFIX/" --region "$CURRENT_REGION" --recursive > /dev/null 2>&1 || true
fi
echo ""

# Step 3: Restore sensitive-data.txt only if the demo somehow modified it.
# The demo only READS this object, so normally nothing happens here.
echo -e "${YELLOW}Step 3: Verifying sensitive-data.txt is unchanged${NC}"
if [ -z "$BUCKET_NAME" ]; then
    echo -e "${YELLOW}Bucket name not available, skipping${NC}"
else
    CHECK_FILE="/tmp/rbr-bp-sensitive-check.txt"
    if aws s3api get-object \
        --region "$CURRENT_REGION" \
        --bucket "$BUCKET_NAME" \
        --key "$SENSITIVE_KEY" \
        "$CHECK_FILE" > /dev/null 2>&1; then
        if grep -qF "$SENSITIVE_EXPECTED_CONTENT" "$CHECK_FILE"; then
            echo -e "${GREEN}✓ sensitive-data.txt is intact (demo did not modify it)${NC}"
        else
            echo -e "${YELLOW}sensitive-data.txt content changed, restoring original...${NC}"
            printf '%s\n' "$SENSITIVE_EXPECTED_CONTENT" > "$CHECK_FILE"
            if aws s3api put-object \
                --region "$CURRENT_REGION" \
                --bucket "$BUCKET_NAME" \
                --key "$SENSITIVE_KEY" \
                --body "$CHECK_FILE" > /dev/null 2>&1; then
                echo -e "${GREEN}✓ Restored sensitive-data.txt${NC}"
            else
                echo -e "${RED}✗ Failed to restore sensitive-data.txt${NC}"
                FAILED=1
            fi
        fi
    else
        echo -e "${YELLOW}Could not read sensitive-data.txt (may be absent), skipping${NC}"
    fi
    rm -f "$CHECK_FILE"
fi
echo ""

# Remove the local probe body file if the demo was interrupted before it could
rm -f "$PROBE_BODY_FILE"

if [ "$FAILED" -ne 0 ]; then
    echo -e "${RED}Cleanup finished with errors${NC}"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Removed probe object(s) under $DEMO_PREFIX/ from the scenario bucket"
echo "- Verified (and restored if needed) sensitive-data.txt"
echo "- Removed local file $PROBE_BODY_FILE (if present)"
echo "- No IAM policies were modified by the demo"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, role, and bucket) remains deployed.${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
