# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Pathfinding Labs** is a modular platform for deploying intentionally vulnerable AWS configurations to validate Cloud Security Posture Management (CSPM) tools and train security teams. Think of it as "Stratus Red Team for CSPM validation."

### Purpose
- **Validate CSPM Detection**: Does your security tooling detect all vulnerable configurations?
- **Train Security Teams**: Provide hands-on experience with real attack scenarios
- **Answer Critical Questions**: Who has access to my most sensitive S3 bucket? If an attacker compromises one employee, what's the likelihood they reach critical resources?
- **Measure Coverage**: Identify gaps in security monitoring
- **Practice IAM Exploitation**: Sharpen privilege escalation skills with real scenarios
- **Build Attack Chains**: Learn complex multi-hop and cross-account techniques

### Key Features
- **Single-Account Support**: Works with just ONE AWS account (prod) for most scenarios
- **Multi-Account Support**: Optional dev/ops accounts for cross-account scenarios
- **Modular Architecture**: Enable/disable individual scenarios via boolean flags
- **Granular Control**: Each scenario is independently deployable
- **20 Scenarios Available**: Covering one-hop, multi-hop, toxic combinations, and cross-account paths

## Architecture

### Directory Structure

```
pathfinding-labs/
├── environments/              # Base infrastructure (always deployed)
│   ├── prod/                 # Production environment base resources
│   ├── dev/                  # Development environment base resources (optional)
│   └── operations/           # Operations environment base resources (optional)
│
├── modules/scenarios/        # Attack scenarios (opt-in via boolean flags)
│   ├── prod/                 # Single-account scenarios (PRIMARY)
│   │   ├── one-hop/
│   │   │   ├── to-admin/    # Single-step privilege escalation to admin
│   │   │   └── to-bucket/   # Single-step escalation to S3 access
│   │   ├── multi-hop/
│   │   │   ├── to-admin/    # Multi-step escalation to admin
│   │   │   └── to-bucket/   # Multi-step escalation to S3 access
│   │   └── toxic-combo/     # Multiple misconfigurations combined
│   ├── tool-testing/         # Edge cases for testing detection engines
│   └── cross-account/
│       ├── dev-to-prod/     # Dev → Prod attack paths
│       └── ops-to-prod/     # Ops → Prod attack paths
│
├── main.tf                   # Root module with conditional instantiation
├── variables.tf              # Boolean flags for each scenario
├── outputs.tf                # Credential outputs for testing
└── terraform.tfvars          # Your configuration (gitignored)
```

### Scenario Taxonomy

**One-Hop Privilege Escalation**
- Single principal traversal (regardless of action complexity)
- Pattern: `Principal A → [IAM actions] → Principal B (admin/bucket access)`
- Examples: `iam:PutRolePolicy`, `iam:PassRole + lambda:CreateFunction + lambda:InvokeFunction`
- Both role-based and user-based scenarios
- Deploy to: **prod account only**

**Multi-Hop Privilege Escalation**
- Multiple principal traversals (chaining 2+ one-hop paths)
- Pattern: `Principal A → Principal B → Principal C → Target`
- Examples: Role chains, multiple privilege escalation steps
- Deploy to: **prod account only** (for single-account) or **cross-account**

**Toxic Combinations**
- Multiple security misconfigurations that amplify risk
- Examples: Public Lambda + Admin Role, Public S3 + Sensitive Data
- Focus on CSPM detection scenarios
- Deploy to: **prod account only**

**Cross-Account Privilege Escalation**
- Privilege escalation paths spanning multiple AWS accounts
- Examples: Dev → Prod, Ops → Prod
- Deploy to: **dev/ops → prod accounts** (requires multi-account setup)

**Tool Testing**
- Edge cases and scenarios designed to test detection engine capabilities
- Not distinct escalation types, but scenarios to measure detection accuracy
- Examples: Resource policies that bypass IAM, complex policy conditions, false positive scenarios
- Can be single-account or cross-account, to-admin or to-bucket, one-hop or multi-hop
- Focus on testing CSPM and security tool detection rather than new attack techniques
- Deploy to: **prod account** (for single-account) or **cross-account**

### Account Usage Strategy

**Prod Account (PRIMARY)**
- All one-hop scenarios (to-admin and to-bucket)
- All single-account multi-hop scenarios
- All toxic-combo scenarios
- **Users with only ONE AWS account can use just prod!**

**Dev/Ops Accounts (OPTIONAL)**
- Reserved for cross-account scenarios only
- Cross-account one-hop and multi-hop paths
- Not required for single-account testing

