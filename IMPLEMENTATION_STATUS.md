# Pathfinder Labs Restructure - Implementation Status

## Overview

The Pathfinder Labs project has been successfully restructured from a cross-account privilege escalation demo into a comprehensive CSPM validation platform with modular, granular control over individual security scenarios.

## Completed Tasks

### ✅ Phase 1: New Directory Structure
- Created `environments/` directory for base infrastructure (always deployed)
- Created `modules/scenarios/` directory with organized taxonomy:
  - `prod/one-hop/` - Single principal traversal scenarios
  - `prod/multi-hop/` - Multiple principal traversal scenarios  
  - `prod/toxic-combo/` - Multiple vulnerable condition scenarios
  - `cross-account/` - Multi-account scenarios

### ✅ Phase 2: Environment Migration
- Moved `modules/environments/prod/` → `environments/prod/`
- Moved `modules/environments/dev/` → `environments/dev/`
- Moved `modules/environments/operations/` → `environments/ops/`
- All base resources remain intact (starting users, admin users, groups, etc.)

### ✅ Phase 3: Scenario Migration
All existing scenarios have been migrated to the new taxonomy:

**Prod One-Hop to Admin:**
- ✅ `iam-putrolepolicy` (from prod_self_privesc_putRolePolicy)
- ✅ `iam-attachrolepolicy` (from prod_self_privesc_attachRolePolicy)
- ✅ `iam-createpolicyversion` (from prod_self_privesc_createPolicyVersion)
- ✅ `iam-createaccesskey` (from dev__user_has_createAccessKey_to_admin - moved to prod)

**Prod Multi-Hop to Admin:**
- ✅ `putrolepolicy-on-other` (from prod_role_has_putrolepolicy_on_non_admin_role)
- ✅ `multiple-paths-combined` (from prod_role_with_multiple_privesc_paths)

**Prod Multi-Hop to Bucket:**
- ✅ `role-chain-to-s3` (from prod_simple_explicit_role_assumption_chain)
- ✅ `resource-policy-bypass` (from prod_role_has_access_to_bucket_through_resource_policy)
- ✅ `exclusive-resource-policy` (from prod_role_has_exclusive_access_to_bucket_through_resource_policy)

**Prod Toxic-Combo:**
- ✅ `public-lambda-with-admin` (from dev_lambda_admin)

**Cross-Account Dev-to-Prod:**
- ✅ `one-hop/simple-role-assumption` (from x-account-from-dev-to-prod-role-assumption-s3-access)
- ✅ `multi-hop/passrole-lambda-admin` (from x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin)
- ✅ `multi-hop/multi-hop-both-sides` (from x-account-from-dev-to-prod-multi-hop-privesc-both-sides)
- ✅ `multi-hop/lambda-invoke-update` (from x-account-from-dev-to-prod-invoke-and-update-on-prod-lambda)

**Cross-Account Ops-to-Prod:**
- ✅ `one-hop/simple-role-assumption` (from x-account-from-operations-to-prod-simple-role-assumption)

### ✅ Phase 4: New One-Hop to-Bucket Scenarios
Created 5 new IAM privilege escalation paths targeting S3 bucket access:
- ✅ `iam-putrolepolicy` - Modify role policy to gain bucket access
- ✅ `iam-attachrolepolicy` - Attach managed policy to gain bucket access
- ✅ `iam-createaccesskey` - Create access keys for privileged user (user-based)
- ✅ `iam-updateassumerolepolicy` - Modify role trust policy to assume it
- ✅ `iam-assumerole` - Simple role assumption to bucket access

### ✅ Phase 5: Root Configuration Update
- ✅ Rewrote `main.tf` with conditional module instantiation using `count`
- ✅ Created comprehensive `variables.tf` with boolean flags for each scenario
- ✅ Created `terraform.tfvars.example` showing how to enable/disable scenarios
- ✅ Backed up original files (`main.tf.backup`, `variables.tf.backup`)

## New Architecture Benefits

### ✅ Single Account Support
Users can now deploy with just a prod account. Dev and ops accounts are only needed for cross-account scenarios.

### ✅ Granular Control
Each scenario can be enabled/disabled independently via boolean variables in `terraform.tfvars`.

### ✅ Clear Taxonomy
- **one-hop**: Single principal traversal (one action or multiple actions, but one principal jump)
- **multi-hop**: Multiple principal traversals (chaining 2+ one-hop paths)
- **toxic-combo**: Multiple vulnerable conditions creating high severity

### ✅ Modular & Extensible
Easy to add new scenarios without restructuring. Each scenario follows a standard pattern:
```
scenario-name/
├── main.tf
├── variables.tf
├── outputs.tf
├── demo_attack.sh
├── cleanup_attack.sh
└── README.md
```

### ✅ CLI/Web Interface Ready
Boolean-based approach makes it trivial to build a CLI or web interface:
```bash
pl scenario enable prod/one-hop/to-admin/iam-putrolepolicy
pl scenario disable prod/one-hop/to-admin/iam-putrolepolicy
pl scenario list
```

