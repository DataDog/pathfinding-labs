#!/bin/bash
#
# demo_permissions.sh - Shared library for temporarily restricting helpful permissions
# during demo_attack.sh validation runs.
#
# During demo runs, this library attaches an explicit deny inline policy to each
# principal that has helpful permissions, ensuring the attack succeeds with only
# required permissions. After the demo, the deny policies are removed so manual
# users can leverage helpful permissions freely.
#
# Usage in demo_attack.sh:
#   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#   source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"
#
#   restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
#   setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"
#   # ... run the demo ...
#   restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
#
# Usage in cleanup_attack.sh:
#   source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"
#   restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true
#
# Environment variables:
#   PL_SKIP_RESTRICTION=1  - Skip restriction entirely (for manual/interactive use)

# Guard against double-sourcing
if [ -n "$_DEMO_PERMISSIONS_LOADED" ]; then
    return 0 2>/dev/null || true
fi
_DEMO_PERMISSIONS_LOADED=1

# Colors (reuse from parent script if available, otherwise define)
_DP_YELLOW="${YELLOW:-\033[1;33m}"
_DP_GREEN="${GREEN:-\033[0;32m}"
_DP_RED="${RED:-\033[0;31m}"
_DP_NC="${NC:-\033[0m}"

# Policy name used for the deny restriction
_DP_POLICY_NAME="pl-demo-validation-restriction"

# Track which principals we've restricted (for trap cleanup)
_DP_RESTRICTED_PRINCIPALS=()
_DP_SCENARIO_YAML_PATH=""

# Admin credentials for attaching/removing policies
_DP_ADMIN_ACCESS_KEY=""
_DP_ADMIN_SECRET_KEY=""

# ============================================================================
# Internal: Retrieve admin cleanup credentials from Terraform outputs
# ============================================================================
_dp_get_admin_creds() {
    if [ -n "$_DP_ADMIN_ACCESS_KEY" ]; then
        return 0
    fi

    # Navigate to project root to get terraform outputs
    local script_dir="$1"
    local project_root
    project_root="$(cd "$script_dir" && cd ../../../../../.. 2>/dev/null && pwd)"

    if [ -z "$project_root" ] || [ ! -f "$project_root/main.tf" ]; then
        # Try alternative depth (cross-account scenarios are deeper)
        project_root="$(cd "$script_dir" && cd ../../../../../../.. 2>/dev/null && pwd)"
    fi

    if [ -z "$project_root" ] || [ ! -f "$project_root/main.tf" ]; then
        echo -e "${_DP_RED}[demo_permissions] Error: Could not find project root from $script_dir${_DP_NC}" >&2
        return 1
    fi

    local orig_dir
    orig_dir="$(pwd)"
    cd "$project_root" || return 1

    _DP_ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
    _DP_ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)

    cd "$orig_dir" || true

    if [ -z "$_DP_ADMIN_ACCESS_KEY" ] || [ "$_DP_ADMIN_ACCESS_KEY" == "null" ]; then
        echo -e "${_DP_RED}[demo_permissions] Error: Could not retrieve admin cleanup credentials${_DP_NC}" >&2
        return 1
    fi
}

# ============================================================================
# Internal: Run an AWS CLI command using admin credentials
# ============================================================================
_dp_aws_as_admin() {
    AWS_ACCESS_KEY_ID="$_DP_ADMIN_ACCESS_KEY" \
    AWS_SECRET_ACCESS_KEY="$_DP_ADMIN_SECRET_KEY" \
    AWS_SESSION_TOKEN="" \
    aws "$@"
}

# ============================================================================
# Internal: Parse helpful permissions from scenario.yaml
# Returns JSON array of objects: [{principal, principal_type, permissions: [action, ...]}]
# ============================================================================
_dp_parse_helpful_principals() {
    local yaml_path="$1"

    if [ ! -f "$yaml_path" ]; then
        echo "[]"
        return 0
    fi

    python3 -c "
import yaml, json, sys

with open('$yaml_path') as f:
    data = yaml.safe_load(f)

helpful = data.get('permissions', {}).get('helpful', [])
if not helpful:
    print('[]')
    sys.exit(0)

# Handle both per-principal format (new) and flat format (legacy)
result = []
if helpful and isinstance(helpful[0], dict) and 'principal' in helpful[0]:
    # New per-principal format
    for entry in helpful:
        actions = [p['permission'] for p in entry.get('permissions', [])]
        if actions:
            result.append({
                'principal': entry['principal'],
                'principal_type': entry['principal_type'],
                'permissions': actions
            })
else:
    # Legacy flat format - cannot determine principal, skip restriction
    # (scenario.yaml needs to be migrated to per-principal format first)
    print('[]')
    sys.exit(0)

print(json.dumps(result))
" 2>/dev/null || echo "[]"
}