### Multi-Account Provider Pattern

- All modules use provider aliases: `aws.dev`, `aws.prod`, `aws.operations`
- Resources must specify the correct provider to deploy to the right account
- Account IDs are passed as variables to all modules
- Conditional module instantiation based on boolean flags

## Common Commands

### Initial Setup (Single Account)

```bash
# 1. Clone the repository
git clone https://github.com/your-org/pathfinding-labs.git
cd pathfinding-labs

# 2. Copy and configure your settings
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your prod account ID and AWS profile

# 3. Enable specific scenarios (edit terraform.tfvars)
enable_prod_one_hop_to_admin_iam_putrolepolicy = true

# 4. Deploy
terraform init
terraform plan
terraform apply

# 5. Run demo scripts (credentials are automatically read from terraform outputs)
cd modules/scenarios/single-account/privesc-one-hop/to-admin/iam-createaccesskey
./demo_attack.sh
```

### Initial Setup (Multi-Account with Dev/Ops)

```bash
# Same as above, but configure all three accounts in terraform.tfvars:
prod_account_id        = "111111111111"
dev_account_id         = "222222222222"
operations_account_id  = "333333333333"

prod_account_aws_profile       = "my-prod-profile"
dev_account_aws_profile        = "my-dev-profile"
operations_account_aws_profile = "my-ops-profile"

# Enable cross-account scenarios
enable_cross_account_dev_to_prod_simple_role_assumption = true
```

### Running Attack Demonstrations

Each scenario includes demonstration scripts:

```bash
# Navigate to a specific scenario
cd modules/scenarios/single-account/privesc-one-hop/to-admin/iam-createaccesskey

# Run the demonstration
./demo_attack.sh

# Clean up attack artifacts (keeps infrastructure)
./cleanup_attack.sh
```

Demo scripts provide:
- Step-by-step exploitation walkthrough
- AWS CLI commands with explanations
- Real-time verification of privilege escalation
- Color-coded output for clarity
- **Automatic credential retrieval from Terraform outputs** (no AWS profile configuration needed)

### Development Workflow
```bash
# Validate Terraform configuration
terraform validate

# Format Terraform files
terraform fmt -recursive

# Show current state
terraform show

# List all resources
terraform state list
```

## Available Scenarios

### One-Hop to Admin (4 scenarios)
| Scenario | Attack Vector | Description |
|----------|---------------|-------------|
| `iam-putrolepolicy` | Self-modification | Role can modify its own inline policy |
| `iam-attachrolepolicy` | Self-modification | Role can attach managed policies to itself |
| `iam-createpolicyversion` | Policy versioning | Role can create new policy versions |
| `iam-createaccesskey` | Credential creation | Role can create access keys for admin user |

### One-Hop to Bucket (5 scenarios)
| Scenario | Attack Vector | Description |
|----------|---------------|-------------|
| `iam-putrolepolicy` | Self-modification | Role grants itself S3 bucket access |
| `iam-attachrolepolicy` | Self-modification | Role attaches S3 access policies |
| `iam-createaccesskey` | Credential creation | Create keys for user with bucket access |
| `iam-updateassumerolepolicy` | Trust policy modification | Modify trust to assume bucket-access roles |
| `sts-assumerole` | Direct assumption | Directly assume role with bucket permissions |

### Multi-Hop to Admin (2 scenarios)
| Scenario | Hops | Description |
|----------|------|-------------|
| `multiple-paths-combined` | 2-3 | EC2, Lambda, CloudFormation paths to admin |
| `putrolepolicy-on-other` | 2 | Modify another role's policy for admin access |

### Multi-Hop to Bucket (3 scenarios)
| Scenario | Hops | Description |
|----------|------|-------------|
| `resource-policy-bypass` | 2 | Access via resource policy bypassing IAM |
| `exclusive-resource-policy` | 2 | Exclusive bucket access via resource policy |
| `role-chain-to-s3` | 3 | Three-hop role assumption chain to S3 |

### Toxic Combo (1 scenario)
| Scenario | Risk Level | Description |
|----------|------------|-------------|
| `public-lambda-with-admin` | Critical | Public Lambda with administrative role |

### Tool Testing (2 scenarios)
| Scenario | Focus | Description |
|----------|-------|-------------|
| `resource-policy-bypass` | Edge case detection | Tests detection of resource policies that bypass IAM restrictions |
| `exclusive-resource-policy` | Policy parsing | Tests detection of exclusive resource policy configurations |

