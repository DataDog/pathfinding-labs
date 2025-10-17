# Pathfinder Labs CSPM Architecture Restructure

## Vision

Transform Pathfinder Labs from a cross-account privilege escalation demo into a comprehensive CSPM validation platform - essentially "Stratus Red Team for Cloud Security Posture Management." The architecture supports granular enable/disable of individual security scenarios through a single Terraform state with boolean variables.

## New Directory Structure

```
pathfinder-labs/
├── cli/                              # Future: Go binary for scenario management
├── environments/                     # Base infrastructure (always deployed)
│   ├── prod/
│   │   ├── main.tf                   # pl-pathfinder-starting-user-prod + admin users
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   ├── dev/
│   │   ├── main.tf                   # pl-pathfinder-starting-user-dev (for x-account only)
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   ├── ops/
│   │   ├── main.tf                   # pl-pathfinder-starting-user-operations (for x-account only)
│   │   ├── variables.tf
│   │   ├── outputs.tf
├── modules/
│   ├── scenarios/
│   │   ├── prod/                     # PRIMARY: All single-account scenarios
│   │   │   ├── one-hop/              # Single principal traversal
│   │   │   │   ├── to-admin/
│   │   │   │   │   ├── iam-putrolepolicy/
│   │   │   │   │   ├── iam-attachrolepolicy/
│   │   │   │   │   ├── iam-createaccesskey/
│   │   │   │   │   ├── iam-passrole-lambda/          # PassRole + Lambda create/invoke
│   │   │   │   │   ├── iam-passrole-ec2/             # PassRole + EC2 RunInstances
│   │   │   │   │   └── [... more IAM techniques]
│   │   │   │   ├── to-bucket/
│   │   │   │   │   ├── iam-putrolepolicy/
│   │   │   │   │   ├── iam-attachrolepolicy/
│   │   │   │   │   ├── iam-createaccesskey/
│   │   │   │   │   └── [... same IAM techniques leading to S3 bucket]
│   │   │   ├── multi-hop/            # Multiple principal traversals
│   │   │   │   ├── to-admin/
│   │   │   │   │   ├── role-chain-3-hop/
│   │   │   │   │   ├── putrolepolicy-on-other/
│   │   │   │   │   ├── multiple-paths-combined/
│   │   │   │   ├── to-bucket/
│   │   │   │   │   ├── role-chain-to-s3/
│   │   │   │   │   ├── resource-policy-bypass/
│   │   │   │   │   ├── exclusive-resource-policy/
│   │   │   ├── toxic-combo/          # Multiple vulnerable conditions
│   │   │   │   ├── public-lambda-with-admin/
│   │   │   │   ├── public-ec2-with-admin/
│   │   │   │   ├── exposed-s3-with-secrets/
│   │   ├── cross-account/            # Multi-account scenarios (dev & ops used here)
│   │   │   ├── dev-to-prod/
│   │   │   │   ├── one-hop/
│   │   │   │   │   ├── simple-role-assumption/
│   │   │   │   ├── multi-hop/
│   │   │   │   │   ├── passrole-lambda-admin/
│   │   │   │   │   ├── multi-hop-both-sides/
│   │   │   │   │   ├── lambda-invoke-update/
│   │   │   ├── ops-to-prod/
│   │   │   │   ├── one-hop/
│   │   │   │   │   ├── simple-role-assumption/
├── main.tf                           # Root orchestrator - calls all modules with conditionals
├── variables.tf                      # Boolean variable for EACH scenario
├── terraform.tfvars                  # User configuration - enable/disable scenarios
├── outputs.tf                        # Aggregate outputs from all enabled scenarios
└── tests/                            # Existing testing framework (update paths)
```

## Key Architectural Decisions

### 1. Taxonomy Clarification

