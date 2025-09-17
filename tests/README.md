# Pathfinder-labs Testing Framework

This directory contains the testing framework for Pathfinder-labs privilege escalation modules.

## Quick Start

```bash
# Run all tests
./run_all_tests.sh

# Test a single module
./test_single_module.sh prod_self_privesc_putRolePolicy

# Run all cleanups
./run_all_cleanups.sh

# List available modules
./test_single_module.sh
```

## Files

- `run_all_tests.sh` - Run all available demo scripts and generate reports
- `test_single_module.sh` - Test a specific module with detailed output
- `run_all_cleanups.sh` - Run all cleanup scripts and generate reports
- `update_demo_scripts.sh` - Add standardized output format to demo scripts
- `TESTING_FRAMEWORK.md` - Complete documentation

## Output

- Test results are saved to the `test_results/` directory with timestamps
- Cleanup results are saved to the `cleanup_results/` directory with timestamps

For complete documentation, see `TESTING_FRAMEWORK.md`.
