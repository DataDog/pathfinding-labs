# Pathfinder Labs 

Pathfinder Labs is a modular system for deploying intentionally vulnerable resources to your playground AWS account(s). 

## Who's it's for?

* **Blue teamers** - Test your CSPM tools. Do they detect all of the intentionally vulnerable modules? 
* **Red teamers** - Test your skills. Does your toolset and methodology find the vulnerable resources? Do you have the skills to exploit them? 

## How it works: 

**Step 1.** You tell pathfinder labs which AWS profile(s) to use
**Step 2.** You pick which modules you want to deploy
**Step 3.** You enable the modules and deploy
**Step 4.** You either exploit them, see if your CSPM detects them, or do both. 
**Step 5.** You disable the modules

## What kinds of vulnerable paths are supported: 

* Single hop IAM privilege escalation paths that lead to admin, e.g., 
   * `RoleA -> iam:createAccessKey -> RoleB`
   * `RoleA -> iam:passrole + ec2:runInstance -> RoleB`
* Single hop IAM privilege escalation paths that lead to a sensitive bucket, e.g., 
   * `RoleA -> iam:createAccessKey -> RoleB -> sensitive-bucket`
   * `RoleA -> iam:passrole + ec2:runInstance -> RoleB`
* Multi hop IAM privilege escalation paths that lead to admin, e.g., 
   * `RoleA -> iam:createAccessKey -> RoleB -> sts:AssumeRole -> Role C` 
* Multi hop IAM privilege escalation paths that lead to a sensitive bucket, e.g., 
   * `RoleA -> iam:createAccessKey -> RoleB -> sts:AssumeRole -> Role C -> sensitive-bucket` 
* Multi account IAM privilege escalation paths that lead to admin, e.g.,
   * `Account1:RoleA -> iam:createAccessKey -> Account1:RoleB -> sts:AssumeRole -> Account2:Role C -> Account2:sensitive-bucket`
* Multi account IAM privilege escalation paths that lead to a sensitive bucket, e.g., 
   * `Account1:RoleA -> iam:createAccessKey -> Account1:RoleB -> sts:AssumeRole -> Account2:Role C -> Account2:sensitive-bucket`
* Toxic combinations, e.g.,
   * `Lambda Function is publicly accessible and has an administrative role attached`
   * `S3 bucket publicly exposed with sensitive data`



## Background

Who has access to my most sensitive S3 bucket? Is it 5% of my organization or 80%?
These are important questions to ask. In fact, you can ask the same question in another way: **If an attacker compromises one of my employees, what is the likelihood they will be able to get to my most sensitive S3 bucket?**

There are tools that will help you find AWS privilege escalation paths, but most of them do this at the account level. **But what about cross-account privilege escalation paths?** Are you sure you are finding all of them before they are exploited? 

Deploy Pathfinder Labs, and put your skills, and your tooling, to the test! 

## Access Path Modules

| Key  | Description           |
|------|-----------------------|
| xa   | Cross-Account         |
| ia   | Intra-Account         | 
| pe   | Privilege Escalation  | 
| sd   | Sensitive Data Access |
| tc   | Toxic Combination     |


#### Intra-Account Privilege Escalation - Attacking other principals

| Module | Start | End | Starting Principal | Description |
|--------|-------|-----|-------------------|-------------|
| [ia-pe-001](./modules/paths/to-admin/prod/prod_role_has_putrolepolicy_on_non_admin_role/README.md) | prod | prod | `prod-role-a-non-admin` | PutRolePolicy privilege escalation to admin access |
| [ia-pe-002](./modules/paths/to-admin/prod/prod_role_with_multiple_privesc_paths/README.md) | prod | prod | `pl-pathfinder-starting-user-prod` | Multiple privilege escalation paths via EC2, Lambda, and CloudFormation |
| [ia-pe-003](./modules/paths/to-admin/dev/dev__user_has_createAccessKey_to_admin/README.md) | dev | dev | `pl-Adam` | User privilege escalation via CreateAccessKey on admin user |


#### Intra-Account Privilege Escalation - Self-escalation

| Module | Start | End | Starting Principal | Description |
|--------|-------|-----|-------------------|-------------|
| [ia-pe-005](./modules/paths/to-admin/prod/prod_self_privesc_putRolePolicy/README.md) | prod | prod | `pl-pathfinder-starting-user-prod` | Self-privilege escalation via PutRolePolicy on own role |
| [ia-pe-006](./modules/paths/to-admin/prod/prod_self_privesc_attachRolePolicy/README.md) | prod | prod | `pl-pathfinder-starting-user-prod` | Self-privilege escalation via AttachRolePolicy on own role |
| [ia-pe-007](./modules/paths/to-admin/prod/prod_self_privesc_createPolicyVersion/README.md) | prod | prod | `pl-pathfinder-starting-user-prod` | Self-privilege escalation via CreatePolicyVersion on own policy |


#### Intra-Account Accessing S3 Bucket through lateral movement without full admin access

| Module | Start | End | Starting Principal | Description |
|--------|-------|-----|-------------------|-------------|
| [ia-sd-001](./modules/paths/to-bucket/prod/prod_role_has_access_to_bucket_through_resource_policy/README.md) | prod | prod | `pl-pathfinder-starting-user-prod` | S3 bucket access through resource policy bypassing IAM restrictions |
| [ia-sd-002](./modules/paths/to-bucket/prod/prod_role_has_exclusive_access_to_bucket_through_resource_policy/README.md) | prod | prod | `pl-pathfinder-starting-user-prod` | Exclusive S3 bucket access through restrictive resource policy with explicit deny for others |
| [ia-sd-003](./modules/paths/to-bucket/prod/prod_simple_explicit_role_assumption_chain/README.md) | prod | prod | `pl-pathfinder-starting-user-prod` | 3-hop role assumption chain in prod environment to s3 bucket|