### Cross-Account (5 scenarios)
| Scenario | Type | Description |
|----------|------|-------------|
| `dev-to-prod/simple-role-assumption` | One-hop | Direct cross-account role assumption |
| `dev-to-prod/passrole-lambda-admin` | Multi-hop | PassRole escalation via Lambda |
| `dev-to-prod/multi-hop-both-sides` | Multi-hop | Escalation in both accounts |
| `dev-to-prod/lambda-invoke-update` | Multi-hop | Lambda code update for credential extraction |
| `ops-to-prod/simple-role-assumption` | One-hop | Ops to prod role assumption |

## Development Guidelines

### Adding New Scenario Modules

Each scenario module follows a standard structure:

```
scenario-name/
├── main.tf              # Terraform resources (uses provider alias)
├── variables.tf         # Required: account_id, resource_suffix, environment
├── outputs.tf           # Credentials, ARNs, attack path info
├── README.md            # Documentation with mermaid diagrams
├── demo_attack.sh       # Exploitation demonstration
└── cleanup_attack.sh    # Artifact cleanup script
```

### Adding a New Scenario (Step-by-Step)

1. **Create the scenario directory** under the appropriate path:
   - One-hop to admin: `modules/scenarios/single-account/privesc-one-hop/to-admin/scenario-name/`
   - One-hop to bucket: `modules/scenarios/single-account/privesc-one-hop/to-bucket/scenario-name/`
   - Multi-hop to admin: `modules/scenarios/single-account/privesc-multi-hop/to-admin/scenario-name/`
   - Multi-hop to bucket: `modules/scenarios/single-account/privesc-multi-hop/to-bucket/scenario-name/`
   - Toxic combo: `modules/scenarios/single-account/toxic-combo/scenario-name/`
   - Tool testing: `modules/scenarios/tool-testing/scenario-name/`
   - Cross-account: `modules/scenarios/cross-account/dev-to-prod/[one-hop|multi-hop]/scenario-name/`

2. **Implement Terraform resources** in `main.tf`:
   ```hcl
   # For single-account (prod) scenarios
   resource "aws_iam_role" "example" {
     provider = aws.prod
     name     = "pl-${var.scenario_name}-role"
     # ...
   }
   ```

3. **Add variables** in `variables.tf`:
   ```hcl
   variable "account_id" {
     description = "AWS Account ID"
     type        = string
   }

   variable "resource_suffix" {
     description = "Random suffix for globally unique resources"
     type        = string
   }

   variable "environment" {
     description = "Environment name (prod, dev, operations)"
     type        = string
     default     = "prod"
   }
   ```

4. **Add outputs** in `outputs.tf`:
   ```hcl
   output "starting_role_arn" {
     description = "ARN of the starting role for this attack path"
     value       = aws_iam_role.starting_role.arn
   }
   ```

5. **Create README.md** with:
   - Attack path description
   - Mermaid diagram showing the path
   - CSPM detection guidance
   - MITRE ATT&CK mapping

6. **Create demo_attack.sh** demonstrating the exploit

7. **Create cleanup_attack.sh** to revert demo changes

8. **Add boolean variable** to root `variables.tf`:
   ```hcl
   variable "enable_prod_one_hop_to_admin_scenario_name" {
     description = "Enable: prod → one-hop → to-admin → scenario-name"
     type        = bool
     default     = false
   }
   ```

9. **Add module instantiation** to root `main.tf`:
   ```hcl
   module "prod_one_hop_to_admin_scenario_name" {
     count  = var.enable_prod_one_hop_to_admin_scenario_name ? 1 : 0
     source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/scenario-name"

     providers = {
       aws = aws.prod
     }

     account_id       = var.prod_account_id
     environment      = "prod"
     resource_suffix  = random_string.resource_suffix.result
   }
   ```

10. **Add grouped output** to root `outputs.tf`:
   ```hcl
   output "single_account_privesc_one_hop_to_admin_scenario_name" {
     description = "All outputs for scenario-name one-hop to-admin scenario"
     value = var.enable_single_account_privesc_one_hop_to_admin_scenario_name ? {
       starting_user_name              = module.single_account_privesc_one_hop_to_admin_scenario_name[0].starting_user_name
       starting_user_arn               = module.single_account_privesc_one_hop_to_admin_scenario_name[0].starting_user_arn
       starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_scenario_name[0].starting_user_access_key_id
       starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_scenario_name[0].starting_user_secret_access_key
       attack_path                     = module.single_account_privesc_one_hop_to_admin_scenario_name[0].attack_path
     } : null
     sensitive = true
   }
   ```

