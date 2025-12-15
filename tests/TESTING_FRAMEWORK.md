# Pathfinding-labs Testing Framework

This testing framework provides automated testing capabilities for all Pathfinding-labs privilege escalation modules.

## Overview

The framework uses standardized output parsing to determine test success/failure and generate comprehensive reports.

## Standardized Output Format

Each demo script outputs standardized test results in the following format:

```
TEST_RESULT:MODULE_NAME:SUCCESS|FAILURE
TEST_DETAILS:MODULE_NAME:Description of what was tested
TEST_METRICS:MODULE_NAME:key=value,key2=value2
```

## Available Scripts

### 1. `tests/run_all_tests.sh` - Run All Tests
Runs all available demo scripts and generates comprehensive reports.

```bash
cd tests
./run_all_tests.sh
```

**Features:**
- Runs all 6 privilege escalation modules
- 5-minute timeout per test
- Generates JSON and text reports
- Saves detailed logs for failed tests
- Returns appropriate exit codes

**Output:**
- `test_results/TEST_RESULTS_TIMESTAMP.json` - Machine-readable results
- `test_results/test_summary_TIMESTAMP.txt` - Human-readable summary
- `test_results/MODULE_failure_TIMESTAMP.log` - Detailed logs for failures

### 2. `tests/test_single_module.sh` - Test Single Module
Runs a specific module and shows detailed results.

```bash
cd tests
./test_single_module.sh <module_name>
```

**Example:**
```bash
cd tests
./test_single_module.sh prod_self_privesc_putRolePolicy
```

**Available modules:**
- `to-admin/prod/prod_self_privesc_putRolePolicy`
- `to-admin/prod/prod_self_privesc_attachRolePolicy`
- `to-admin/prod/prod_self_privesc_createPolicyVersion`
- `to-admin/prod/prod_role_with_multiple_privesc_paths`
- `to-bucket/prod/prod_simple_explicit_role_assumption_chain`
- `to-admin/prod/prod_role_has_putrolepolicy_on_non_admin_role`
- `to-bucket/x-account/x-account-from-dev-to-prod-role-assumption-s3-access`

### 3. `tests/update_demo_scripts.sh` - Update Scripts
Adds standardized output format to demo scripts (already run).

```bash
cd tests
./update_demo_scripts.sh
```

## Test Results

### Success Example
```
✓ prod_self_privesc_putRolePolicy: SUCCESS (15s)
  Details: Successfully escalated privileges using PutRolePolicy to attach admin policy
  Metrics: policy_attached=true,admin_access_gained=true,cleanup_completed=true,execution_time=15s
```

### Failure Example
```
✗ prod_role_with_multiple_privesc_paths: FAILURE (45s)
  Details: Script failed with exit code 1. Successfully demonstrated EC2, Lambda, and CloudFormation privilege escalation paths
  Metrics: execution_time=45s
```

## JSON Report Format

```json
{
  "timestamp": "20240909_143022",
  "summary": {
    "total_tests": 6,
    "passed": 5,
    "failed": 1
  },
  "tests": [
    {
      "module": "prod_self_privesc_putRolePolicy",
      "result": "SUCCESS",
      "details": "Successfully escalated privileges using PutRolePolicy to attach admin policy",
      "metrics": "policy_attached=true,admin_access_gained=true,cleanup_completed=true,execution_time=15s",
      "execution_time": "15s"
    }
  ]
}
```

## Integration with CI/CD

The test harness returns appropriate exit codes:
- `0` - All tests passed
- `1` - One or more tests failed

This makes it suitable for CI/CD pipelines:

```bash
# In your CI pipeline
cd tests
if ./run_all_tests.sh; then
    echo "All tests passed!"
else
    echo "Some tests failed. Check the reports."
    exit 1
fi
```

## Troubleshooting

### Test Timeout
If a test times out (5 minutes), check:
1. AWS credentials are properly configured
2. Required AWS profiles exist
3. Network connectivity to AWS

### Permission Errors
Ensure your AWS profiles have the necessary permissions for the modules being tested.

### Module Not Found
Verify the module exists in the `../modules/` directory and has a `demo_attack.sh` script.

## Adding New Modules

To add a new module to the testing framework:

1. Create the module in `modules/MODULE_NAME/`
2. Add a `demo_attack.sh` script with standardized output
3. Add the module name to the `test_modules` array in `tests/run_all_tests.sh`

## Standardized Output Requirements

Each demo script must output:

1. **TEST_RESULT**: Final success/failure status
2. **TEST_DETAILS**: Human-readable description
3. **TEST_METRICS**: Key-value pairs of test metrics

Example:
```bash
echo "TEST_RESULT:my_module:SUCCESS"
echo "TEST_DETAILS:my_module:Successfully demonstrated privilege escalation"
echo "TEST_METRICS:my_module:escalation_method=role_assumption,admin_access_gained=true"
```