#### Cross-Account Privilege Escalation

| Module | Start | End | Starting Principal | Description |
|--------|-------|-----|-------------------|-------------|
| [xa-pe-001](./modules/paths/to-admin/x-account/x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin/README.md) | dev | prod | `pl-lambda-prod-updater` | Cross-account PassRole privilege escalation to Lambda admin |
| [xa-pe-002](./modules/paths/to-admin/x-account/x-account-from-dev-to-prod-multi-hop-privesc-both-sides/README.md) | dev | prod | `pl-pathfinder-starting-user-dev` | Multi-hop cross-account privilege escalation using login profiles |
| [xa-pe-003](./modules/paths/to-admin/x-account/x-account-from-operations-to-prod-simple-role-assumption/README.md) | operations | prod | `pl-pathfinder-starting-user-operations` | Cross-account role assumption |
| [xa-pe-004](./modules/paths/to-admin/x-account/x-account-from-dev-to-prod-invoke-and-update-on-prod-lambda/README.md) | dev | prod | `pl-pathfinder-starting-user-dev` | Cross-account Lambda function code update to extract credentials |




#### Cross-Account Accessing S3 Bucket through lateral movement without full admin access

| Module | Start | End | Starting Principal | Description |
|--------|-------|-----|-------------------|-------------|
| [xa-sd-001](./modules/paths/to-bucket/x-account/x-account-from-dev-to-prod-role-assumption-s3-access/README.md) | dev | prod | `s3-sensitive-data-access-user` | From dev to prod via role assumption with S3 access |





#### Vulnerable Cloud Resources

| Module | Start | End | Description |
|--------|-------|-----|-------------|
| [tc-001](./modules/paths/to-admin/dev/dev_lambda_admin/README.md) | dev | dev | Lambda admin access patterns in dev environment |

### Environment Modules

| Module | Description |
|--------|-------------|
| [dev](./modules/environments/dev/README.md) | Development environment resources |
| [prod](./modules/environments/prod/README.md) | Production environment resources |
| [operations](./modules/environments/operations/README.md) | Operations environment resources |


## Quick Start (Going to turn this into a script)

### If you already have 3 accounts that you can use for this lab

* **Step 1:** Configure profiles using aws-vault or aws-sso-util 
* **Step 2:** Configure Pathfinder Labs' terraform.tfvars with the AWS profiles to use for prod, dev, and ops (You can just configure prod to start if you'd like)
* **Step 3:** Deploy Pathfinder Labs
* **Step 4:** Run `create_pathfinder_profiles.sh` to create the remaining profiles. 


## Resource Naming Convention

All resources created by Pathfinder-labs follow a consistent naming pattern to prevent conflicts when multiple people deploy the repository:

- **Prefix**: All resources use the `pl-` prefix (Pathfinder Labs)
- **Random Suffix**: Globally namespaced resources (like S3 buckets) include a 6-character random alphanumeric suffix
- **Format**: `pl-{resource-type}-{account-id}-{random-suffix}`

This ensures that multiple deployments can coexist without resource name conflicts.

## Pathfinder Starting Users

The Pathfinder-labs project creates standardized starting users for each environment to serve as the initial access point for privilege escalation scenarios:

### **Available Users:**
- **`pl-pathfinder-starting-user-dev`** - Development environment starting user
- **`pl-pathfinder-starting-user-prod`** - Production environment starting user  
- **`pl-pathfinder-starting-user-operations`** - Operations environment starting user

### **Permissions:**
Each pathfinder starting user has minimal permissions:
- `sts:GetCallerIdentity` - Can identify themselves
- `iam:GetUser` - Can get their own user information

### **Creating AWS Profiles:**
After running `terraform apply`, create AWS profiles for each environment:

```bash
./create_pathfinder_profiles.sh
```

This creates three profiles:
- `pl-pathfinder-starting-user-dev` - Development environment
- `pl-pathfinder-starting-user-prod` - Production environment
- `pl-pathfinder-starting-user-operations` - Operations environment

### **Usage in Scenarios:**
- **User-based scenarios**: Use the pathfinder starting user directly
- **Role-based scenarios**: Initial roles trust the pathfinder starting user instead of `:root`
- **Cross-account scenarios**: Each environment's pathfinder user can assume trusted roles

## Usage

Each module can be used independently to test or implement specific cross-account access patterns. The modules are designed to be reusable and can be combined to create more complex access patterns.

To use a module:

1. Add the module to your root `main.tf`:
```hcl
module "module_name" {
  source = "./modules/module_name"
  providers = {
    aws.prod = aws.prod
    aws.dev = aws.dev
    aws.operations = aws.operations
  }
  dev_account_id = var.dev_account_id
  prod_account_id = var.prod_account_id
  operations_account_id = var.operations_account_id
}
```

2. Configure the required variables in your `terraform.tfvars` file
3. Run `terraform init` and `terraform apply`
4. Create pathfinder profiles: `./create_pathfinder_profiles.sh`

## Contributing

When adding new modules:
1. Create a new directory under `modules/`
2. Implement the required resources
3. Create a README.md in the module directory documenting the access paths using mermaid graph syntax
4. Include any specific usage instructions or requirements
5. Add the module to this table of contents
