# Migration Comparison: Old Paths vs New Scenarios

## Summary

This document compares the old `modules/paths/` structure with the new `modules/scenarios/` structure to identify what has been migrated and what hasn't.

## ✅ Migrated Scenarios

### Prod One-Hop to Admin (4 scenarios)
| Old Path | New Scenario | Status |
|----------|-------------|---------|
| `modules/paths/to-admin/prod/prod_self_privesc_putRolePolicy` | `modules/scenarios/prod/one-hop/to-admin/iam-putrolepolicy` | ✅ Migrated |
| `modules/paths/to-admin/prod/prod_self_privesc_attachRolePolicy` | `modules/scenarios/prod/one-hop/to-admin/iam-attachrolepolicy` | ✅ Migrated |
| `modules/paths/to-admin/prod/prod_self_privesc_createPolicyVersion` | `modules/scenarios/prod/one-hop/to-admin/iam-createpolicyversion` | ✅ Migrated |
| `modules/paths/to-admin/dev/dev__user_has_createAccessKey_to_admin` | `modules/scenarios/prod/one-hop/to-admin/iam-createaccesskey` | ✅ Migrated (moved from dev to prod) |

### Prod Multi-Hop to Admin (2 scenarios)
| Old Path | New Scenario | Status |
|----------|-------------|---------|
| `modules/paths/to-admin/prod/prod_role_with_multiple_privesc_paths` | `modules/scenarios/prod/multi-hop/to-admin/multiple-paths-combined` | ✅ Migrated |
| `modules/paths/to-admin/prod/prod_role_has_putrolepolicy_on_non_admin_role` | `modules/scenarios/prod/multi-hop/to-admin/putrolepolicy-on-other` | ✅ Migrated |

### Prod One-Hop to Bucket (5 scenarios)
| Old Path | New Scenario | Status |
|----------|-------------|---------|
| N/A - New | `modules/scenarios/prod/one-hop/to-bucket/iam-putrolepolicy` | ✅ Created New |
| N/A - New | `modules/scenarios/prod/one-hop/to-bucket/iam-attachrolepolicy` | ✅ Created New |
| N/A - New | `modules/scenarios/prod/one-hop/to-bucket/iam-createaccesskey` | ✅ Created New |
| N/A - New | `modules/scenarios/prod/one-hop/to-bucket/iam-updateassumerolepolicy` | ✅ Created New |
| N/A - New | `modules/scenarios/prod/one-hop/to-bucket/iam-assumerole` | ✅ Created New |

### Prod Multi-Hop to Bucket (3 scenarios)
| Old Path | New Scenario | Status |
|----------|-------------|---------|
| `modules/paths/to-bucket/prod/prod_role_has_access_to_bucket_through_resource_policy` | `modules/scenarios/prod/multi-hop/to-bucket/resource-policy-bypass` | ✅ Migrated |
| `modules/paths/to-bucket/prod/prod_role_has_exclusive_access_to_bucket_through_resource_policy` | `modules/scenarios/prod/multi-hop/to-bucket/exclusive-resource-policy` | ✅ Migrated |
| `modules/paths/to-bucket/prod/prod_simple_explicit_role_assumption_chain` | `modules/scenarios/prod/multi-hop/to-bucket/role-chain-to-s3` | ✅ Migrated |

### Toxic Combo (1 scenario)
| Old Path | New Scenario | Status |
|----------|-------------|---------|
| `modules/paths/to-admin/dev/dev_lambda_admin` | `modules/scenarios/prod/toxic-combo/public-lambda-with-admin` | ✅ Migrated (moved from dev to prod) |

### Cross-Account Dev-to-Prod (4 scenarios)
| Old Path | New Scenario | Status |
|----------|-------------|---------|
| `modules/paths/to-bucket/x-account/x-account-from-dev-to-prod-role-assumption-s3-access` | `modules/scenarios/cross-account/dev-to-prod/one-hop/simple-role-assumption` | ✅ Migrated |
| `modules/paths/to-admin/x-account/x-account-from-dev-to-prod-invoke-and-update-on-prod-lambda` | `modules/scenarios/cross-account/dev-to-prod/multi-hop/lambda-invoke-update` | ✅ Migrated |
| `modules/paths/to-admin/x-account/x-account-from-dev-to-prod-multi-hop-privesc-both-sides` | `modules/scenarios/cross-account/dev-to-prod/multi-hop/multi-hop-both-sides` | ✅ Migrated |
| `modules/paths/to-admin/x-account/x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin` | `modules/scenarios/cross-account/dev-to-prod/multi-hop/passrole-lambda-admin` | ✅ Migrated |

### Cross-Account Ops-to-Prod (1 scenario)
| Old Path | New Scenario | Status |
|----------|-------------|---------|
| `modules/paths/to-admin/x-account/x-account-from-operations-to-prod-simple-role-assumption` | `modules/scenarios/cross-account/ops-to-prod/one-hop/simple-role-assumption` | ✅ Migrated |

## ❌ Not Yet Ported

**All scenarios have been migrated!** There are no unmigrated scenarios from the old structure.

## Statistics

- **Total Old Scenarios**: 15
- **Migrated**: 15 (100%)
- **New Scenarios Created**: 5 (one-hop to-bucket scenarios)
- **Total Scenarios in New Structure**: 20

## Notes

1. **Dev scenarios moved to Prod**: Following the new architecture where single-account scenarios live in prod, we moved:
   - `dev__user_has_createAccessKey_to_admin` → `prod/one-hop/to-admin/iam-createaccesskey`
   - `dev_lambda_admin` → `prod/toxic-combo/public-lambda-with-admin`

2. **All scenarios are now optional**: Every scenario can be enabled/disabled via boolean flags in `terraform.tfvars`

3. **New taxonomy applied**: 
   - One-hop = Single privilege escalation step (one principal to another)
   - Multi-hop = Multiple privilege escalation steps (multiple principals)
   - Toxic-combo = Attack paths with multiple vulnerabilities/conditions

4. **Old structure preserved**: The old `modules/paths/` directory still exists but is no longer referenced in `main.tf`

