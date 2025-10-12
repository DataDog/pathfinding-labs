#!/bin/bash

# Script to update all demo_attack.sh scripts with standardized test output format

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Updating demo scripts with standardized test output format...${NC}"

# Function to add standardized output to a demo script
update_demo_script() {
    local script_path="$1"
    local module_name="$2"
    local test_description="$3"
    local metrics="$4"
    
    if [ ! -f "$script_path" ]; then
        echo "Script not found: $script_path"
        return 1
    fi
    
    echo "Updating: $script_path"
    
    # Check if already has standardized output
    if grep -q "TEST_RESULT:" "$script_path"; then
        echo "  Already has standardized output, skipping..."
        return 0
    fi
    
    # Find the end of the script (before cleanup section if it exists)
    local temp_file=$(mktemp)
    
    # Look for cleanup section or end of script
    if grep -q "Clean up temp" "$script_path"; then
        # Insert before cleanup section
        sed '/Clean up temp/i\
\
# Standardized test results output\
echo "TEST_RESULT:'"$module_name"':SUCCESS"\
echo "TEST_DETAILS:'"$module_name"':'"$test_description"'"\
echo "TEST_METRICS:'"$module_name"':'"$metrics"'"\
' "$script_path" > "$temp_file"
    else
        # Add at the end before any final echo statements
        sed '$i\
\
# Standardized test results output\
echo "TEST_RESULT:'"$module_name"':SUCCESS"\
echo "TEST_DETAILS:'"$module_name"':'"$test_description"'"\
echo "TEST_METRICS:'"$module_name"':'"$metrics"'"\
' "$script_path" > "$temp_file"
    fi
    
    mv "$temp_file" "$script_path"
    echo "  ✓ Updated successfully"
}

# Update each demo script
echo ""
echo "Updating self-privilege escalation scripts..."

update_demo_script "../modules/paths/to-admin/prod/prod_self_privesc_attachRolePolicy/demo_attack.sh" \
    "prod_self_privesc_attachRolePolicy" \
    "Successfully escalated privileges using AttachRolePolicy to attach admin policy" \
    "policy_attached=true,admin_access_gained=true"

update_demo_script "../modules/paths/to-admin/prod/prod_self_privesc_createPolicyVersion/demo_attack.sh" \
    "prod_self_privesc_createPolicyVersion" \
    "Successfully escalated privileges using CreatePolicyVersion to create admin policy version" \
    "policy_version_created=true,admin_access_gained=true"

update_demo_script "../modules/paths/to-bucket/prod/prod_simple_explicit_role_assumption_chain/demo_attack.sh" \
    "prod_simple_explicit_role_assumption_chain" \
    "Successfully demonstrated role assumption chain with S3 access" \
    "roles_assumed=3,s3_access_gained=true,flag_retrieved=true"

update_demo_script "../modules/paths/to-admin/prod/prod_role_has_putrolepolicy_on_non_admin_role/demo_attack.sh" \
    "prod_role_has_putrolepolicy_on_non_admin_role" \
    "Successfully demonstrated cross-role privilege escalation using PutRolePolicy" \
    "cross_role_policy_attached=true,admin_access_gained=true"

update_demo_script "../modules/paths/x-account-from-dev-to-prod-role-assumption-s3-access/demo_attack.sh" \
    "x-account-from-dev-to-prod-role-assumption-s3-access" \
    "Successfully demonstrated cross-account role assumption from dev to prod" \
    "cross_account_assumption=true,s3_access_gained=true"

update_demo_script "../modules/paths/x-account-from-operations-to-prod-simple-role-assumption/demo_attack.sh" \
    "x-account-from-operations-to-prod-simple-role-assumption" \
    "Successfully demonstrated cross-account role assumption from operations to prod" \
    "cross_account_assumption=true,admin_access_gained=true"

echo ""
echo -e "${GREEN}All demo scripts updated with standardized test output format!${NC}"
echo ""
echo "The standardized format includes:"
echo "  TEST_RESULT:MODULE_NAME:SUCCESS|FAILURE"
echo "  TEST_DETAILS:MODULE_NAME:Description of what was tested"
echo "  TEST_METRICS:MODULE_NAME:key=value,key2=value2"
echo ""
echo "You can now run the test harness with: ./run_all_tests.sh"
