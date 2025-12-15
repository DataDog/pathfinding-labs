#!/bin/bash

# Pathfinding-labs Cleanup Runner
# Runs all cleanup scripts and reports the results

set -e

# Ensure we're using bash 4+ for associative arrays
if [ -z "$BASH_VERSION" ]; then
    echo "This script requires bash for associative arrays. Please run with: bash $0"
    exit 1
fi

# Check bash version (associative arrays require bash 4+)
if [ "${BASH_VERSION%%.*}" -lt 4 ]; then
    echo "This script requires bash 4+ for associative arrays. Current version: $BASH_VERSION"
    echo "Please upgrade bash or run with: bash $0"
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLEANUP_RESULTS_DIR="cleanup_results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RESULTS_FILE="$CLEANUP_RESULTS_DIR/cleanup_results_$TIMESTAMP.json"
SUMMARY_FILE="$CLEANUP_RESULTS_DIR/cleanup_summary_$TIMESTAMP.txt"

# Create results directory
mkdir -p "$CLEANUP_RESULTS_DIR"

echo -e "${BLUE}=== Pathfinding-labs Cleanup Runner ===${NC}"
echo "Timestamp: $TIMESTAMP"
echo "Results will be saved to: $RESULTS_FILE"
echo ""

# Initialize results
declare -A cleanup_results
declare -A cleanup_details
declare -A cleanup_execution_times

# Cleanup modules configuration (only modules with cleanup_attack.sh scripts)
declare -a cleanup_modules=(
    "to-admin/prod/prod_self_privesc_putRolePolicy"
    "to-admin/prod/prod_self_privesc_attachRolePolicy" 
    "to-admin/prod/prod_self_privesc_createPolicyVersion"
    "to-admin/prod/prod_role_with_multiple_privesc_paths"
    "to-admin/dev/dev__user_has_createAccessKey_to_admin"
    "to-admin/x-account/x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin"
    "to-admin/x-account/x-account-from-dev-to-prod-multi-hop-privesc-both-sides"
    "to-bucket/prod/prod_role_has_access_to_bucket_through_resource_policy"
    "to-bucket/prod/prod_role_has_exclusive_access_to_bucket_through_resource_policy"
)

# Function to run a single cleanup
run_cleanup() {
    local module_name="$1"
    local module_path="../modules/paths/$module_name"
    local cleanup_script="$module_path/cleanup_attack.sh"
    
    echo -e "${YELLOW}Running cleanup: $module_name${NC}"
    
    if [ ! -f "$cleanup_script" ]; then
        echo -e "${RED}✗ Cleanup script not found: $cleanup_script${NC}"
        cleanup_results["$module_name"]="FAILURE"
        cleanup_details["$module_name"]="Cleanup script not found"
        cleanup_execution_times["$module_name"]="0"
        return 1
    fi
    
    if [ ! -x "$cleanup_script" ]; then
        echo -e "${RED}✗ Cleanup script not executable: $cleanup_script${NC}"
        cleanup_results["$module_name"]="FAILURE"
        cleanup_details["$module_name"]="Cleanup script not executable"
        cleanup_execution_times["$module_name"]="0"
        return 1
    fi
    
    # Record start time
    local start_time=$(date +%s)
    
    # Run the cleanup and capture output
    local cleanup_output
    local cleanup_exit_code
    
    if cleanup_output=$(cd "$module_path" && timeout 300 ./cleanup_attack.sh 2>&1); then
        cleanup_exit_code=0
    else
        cleanup_exit_code=$?
    fi
    
    # Record end time
    local end_time=$(date +%s)
    local execution_time=$((end_time - start_time))
    cleanup_execution_times["$module_name"]="$execution_time"
    
    # Determine result based on exit code and output
    local result="UNKNOWN"
    local details="No details provided"
    
    if [ $cleanup_exit_code -eq 0 ]; then
        # Check for success indicators in output
        if echo "$cleanup_output" | grep -q "Cleanup Complete\|cleanup complete\|✓.*complete"; then
            echo -e "${GREEN}✓ $module_name: SUCCESS (${execution_time}s)${NC}"
            cleanup_results["$module_name"]="SUCCESS"
            details="Cleanup completed successfully"
        else
            echo -e "${YELLOW}⚠ $module_name: PARTIAL (${execution_time}s)${NC}"
            cleanup_results["$module_name"]="PARTIAL"
            details="Cleanup completed but no clear success indicator found"
        fi
    else
        echo -e "${RED}✗ $module_name: FAILURE (${execution_time}s)${NC}"
        cleanup_results["$module_name"]="FAILURE"
        if [ $cleanup_exit_code -eq 124 ]; then
            details="Cleanup timed out after 5 minutes"
        else
            details="Cleanup failed with exit code $cleanup_exit_code"
        fi
    fi
    
    cleanup_details["$module_name"]="$details"
    
    # Save detailed output for failed/partial cleanups
    if [ "${cleanup_results[$module_name]}" != "SUCCESS" ]; then
        echo "$cleanup_output" > "$CLEANUP_RESULTS_DIR/${module_name}_cleanup_$TIMESTAMP.log"
        echo -e "${YELLOW}  Detailed logs saved to: ${module_name}_cleanup_$TIMESTAMP.log${NC}"
    fi
    
    echo ""
}