11. **Update terraform.tfvars.example** with the new boolean flag

12. **Test thoroughly** in an isolated AWS account

### Demo Script Best Practices

Demo scripts should:
- Use color-coded output for clarity (red/green/yellow)
- Show step-by-step exploitation with explanations
- Verify privilege escalation actually works
- Include AWS CLI commands with comments
- **Read credentials from grouped Terraform outputs** using this pattern:
  ```bash
  cd ../../../../../..  # Navigate to project root
  MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_CATEGORY_SCENARIO.value // empty')
  ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
  SECRET_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
  cd - > /dev/null  # Return to scenario directory
  ```
- **Use 15-second waits** for IAM policy propagation (not 5 seconds)
- Clean up any temporary resources created during demo

### Cleanup Script Best Practices

Cleanup scripts should:
- **Use admin credentials from Terraform outputs** for cleanup operations:
  ```bash
  cd ../../../../../..  # Navigate to project root
  ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
  ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)
  export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
  export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
  unset AWS_SESSION_TOKEN
  cd - > /dev/null  # Return to scenario directory
  ```
- Remove attack artifacts (access keys, modified policies, etc.)
- **Preserve infrastructure** - cleanup scripts remove demo artifacts, not the terraform resources
- Provide clear feedback about what was cleaned up
- Use color-coded output to show cleanup progress

### Resource Naming Convention

All resources follow a consistent naming pattern:

- **Prefix**: `pl-` (Pathfinding Labs)
- **Format**: `pl-{resource-description}-{context}`
- **Examples**:
  - `pl-pathfinding-starting-user-prod`
  - `pl-cak-admin` (CreateAccessKey Admin)
  - `pl-prod-one-hop-putrolepolicy-role`

Globally unique resources (S3 buckets) include account ID and random suffix:
- **Format**: `pl-{resource}-{account-id}-{random-6-char}`
- **Example**: `pl-sensitive-data-954976316246-a3f9x2`
- Use the `resource_suffix` variable for consistent random suffixes

## Configuration

### Required Variables (Single Account)

Configure these in `terraform.tfvars`:

```hcl
# Minimal configuration for single-account scenarios
prod_account_id          = "111111111111"
prod_account_aws_profile = "my-playground-account"

# Enable specific scenarios
enable_prod_one_hop_to_admin_iam_putrolepolicy = true
enable_prod_one_hop_to_admin_iam_createaccesskey = true
enable_prod_toxic_combo_public_lambda_with_admin = true

# Keep everything else disabled
enable_prod_multi_hop_to_bucket_role_chain_to_s3 = false
# ... etc
```

### Optional Variables (Multi-Account)

For cross-account scenarios:

```hcl
# Add dev and ops accounts
dev_account_id         = "222222222222"
operations_account_id  = "333333333333"

dev_account_aws_profile        = "my-dev-profile"
operations_account_aws_profile = "my-ops-profile"

# Enable cross-account scenarios
enable_cross_account_dev_to_prod_simple_role_assumption = true
```

### Boolean Variable Convention

Each scenario has a corresponding boolean variable:

```hcl
# Format: enable_{account}_{category}_{target}_{technique}
enable_prod_one_hop_to_admin_iam_putrolepolicy = true
enable_prod_multi_hop_to_bucket_role_chain_to_s3 = true
enable_tool_testing_resource_policy_bypass = true
enable_tool_testing_exclusive_resource_policy = true
enable_cross_account_dev_to_prod_multi_hop_passrole_lambda_admin = true
```

## Pathfinder Starting Users

The project creates standardized starting users for each environment to serve as initial access points:

### Available Users
- `pl-pathfinding-starting-user-dev` - Development environment
- `pl-pathfinding-starting-user-prod` - Production environment
- `pl-pathfinding-starting-user-operations` - Operations environment

### Permissions
Each pathfinder starting user has minimal permissions:
- `sts:GetCallerIdentity` - Can identify themselves
- `iam:GetUser` - Can get their own user information

### Usage in Scenarios
- **User-based scenarios**: Use the pathfinder starting user directly
- **Role-based scenarios**: Initial roles trust the pathfinder starting user instead of `:root`
- **Cross-account scenarios**: Each environment's pathfinder user can assume trusted roles

## Attack Path Types

Pathfinding Labs supports diverse attack scenarios:

### One-Hop Paths
```
RoleA → iam:CreateAccessKey → RoleB (Admin)
RoleA → iam:PassRole + ec2:RunInstances → RoleB (Admin)
RoleA → iam:PutRolePolicy → Self (Admin)
```