# ============================================================================
# Internal: Attach deny policy to a single principal
# ============================================================================
_dp_attach_deny_policy() {
    local principal_name="$1"
    local principal_type="$2"
    local permissions_json="$3"

    # Build the deny policy document
    local policy_doc
    policy_doc=$(python3 -c "
import json, sys
actions = json.loads('$permissions_json')
policy = {
    'Version': '2012-10-17',
    'Statement': [{
        'Sid': 'PlDemoValidationRestriction',
        'Effect': 'Deny',
        'Action': actions,
        'Resource': '*'
    }]
}
print(json.dumps(policy))
" 2>/dev/null)

    if [ -z "$policy_doc" ]; then
        echo -e "${_DP_RED}[demo_permissions] Error: Failed to build deny policy for $principal_name${_DP_NC}" >&2
        return 1
    fi

    if [ "$principal_type" = "user" ]; then
        _dp_aws_as_admin iam put-user-policy \
            --user-name "$principal_name" \
            --policy-name "$_DP_POLICY_NAME" \
            --policy-document "$policy_doc" 2>/dev/null
    elif [ "$principal_type" = "role" ]; then
        _dp_aws_as_admin iam put-role-policy \
            --role-name "$principal_name" \
            --policy-name "$_DP_POLICY_NAME" \
            --policy-document "$policy_doc" 2>/dev/null
    else
        echo -e "${_DP_RED}[demo_permissions] Error: Unknown principal_type '$principal_type' for $principal_name${_DP_NC}" >&2
        return 1
    fi
}

# ============================================================================
# Internal: Remove deny policy from a single principal
# ============================================================================
_dp_remove_deny_policy() {
    local principal_name="$1"
    local principal_type="$2"

    if [ "$principal_type" = "user" ]; then
        _dp_aws_as_admin iam delete-user-policy \
            --user-name "$principal_name" \
            --policy-name "$_DP_POLICY_NAME" 2>/dev/null || true
    elif [ "$principal_type" = "role" ]; then
        _dp_aws_as_admin iam delete-role-policy \
            --role-name "$principal_name" \
            --policy-name "$_DP_POLICY_NAME" 2>/dev/null || true
    fi
}

# ============================================================================
# Public: Restrict helpful permissions on all principals in scenario.yaml
# ============================================================================
restrict_helpful_permissions() {
    local scenario_yaml="$1"
    _DP_SCENARIO_YAML_PATH="$scenario_yaml"

    # Skip if restriction is disabled
    if [ "${PL_SKIP_RESTRICTION:-0}" = "1" ]; then
        echo -e "${_DP_YELLOW}[demo_permissions] Skipping restriction (PL_SKIP_RESTRICTION=1)${_DP_NC}"
        return 0
    fi

    local script_dir
    script_dir="$(dirname "$scenario_yaml")"

    # Get admin credentials
    if ! _dp_get_admin_creds "$script_dir"; then
        echo -e "${_DP_RED}[demo_permissions] Warning: Could not get admin creds, skipping restriction${_DP_NC}" >&2
        return 0
    fi

    # Parse helpful principals from scenario.yaml
    local principals_json
    principals_json=$(_dp_parse_helpful_principals "$scenario_yaml")

    if [ "$principals_json" = "[]" ]; then
        echo -e "${_DP_YELLOW}[demo_permissions] No helpful permissions to restrict${_DP_NC}"
        return 0
    fi

    echo -e "${_DP_YELLOW}[demo_permissions] Restricting helpful permissions for validation...${_DP_NC}"

    # Attach deny policy to each principal
    local count
    count=$(echo "$principals_json" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")

    local i=0
    while [ $i -lt "$count" ]; do
        local principal_name principal_type permissions
        principal_name=$(echo "$principals_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[$i]['principal'])")
        principal_type=$(echo "$principals_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[$i]['principal_type'])")
        permissions=$(echo "$principals_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d[$i]['permissions']))")

        if _dp_attach_deny_policy "$principal_name" "$principal_type" "$permissions"; then
            _DP_RESTRICTED_PRINCIPALS+=("$principal_name:$principal_type")
            echo -e "  Denied helpful permissions on $principal_type: $principal_name"
        else
            echo -e "${_DP_RED}  Failed to restrict $principal_type: $principal_name${_DP_NC}" >&2
        fi

        i=$((i + 1))
    done

    # Wait for IAM propagation
    echo -e "${_DP_YELLOW}[demo_permissions] Waiting 15s for IAM policy propagation...${_DP_NC}"
    sleep 15
    echo -e "${_DP_GREEN}[demo_permissions] Helpful permissions restricted${_DP_NC}"
}

# ============================================================================
# Public: Restore helpful permissions on all principals
# ============================================================================
restore_helpful_permissions() {
    local scenario_yaml="${1:-$_DP_SCENARIO_YAML_PATH}"

    # Skip if restriction was disabled
    if [ "${PL_SKIP_RESTRICTION:-0}" = "1" ]; then
        return 0
    fi

    local script_dir
    script_dir="$(dirname "$scenario_yaml")"

    # Get admin credentials if we don't have them
    if ! _dp_get_admin_creds "$script_dir" 2>/dev/null; then
        return 0
    fi

    # If we tracked which principals were restricted, use that list
    if [ ${#_DP_RESTRICTED_PRINCIPALS[@]} -gt 0 ]; then
        echo -e "${_DP_YELLOW}[demo_permissions] Restoring helpful permissions...${_DP_NC}"
        for entry in "${_DP_RESTRICTED_PRINCIPALS[@]}"; do
            local principal_name="${entry%%:*}"
            local principal_type="${entry##*:}"
            _dp_remove_deny_policy "$principal_name" "$principal_type"
            echo -e "  Restored $principal_type: $principal_name"
        done
        _DP_RESTRICTED_PRINCIPALS=()
        echo -e "${_DP_GREEN}[demo_permissions] Helpful permissions restored${_DP_NC}"
        return 0
    fi

    # Fallback: parse scenario.yaml and remove deny policies from all principals
    local principals_json
    principals_json=$(_dp_parse_helpful_principals "$scenario_yaml")

    if [ "$principals_json" = "[]" ]; then
        return 0
    fi

    local count
    count=$(echo "$principals_json" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null)

    if [ -z "$count" ] || [ "$count" = "0" ]; then
        return 0
    fi

    echo -e "${_DP_YELLOW}[demo_permissions] Restoring helpful permissions...${_DP_NC}"

    local i=0
    while [ $i -lt "$count" ]; do
        local principal_name principal_type
        principal_name=$(echo "$principals_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[$i]['principal'])")
        principal_type=$(echo "$principals_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[$i]['principal_type'])")

        _dp_remove_deny_policy "$principal_name" "$principal_type"
        echo -e "  Restored $principal_type: $principal_name"

        i=$((i + 1))
    done

    echo -e "${_DP_GREEN}[demo_permissions] Helpful permissions restored${_DP_NC}"
}

# ============================================================================
# Public: Set up a trap to restore permissions on script exit/failure
# ============================================================================
setup_demo_restriction_trap() {
    local scenario_yaml="$1"
    _DP_SCENARIO_YAML_PATH="$scenario_yaml"

    # Skip if restriction is disabled
    if [ "${PL_SKIP_RESTRICTION:-0}" = "1" ]; then
        return 0
    fi

    trap '_dp_trap_handler' EXIT INT TERM
}

_dp_trap_handler() {
    # Prevent re-entry: clear traps before doing anything
    trap - EXIT INT TERM

    if [ ${#_DP_RESTRICTED_PRINCIPALS[@]} -gt 0 ]; then
        echo ""
        echo -e "${_DP_YELLOW}[demo_permissions] Script interrupted, restoring permissions...${_DP_NC}"
        restore_helpful_permissions "$_DP_SCENARIO_YAML_PATH" 2>/dev/null || true
    fi

    # Exit explicitly so the script doesn't resume after Ctrl+C
    exit 130
}
