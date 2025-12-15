#!/bin/bash

# Pathfinding-labs Test Harness
# Runs all demo scripts and parses standardized output for pass/fail reporting

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
TEST_RESULTS_DIR="test_results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RESULTS_FILE="$TEST_RESULTS_DIR/test_results_$TIMESTAMP.json"
SUMMARY_FILE="$TEST_RESULTS_DIR/test_summary_$TIMESTAMP.txt"

# Create results directory
mkdir -p "$TEST_RESULTS_DIR"

echo -e "${BLUE}=== Pathfinding-labs Test Harness ===${NC}"
echo "Timestamp: $TIMESTAMP"
echo "Results will be saved to: $RESULTS_FILE"
echo ""

# Initialize results
declare -A test_results
declare -A test_details
declare -A test_metrics
declare -A test_execution_times

# Test modules configuration (only modules with demo_attack.sh scripts)
declare -a test_modules=(
    "to-admin/prod/prod_self_privesc_putRolePolicy"
    "to-admin/prod/prod_self_privesc_attachRolePolicy" 
    "to-admin/prod/prod_self_privesc_createPolicyVersion"
    "to-admin/prod/prod_role_with_multiple_privesc_paths"
    "to-bucket/prod/prod_simple_explicit_role_assumption_chain"
    "to-admin/prod/prod_role_has_putrolepolicy_on_non_admin_role"
    "to-bucket/x-account/x-account-from-dev-to-prod-role-assumption-s3-access"
    "to-admin/x-account/x-account-from-operations-to-prod-simple-role-assumption"
    "to-admin/dev/dev__user_has_createAccessKey_to_admin"
    "to-admin/x-account/x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin"
    "to-admin/x-account/x-account-from-dev-to-prod-multi-hop-privesc-both-sides"
    "to-bucket/prod/prod_role_has_access_to_bucket_through_resource_policy"
    "to-bucket/prod/prod_role_has_exclusive_access_to_bucket_through_resource_policy"
    "to-admin/x-account/x-account-from-dev-to-prod-invoke-and-update-on-prod-lambda"
)

# Function to run a single test
run_test() {
    local module_name="$1"
    local module_path="../modules/paths/$module_name"
    local demo_script="$module_path/demo_attack.sh"
    
    echo -e "${YELLOW}Running test: $module_name${NC}"
    
    if [ ! -f "$demo_script" ]; then
        echo -e "${RED}✗ Demo script not found: $demo_script${NC}"
        test_results["$module_name"]="FAILURE"
        test_details["$module_name"]="Demo script not found"
        test_metrics["$module_name"]="error=script_not_found"
        test_execution_times["$module_name"]="0"
        return 1
    fi
    
    if [ ! -x "$demo_script" ]; then
        echo -e "${RED}✗ Demo script not executable: $demo_script${NC}"
        test_results["$module_name"]="FAILURE"
        test_details["$module_name"]="Demo script not executable"
        test_metrics["$module_name"]="error=not_executable"
        test_execution_times["$module_name"]="0"
        return 1
    fi
    
    # Record start time
    local start_time=$(date +%s)
    
    # Run the test and capture output
    local test_output
    local test_exit_code
    
    if test_output=$(cd "$module_path" && timeout 300 ./demo_attack.sh 2>&1); then
        test_exit_code=0
    else
        test_exit_code=$?
    fi
    
    # Record end time
    local end_time=$(date +%s)
    local execution_time=$((end_time - start_time))
    test_execution_times["$module_name"]="$execution_time"
    
    # Parse standardized output
    local result="UNKNOWN"
    local details="No details provided"
    local metrics="execution_time=${execution_time}s"
    
    # Extract TEST_RESULT
    local result_line=$(echo "$test_output" | grep "^TEST_RESULT:$module_name:" | tail -1)
    if [ -n "$result_line" ]; then
        result=$(echo "$result_line" | cut -d: -f3)
    fi
    
    # Extract TEST_DETAILS
    local details_line=$(echo "$test_output" | grep "^TEST_DETAILS:$module_name:" | tail -1)
    if [ -n "$details_line" ]; then
        details=$(echo "$details_line" | cut -d: -f3-)
    fi
    
    # Extract TEST_METRICS
    local metrics_line=$(echo "$test_output" | grep "^TEST_METRICS:$module_name:" | tail -1)
    if [ -n "$metrics_line" ]; then
        local extracted_metrics=$(echo "$metrics_line" | cut -d: -f3-)
        metrics="$extracted_metrics,execution_time=${execution_time}s"
    fi
    
    # Determine final result based on exit code and parsed result
    if [ $test_exit_code -eq 0 ] && [ "$result" = "SUCCESS" ]; then
        echo -e "${GREEN}✓ $module_name: SUCCESS (${execution_time}s)${NC}"
        test_results["$module_name"]="SUCCESS"
    else
        echo -e "${RED}✗ $module_name: FAILURE (${execution_time}s)${NC}"
        test_results["$module_name"]="FAILURE"
        if [ $test_exit_code -ne 0 ]; then
            details="Script failed with exit code $test_exit_code. $details"
        fi
    fi
    
    test_details["$module_name"]="$details"
    test_metrics["$module_name"]="$metrics"
    
    # Save detailed output for failed tests
    if [ "${test_results[$module_name]}" = "FAILURE" ]; then
        echo "$test_output" > "$TEST_RESULTS_DIR/${module_name}_failure_$TIMESTAMP.log"
        echo -e "${YELLOW}  Detailed logs saved to: ${module_name}_failure_$TIMESTAMP.log${NC}"
    fi
    
    echo ""
}