## File Structure

```
pathfinder-labs/
├── environments/          # Base infrastructure (always deployed)
│   ├── prod/
│   ├── dev/
│   └── ops/
├── modules/
│   ├── scenarios/         # All security scenarios
│   │   ├── prod/
│   │   │   ├── one-hop/
│   │   │   ├── multi-hop/
│   │   │   └── toxic-combo/
│   │   └── cross-account/
│   │       ├── dev-to-prod/
│   │       └── ops-to-prod/
│   └── paths/            # OLD structure (kept for reference)
├── main.tf               # NEW: Conditional module orchestration
├── variables.tf          # NEW: Boolean flags for each scenario
├── terraform.tfvars.example
├── RESTRUCTURE_PLAN.md   # Original plan document
└── IMPLEMENTATION_STATUS.md  # This file
```

## How to Use

### 1. Configure Accounts
Edit `terraform.tfvars`:
```hcl
prod_account_id       = "111111111111"
dev_account_id        = "222222222222"  # Optional for cross-account
operations_account_id = "333333333333"  # Optional for cross-account
```

### 2. Enable Scenarios
Set desired scenarios to `true` in `terraform.tfvars`:
```hcl
# Enable a simple one-hop scenario
enable_prod_one_hop_to_bucket_iam_assumerole = true

# Enable a cross-account scenario
enable_cross_account_dev_to_prod_one_hop_simple_role_assumption = true
```

### 3. Deploy
```bash
terraform init
terraform plan
terraform apply
```

### 4. Test
Run demo scripts from individual scenario directories:
```bash
cd modules/scenarios/prod/one-hop/to-bucket/iam-assumerole
./demo_attack.sh
./cleanup_attack.sh
```

## Remaining Tasks

### Testing
- 🔄 Test `terraform plan` with single account (prod only)
- 🔄 Test `terraform plan` with multi-account (all three)
- 🔄 Validate all migrated scenarios work correctly
- 🔄 Update testing framework to work with new paths

### Documentation
- 🔄 Update main README.md with new taxonomy explanation
- 🔄 Create migration guide for existing users
- 🔄 Update AGENTS.md with new structure guidelines

### Demo Scripts
- 🔄 Update demo scripts in migrated scenarios to use new resource names
- 🔄 Create demo scripts for new one-hop to-bucket scenarios

## Breaking Changes

### For Existing Users
1. **main.tf structure changed**: Old module calls are replaced with conditional instantiation
2. **variables.tf structure changed**: New boolean variables added for each scenario
3. **Module paths changed**: Scenarios moved from `modules/paths/` to `modules/scenarios/`
4. **Environment modules moved**: From `modules/environments/` to `environments/`

### Migration Path for Existing Deployments
**WARNING**: This is a breaking change. You cannot simply update and run `terraform apply`.

**Recommended approach:**
1. Backup your current `terraform.tfstate`
2. Destroy existing resources: `terraform destroy`
3. Update to new structure
4. Configure scenarios in `terraform.tfvars`
5. Deploy fresh: `terraform init && terraform apply`

**Alternative (Advanced):**
Use `terraform state mv` commands to migrate state, but this is complex and error-prone.

## Future Enhancements

### Additional Scenarios (Planned)
Based on iam-vulnerable, we can add 20+ more discrete IAM privesc paths:
- `iam-setdefaultpolicyversion`
- `iam-addusertogroup`
- `iam-attachuserpolicy`
- `iam-putuserpolicy`
- `iam-putgrouppolicy`
- `iam-createloginprofile`
- `iam-updateloginprofile`
- `iam-passrole-lambda`
- `iam-passrole-ec2`
- `iam-passrole-glue`
- `iam-passrole-cloudformation`
- `iam-passrole-sagemaker`
- SSM-based paths

### CLI Tool
Build a Go binary to manage scenarios:
```bash
pl account add --profile prod --account-id 111111111111
pl scenario list
pl scenario enable prod/one-hop/to-admin/iam-putrolepolicy
pl scenario status
pl deploy
```

### Web Interface
Create a web UI for visual scenario management and attack path visualization.

### Metadata System
Add `metadata.json` to each scenario with:
- CSPM tool mappings (Prowler, ScoutSuite, CloudFox, etc.)
- MITRE ATT&CK techniques
- CWE/CVE references
- Difficulty level
- Cost estimate

## Summary

✅ **Restructure Complete**: All major components successfully migrated  
✅ **Architecture Sound**: Modular, extensible, and ready for CLI/web interfaces  
✅ **Backward Compatible Approach**: Old structure preserved in `modules/paths/` for reference  
✅ **Ready for Testing**: Structure is complete, awaiting validation testing  
🔄 **Documentation In Progress**: Need to update README and testing framework  

The project is now positioned as a comprehensive CSPM validation platform that can grow to include hundreds of discrete security scenarios, all manageable through simple boolean flags or future programmatic interfaces.

