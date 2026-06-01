#!/bin/bash

# Print starting credentials and attack context for the scheduler-001 scenario.
# Read-only — does not modify any AWS resources.

TERRAFORM_ROOT="$(cd "$(dirname "$0")/../../../../../.." && pwd)"

MODULE_OUTPUT=$(terraform -chdir="$TERRAFORM_ROOT" output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_scheduler_001.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo "Error: Could not find terraform output for scheduler-001 scenario."
    echo "Make sure the scenario is deployed: plabs apply"
    exit 1
fi

echo "=== scheduler-001: PassRole + EventBridge Scheduler ==="
echo ""
echo "Starting User:           $(echo "$MODULE_OUTPUT" | jq -r '.starting_user_name')"
echo "Access Key ID:           $(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')"
echo "Secret Access Key:       $(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')"
echo ""
echo "Scheduler Role ARN:      $(echo "$MODULE_OUTPUT" | jq -r '.scheduler_role_arn')"
echo "Scheduler Role Name:     $(echo "$MODULE_OUTPUT" | jq -r '.scheduler_role_name')"
echo ""
echo "Flag SSM Parameter:      $(echo "$MODULE_OUTPUT" | jq -r '.flag_ssm_parameter_name')"
echo ""
echo "Attack Path:"
echo "  $(echo "$MODULE_OUTPUT" | jq -r '.attack_path')"