**one-hop/** - Single principal traversal (regardless of action complexity)
- Examples: 
  - Simple: `iam:PutRolePolicy` (one action)
  - Complex: `iam:PassRole` + `lambda:CreateFunction` + `lambda:InvokeFunction` (multiple actions)
  - Complex: `iam:PassRole` + `ec2:RunInstances` (multiple actions)
- Pattern: Starting principal → [one or more IAM actions] → ONE target principal with admin/bucket access
- Key: You go from Principal A to Principal B (or A to Target Resource directly)
- Both role-based and user-based scenarios

**multi-hop/** - Multiple principal traversals (chaining multiple one-hop paths)
- Examples: 
  - User1 → [iam:PassRole + lambda:CreateFunction + lambda:InvokeFunction] → Role2 → [sts:AssumeRole] → Role3 → Admin
  - User1 → [iam:PutRolePolicy] → Role2 → [sts:AssumeRole] → Role3 → Bucket
  - Role A → [sts:AssumeRole] → Role B → [sts:AssumeRole] → Role C → Admin
- Pattern: Multiple principal traversals, chaining together 2+ one-hop paths
- Key: You traverse through 2 or more intermediate principals before reaching target
- Can be intra-account or cross-account

**toxic-combo/** - Multiple vulnerable conditions combined
- Examples: Public Lambda + Admin Role, Public EC2 + Admin + CVE, Exposed Secrets in Public S3
- Pattern: Multiple security misconfigurations that amplify risk
- Focus on CSPM detection scenarios

### 2. Account Usage Strategy

**Prod Account** - Primary account for single-account scenarios
- All one-hop scenarios (to-admin and to-bucket)
- All intra-account multi-hop scenarios
- All toxic-combo scenarios
- Users with only one AWS account can use just prod

**Dev/Ops Accounts** - Reserved for cross-account scenarios only
- Cross-account one-hop paths (dev-to-prod, ops-to-prod)
- Cross-account multi-hop paths
- No standalone single-account scenarios in dev/ops

### 3. Module Structure Pattern

Each scenario module follows this standard:

```
scenario-name/
├── main.tf              # Resources for this scenario (uses provider alias)
├── variables.tf         # Required: account_id, resource_suffix, environment
├── outputs.tf           # Credentials, ARNs, attack path info
├── demo_attack.sh       # Demonstrates the attack path
├── cleanup_attack.sh    # Reverts demo changes
├── README.md            # Documentation with mermaid diagram
└── metadata.json        # Future: CSPM mappings, MITRE ATT&CK, etc.
```

### 4. Boolean Variable Convention

```hcl
# variables.tf
variable "enable_prod_one_hop_to_admin_iam_putrolepolicy" {
  description = "Enable: prod → one-hop → to-admin → iam-putrolepolicy"
  type        = bool
  default     = false
}

variable "enable_prod_one_hop_to_admin_iam_passrole_lambda" {
  description = "Enable: prod → one-hop → to-admin → iam-passrole-lambda"
  type        = bool
  default     = false
}

variable "enable_prod_multi_hop_to_bucket_role_chain_to_s3" {
  description = "Enable: prod → multi-hop → to-bucket → role-chain-to-s3"
  type        = bool
  default     = false
}

variable "enable_cross_account_dev_to_prod_multi_hop_passrole_lambda_admin" {
  description = "Enable: cross-account → dev-to-prod → multi-hop → passrole-lambda-admin"
  type        = bool
  default     = false
}
```

### 5. Root main.tf Orchestration

```hcl
# Always deploy base environments
module "prod_environment" {
  source = "./environments/prod"
  ...
}

module "dev_environment" {
  source = "./environments/dev"
  ...
}

module "ops_environment" {
  source = "./environments/ops"
  ...
}

# Conditional scenario modules
module "prod_one_hop_to_admin_iam_putrolepolicy" {
  count  = var.enable_prod_one_hop_to_admin_iam_putrolepolicy ? 1 : 0
  source = "./modules/scenarios/prod/one-hop/to-admin/iam-putrolepolicy"
  
  providers = {
    aws = aws.prod
  }
  
  account_id       = var.prod_account_id
  environment      = "prod"
  resource_suffix  = random_string.resource_suffix.result
}

# Cross-account scenario with multiple providers
module "cross_account_dev_to_prod_multi_hop_passrole_lambda_admin" {
  count  = var.enable_cross_account_dev_to_prod_multi_hop_passrole_lambda_admin ? 1 : 0
  source = "./modules/scenarios/cross-account/dev-to-prod/multi-hop/passrole-lambda-admin"
  
  providers = {
    aws.dev  = aws.dev
    aws.prod = aws.prod
  }
  
  dev_account_id        = var.dev_account_id
  prod_account_id       = var.prod_account_id
  operations_account_id = var.operations_account_id
  resource_suffix       = random_string.resource_suffix.result
}
```

## Migration Strategy

### Phase 1: Create New Structure
1. Create new directory structure under `modules/scenarios/`
2. Keep existing `modules/paths/` temporarily for reference
3. Create base environment modules under `environments/`

### Phase 2: Migrate Existing Modules

Map existing modules to new taxonomy:

**Prod One-Hop to Admin:**
- `prod_self_privesc_putRolePolicy` → `prod/one-hop/to-admin/iam-putrolepolicy`
- `prod_self_privesc_attachRolePolicy` → `prod/one-hop/to-admin/iam-attachrolepolicy`
- `prod_self_privesc_createPolicyVersion` → `prod/one-hop/to-admin/iam-createpolicyversion`

**Prod Multi-Hop to Admin:**
- `prod_role_has_putrolepolicy_on_non_admin_role` → `prod/multi-hop/to-admin/putrolepolicy-on-other`
- `prod_role_with_multiple_privesc_paths` → `prod/multi-hop/to-admin/multiple-paths-combined`

**Prod Multi-Hop to Bucket:**
- `prod_simple_explicit_role_assumption_chain` → `prod/multi-hop/to-bucket/role-chain-to-s3`
- `prod_role_has_access_to_bucket_through_resource_policy` → `prod/multi-hop/to-bucket/resource-policy-bypass`
- `prod_role_has_exclusive_access_to_bucket_through_resource_policy` → `prod/multi-hop/to-bucket/exclusive-resource-policy`

**Prod Toxic-Combo:**
- `dev_lambda_admin` → `prod/toxic-combo/public-lambda-with-admin`

**Cross-Account Dev-to-Prod:**
- `x-account-from-dev-to-prod-role-assumption-s3-access` → `cross-account/dev-to-prod/one-hop/simple-role-assumption`
- `x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin` → `cross-account/dev-to-prod/multi-hop/passrole-lambda-admin`
- `x-account-from-dev-to-prod-multi-hop-privesc-both-sides` → `cross-account/dev-to-prod/multi-hop/multi-hop-both-sides`
- `x-account-from-dev-to-prod-invoke-and-update-on-prod-lambda` → `cross-account/dev-to-prod/multi-hop/lambda-invoke-update`

**Cross-Account Ops-to-Prod:**
- `x-account-from-operations-to-prod-simple-role-assumption` → `cross-account/ops-to-prod/one-hop/simple-role-assumption`

**Note:** Former `dev__user_has_createAccessKey_to_admin` will be moved to prod account as `prod/one-hop/to-admin/iam-createaccesskey` since we're reserving dev/ops for cross-account only.

### Phase 3: Create New IAM-Vulnerable Style Modules

Implement discrete IAM privilege escalation paths for both admin and bucket destinations (all in prod account):

**Priority One-Hop Paths (5 initial for both to-admin and to-bucket):**
- `iam-putrolepolicy` (role-only)
- `iam-attachrolepolicy` (role-only)  
- `iam-createaccesskey` (user-only)
- `iam-updateassumerolepolicy` (role-only)
- `iam-assumerole` (simple role assumption)

**Future One-Hop Paths (from iam-vulnerable):**
- `iam-createpolicyversion`
- `iam-setdefaultpolicyversion`
- `iam-addusertogroup`
- `iam-attachuserpolicy`
- `iam-attachgrouppolicy`
- `iam-putuserpolicy`
- `iam-putgrouppolicy`
- `iam-createloginprofile`
- `iam-updateloginprofile`
- `iam-passrole-lambda` (PassRole + Lambda CreateFunction + InvokeFunction)
- `iam-passrole-ec2` (PassRole + EC2 RunInstances)
- `iam-passrole-glue` (PassRole + Glue CreateDevEndpoint)
- `iam-passrole-cloudformation` (PassRole + CloudFormation CreateStack)
- `iam-passrole-datapipeline` (PassRole + DataPipeline CreatePipeline)
- `iam-passrole-sagemaker` (PassRole + SageMaker variants)
- SSM variants (StartSession, SendCommand)

### Phase 4: Update Root Configuration

1. Create comprehensive `variables.tf` with boolean for each scenario
2. Rewrite `main.tf` to use conditional module instantiation
3. Create sample `terraform.tfvars.example` with all scenarios listed
4. Update `outputs.tf` to aggregate outputs from enabled scenarios

### Phase 5: Testing & Documentation

1. Update testing framework to work with new paths
2. Update README.md with new taxonomy
3. Create migration guide for existing users
4. Test single-account deployment (prod only)
5. Test multi-account deployment (all three)

## Future CLI Interface Support

The boolean-based approach naturally supports a CLI:

```go
// CLI would modify terraform.tfvars
func enableScenario(scenario string, account string) {
  // Parse scenario: "one-hop/to-admin/iam-putrolepolicy"
  // Set: enable_prod_one_hop_to_admin_iam_putrolepolicy = true
  // Run: terraform apply -auto-approve
}

func disableScenario(scenario string, account string) {
  // Set: enable_prod_one_hop_to_admin_iam_putrolepolicy = false
  // Run: terraform apply -auto-approve
}

func listScenarios() {
  // Parse variables.tf for all enable_* variables
  // Parse terraform.tfstate for deployed resources
  // Show enabled/disabled status
}
```

## Benefits of This Architecture

✅ **Single account support** - Users can deploy with just prod account
✅ **Granular control** - Enable/disable individual scenarios
✅ **CSPM validation** - Each scenario tests specific detections
✅ **Educational** - Clear taxonomy helps understand attack patterns
✅ **Extensible** - Easy to add new scenarios without restructuring
✅ **Backward compatible** - Existing test framework can be adapted
✅ **CLI ready** - Boolean variables are perfect for programmatic control
✅ **State management** - Single state file, easier to manage
✅ **Cost control** - Disable expensive scenarios easily

## Implementation Order

1. **Create directory structure** - Set up new folders
2. **Migrate environments** - Move base infrastructure to `environments/`
3. **Migrate one existing scenario** - Prove the pattern works
4. **Update root main.tf** - Add conditional orchestration
5. **Migrate remaining scenarios** - Batch migration
6. **Create 5 new one-hop paths** - Both to-admin and to-bucket versions (in prod)
7. **Update documentation** - README, AGENTS.md, new taxonomy guide
8. **Update testing framework** - Adapt to new paths
9. **Validate deployment** - Single-account and multi-account tests

## Implementation Checklist

- [ ] Create new directory structure: environments/ and modules/scenarios/ with all subdirectories
- [ ] Move environment modules to environments/ keeping existing resources
- [ ] Create a template scenario module with standard structure
- [ ] Migrate one existing scenario as proof of concept (prod_self_privesc_putRolePolicy → prod/one-hop/to-admin/iam-putrolepolicy)
- [ ] Rewrite root main.tf with conditional module instantiation pattern
- [ ] Create variables.tf with boolean enable flags for all scenarios
- [ ] Migrate all existing prod scenarios to new taxonomy structure
- [ ] Migrate all existing cross-account scenarios to new structure
- [ ] Move dev__user_has_createAccessKey_to_admin to prod/one-hop/to-admin/iam-createaccesskey
- [ ] Create 5 new one-hop to-bucket IAM privilege escalation scenarios in prod
- [ ] Create additional one-hop to-admin IAM scenarios in prod
- [ ] Update README.md with new taxonomy, single-account focus, migration guide
- [ ] Adapt testing framework to work with new scenario paths
- [ ] Test single-account (prod only) and multi-account deployments