### Multi-Hop Paths
```
RoleA → iam:CreateAccessKey → RoleB → sts:AssumeRole → RoleC (Admin)
RoleA → iam:PutRolePolicy → RoleB → sts:AssumeRole → RoleC → Sensitive-Bucket
```

### Cross-Account Paths
```
Account1:RoleA → iam:CreateAccessKey → Account1:RoleB → sts:AssumeRole → Account2:RoleC (Admin)
Account1:RoleA → iam:CreateAccessKey → Account1:RoleB → sts:AssumeRole → Account2:RoleC → Account2:Sensitive-Bucket
```

### Toxic Combinations
```
Lambda Function (publicly accessible) + Admin Role
EC2 Instance (internet-facing) + Critical CVE + Admin Role
S3 Bucket (public) + Sensitive Data + No Encryption
```

## CSPM Detection Examples

Each scenario documents what a properly configured CSPM should detect:

### Example: iam-createaccesskey Scenario

**Expected CSPM Alerts:**
- IAM role can create access keys for privileged users
- Privilege escalation path detected
- Role has permissions on admin user
- Potential for credential theft

**MITRE ATT&CK Mapping:**
- **Tactic**: Privilege Escalation, Persistence
- **Technique**: T1098.001 - Account Manipulation: Additional Cloud Credentials

## Use Cases

### 1. CSPM Validation
Deploy known vulnerabilities and verify your CSPM detects them:
```bash
enable_prod_toxic_combo_public_lambda_with_admin = true
terraform apply
# Check if CSPM alerts on: Lambda function publicly accessible + administrative permissions
```

### 2. Red Team Training
Practice exploitation techniques:
```bash
enable_prod_one_hop_to_admin_iam_putrolepolicy = true
terraform apply
cd modules/scenarios/single-account/privesc-one-hop/to-admin/iam-putrolepolicy
./demo_attack.sh
```

### 3. Security Tool Testing
Deploy multiple scenarios and test if your tooling finds all paths:
```bash
enable_prod_one_hop_to_admin_iam_putrolepolicy = true
enable_prod_one_hop_to_admin_iam_createaccesskey = true
enable_prod_multi_hop_to_admin_multiple_paths_combined = true
terraform apply
# Test your security tools against these scenarios
```

### 4. Incident Response Practice
Create realistic compromise scenarios and practice detection/response:
```bash
enable_cross_account_dev_to_prod_multi_hop_lambda_invoke_update = true
terraform apply
# Practice using CloudTrail, GuardDuty, and other AWS security services
```

## Important Warnings

### **ONLY USE IN PLAYGROUND/SANDBOX ACCOUNTS**

- ❌ **NEVER** deploy to production AWS accounts
- ❌ **NEVER** deploy to accounts with real customer data
- ❌ **NEVER** deploy to accounts with production workloads
- ✅ **ALWAYS** use isolated playground/sandbox accounts
- ✅ **ALWAYS** tear down resources when finished
- ✅ **ALWAYS** monitor costs and set billing alarms

### Security Best Practices

1. **Use SCPs** to prevent accidental production deployment
2. **Set up billing alerts** to catch unexpected charges
3. **Use separate AWS Organizations** for testing
4. **Review each scenario** before enabling
5. **Document your testing** for compliance and audit purposes

## Documentation Standards

- README files must include mermaid diagrams showing attack paths
- Use format: `graph LR` with nodes showing the escalation flow
- Document each step of the privilege escalation path
- Include CSPM detection guidance and MITRE ATT&CK mappings
- Provide usage instructions and prerequisites

## Future Roadmap

- [ ] Web interface for scenario management
- [ ] Go CLI for easier configuration
- [ ] More toxic combination scenarios
- [ ] GCP and Azure support
- [ ] Integration with popular CSPM tools
- [ ] Automated testing framework
- [ ] Video walkthroughs for each scenario

## Additional Resources

- [README.md](README.md) - Complete project documentation
- [RESTRUCTURE_PLAN.md](RESTRUCTURE_PLAN.md) - Architecture evolution details
- [IAM Vulnerable Project](https://github.com/bishopfox/iam-vulnerable) - Inspiration for single-account paths
- [Stratus Red Team](https://github.com/DataDog/stratus-red-team) - Similar approach for adversary emulation
- [MITRE ATT&CK Cloud Matrix](https://attack.mitre.org/matrices/enterprise/cloud/)