# Function to generate JSON report
generate_json_report() {
    echo "{" > "$RESULTS_FILE"
    echo "  \"timestamp\": \"$TIMESTAMP\"," >> "$RESULTS_FILE"
    echo "  \"summary\": {" >> "$RESULTS_FILE"
    echo "    \"total_cleanups\": ${#cleanup_modules[@]}," >> "$RESULTS_FILE"
    echo "    \"successful\": $(printf '%s\n' "${cleanup_results[@]}" | grep -c "SUCCESS" || true)," >> "$RESULTS_FILE"
    echo "    \"partial\": $(printf '%s\n' "${cleanup_results[@]}" | grep -c "PARTIAL" || true)," >> "$RESULTS_FILE"
    echo "    \"failed\": $(printf '%s\n' "${cleanup_results[@]}" | grep -c "FAILURE" || true)" >> "$RESULTS_FILE"
    echo "  }," >> "$RESULTS_FILE"
    echo "  \"cleanups\": [" >> "$RESULTS_FILE"
    
    local first=true
    for module in "${cleanup_modules[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$RESULTS_FILE"
        fi
        
        echo "    {" >> "$RESULTS_FILE"
        echo "      \"module\": \"$module\"," >> "$RESULTS_FILE"
        echo "      \"result\": \"${cleanup_results[$module]}\"," >> "$RESULTS_FILE"
        echo "      \"details\": \"${cleanup_details[$module]}\"," >> "$RESULTS_FILE"
        echo "      \"execution_time\": \"${cleanup_execution_times[$module]}s\"" >> "$RESULTS_FILE"
        echo "    }" >> "$RESULTS_FILE"
    done
    
    echo "  ]" >> "$RESULTS_FILE"
    echo "}" >> "$RESULTS_FILE"
}

# Function to generate summary report
generate_summary_report() {
    {
        echo "Pathfinding-labs Cleanup Results Summary"
        echo "======================================"
        echo "Timestamp: $TIMESTAMP"
        echo ""
        
        local total_cleanups=${#cleanup_modules[@]}
        local successful=$(printf '%s\n' "${cleanup_results[@]}" | grep -c "SUCCESS" || true)
        local partial=$(printf '%s\n' "${cleanup_results[@]}" | grep -c "PARTIAL" || true)
        local failed=$(printf '%s\n' "${cleanup_results[@]}" | grep -c "FAILURE" || true)
        
        echo "Overall Results:"
        echo "  Total Cleanups: $total_cleanups"
        echo "  Successful: $successful"
        echo "  Partial: $partial"
        echo "  Failed: $failed"
        echo "  Success Rate: $(( (successful + partial) * 100 / total_cleanups ))%"
        echo ""
        
        echo "Individual Cleanup Results:"
        echo "---------------------------"
        for module in "${cleanup_modules[@]}"; do
            local status="${cleanup_results[$module]}"
            local time="${cleanup_execution_times[$module]}s"
            local details="${cleanup_details[$module]}"
            
            if [ "$status" = "SUCCESS" ]; then
                echo "✓ $module ($time) - $details"
            elif [ "$status" = "PARTIAL" ]; then
                echo "⚠ $module ($time) - $details"
            else
                echo "✗ $module ($time) - $details"
            fi
        done
        
        echo ""
        echo "Detailed logs for failed/partial cleanups are available in: $CLEANUP_RESULTS_DIR/"
    } > "$SUMMARY_FILE"
}

# Main execution
echo -e "${BLUE}Starting cleanup execution...${NC}"
echo ""

# Run all cleanups
for module in "${cleanup_modules[@]}"; do
    run_cleanup "$module"
done

# Generate reports
echo -e "${BLUE}Generating reports...${NC}"
generate_json_report
generate_summary_report

# Display summary
echo -e "${BLUE}=== Cleanup Execution Complete ===${NC}"
echo ""

# Show summary
cat "$SUMMARY_FILE"

echo ""
echo -e "${GREEN}Reports generated:${NC}"
echo "  JSON Report: $RESULTS_FILE"
echo "  Summary Report: $SUMMARY_FILE"
echo "  Detailed logs: $CLEANUP_RESULTS_DIR/"

# Exit with appropriate code
local failed_count=$(printf '%s\n' "${cleanup_results[@]}" | grep -c "FAILURE" || true)
if [ "$failed_count" -eq 0 ]; then
    echo -e "${GREEN}All cleanups completed successfully!${NC}"
    exit 0
else
    echo -e "${RED}$failed_count cleanup(s) failed.${NC}"
    exit 1
fi