# Function to generate JSON report
generate_json_report() {
    echo "{" > "$RESULTS_FILE"
    echo "  \"timestamp\": \"$TIMESTAMP\"," >> "$RESULTS_FILE"
    echo "  \"summary\": {" >> "$RESULTS_FILE"
    echo "    \"total_tests\": ${#test_modules[@]}," >> "$RESULTS_FILE"
    echo "    \"passed\": $(printf '%s\n' "${test_results[@]}" | grep -c "SUCCESS" || true)," >> "$RESULTS_FILE"
    echo "    \"failed\": $(printf '%s\n' "${test_results[@]}" | grep -c "FAILURE" || true)" >> "$RESULTS_FILE"
    echo "  }," >> "$RESULTS_FILE"
    echo "  \"tests\": [" >> "$RESULTS_FILE"
    
    local first=true
    for module in "${test_modules[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$RESULTS_FILE"
        fi
        
        echo "    {" >> "$RESULTS_FILE"
        echo "      \"module\": \"$module\"," >> "$RESULTS_FILE"
        echo "      \"result\": \"${test_results[$module]}\"," >> "$RESULTS_FILE"
        echo "      \"details\": \"${test_details[$module]}\"," >> "$RESULTS_FILE"
        echo "      \"metrics\": \"${test_metrics[$module]}\"," >> "$RESULTS_FILE"
        echo "      \"execution_time\": \"${test_execution_times[$module]}s\"" >> "$RESULTS_FILE"
        echo "    }" >> "$RESULTS_FILE"
    done
    
    echo "  ]" >> "$RESULTS_FILE"
    echo "}" >> "$RESULTS_FILE"
}

# Function to generate summary report
generate_summary_report() {
    {
        echo "Pathfinding-labs Test Results Summary"
        echo "===================================="
        echo "Timestamp: $TIMESTAMP"
        echo ""
        
        local total_tests=${#test_modules[@]}
        local passed=$(printf '%s\n' "${test_results[@]}" | grep -c "SUCCESS" || true)
        local failed=$(printf '%s\n' "${test_results[@]}" | grep -c "FAILURE" || true)
        
        echo "Overall Results:"
        echo "  Total Tests: $total_tests"
        echo "  Passed: $passed"
        echo "  Failed: $failed"
        echo "  Success Rate: $(( passed * 100 / total_tests ))%"
        echo ""
        
        echo "Individual Test Results:"
        echo "-----------------------"
        for module in "${test_modules[@]}"; do
            local status="${test_results[$module]}"
            local time="${test_execution_times[$module]}s"
            local details="${test_details[$module]}"
            
            if [ "$status" = "SUCCESS" ]; then
                echo "✓ $module ($time) - $details"
            else
                echo "✗ $module ($time) - $details"
            fi
        done
        
        echo ""
        echo "Detailed logs for failed tests are available in: $TEST_RESULTS_DIR/"
    } > "$SUMMARY_FILE"
}

# Main execution
echo -e "${BLUE}Starting test execution...${NC}"
echo ""

# Run all tests
for module in "${test_modules[@]}"; do
    run_test "$module"
done

# Generate reports
echo -e "${BLUE}Generating reports...${NC}"
generate_json_report
generate_summary_report

# Display summary
echo -e "${BLUE}=== Test Execution Complete ===${NC}"
echo ""

# Show summary
cat "$SUMMARY_FILE"

echo ""
echo -e "${GREEN}Reports generated:${NC}"
echo "  JSON Report: $RESULTS_FILE"
echo "  Summary Report: $SUMMARY_FILE"
echo "  Detailed logs: $TEST_RESULTS_DIR/"

# Exit with appropriate code
failed_count=$(printf '%s\n' "${test_results[@]}" | grep -c "FAILURE" || true)
if [ "$failed_count" -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}$failed_count test(s) failed.${NC}"
    exit 1
fi
