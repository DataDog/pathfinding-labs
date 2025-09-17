# Pathfinder Labs 

Try your hand at identifying and exploiting multiple cross-account AWS privilege escalation paths. 

Here are the types of attack paths that Pathfinder labs will create

| Start | Hop 1 | Hop 2 | Hop 3 | 
|--|--|--|--|
|`Prod:Low-priv`| **`Prod:Admin`** 👑| | |
|`Operations:Admin` | **`Prod:Admin`** 👑| | | 
|`Operations:Low-priv` | `Prod:low-priv` | **`Prod:Admin`** 👑| | 
|`Dev:Low-priv` | `Dev:Admin` | `Prod:low-priv` | **`Prod:Admin`** 👑| 
|`Dev:Low-priv` | `Ops:Low-priv` | **`Prod:Admin`** 👑| | | 


And many more. 


## Background

Who has access to my most sensiive S3 bucket? Is it 5% of my organization or 80%?
These are important questions to ask. In fact, you can ask the same question in another way: **If an attacker compromises one of my employees, what is the likelyhood they will be able to get to my most sensitve S3 bucket?**

There are tools that will help you find AWS privilege escalation paths, but most of them do this at the account level. **But what about cross-account privilege escalation paths?** Are you sure you are finding all of them before they are exploited? 

Deploy Pathfinder Labs, and put your skills, and your tooling, to the test! 

## Quick Start (Going to turn this into a script)

### If you already have 3 accounts that you can use for this lab

* **Step 1:** Configure profiles using aws-vault, aws-sso-util 
* **Step 2:** Configure Pathfinder Labs' terraform.tfvars with the three AWS profiles to use for prod, dev, and ops
* **Step 3:** Deploy Pathfinder Labs
* **Step 4:** Run `create_pathfinder_profiles.sh` to create the remaining profiles. 

### If you don't yet have 3 accounts that you can use for this lab

* **Step 1, Option A:** If you don't have anything you consider a production workload in your personal playground/testing account, enable AWS Organizations in this account
* **Step 1, Option B:** If you do have what you consider production workloads in your personal playground/test account, create a new AWS account and enable AWS Organizations in this new account
* **Step 2:** From within the Organization management account, create 3 accounts dedicated for pathfinder-labs pl-prod, pl-dev, pl-ops (creating accounts is free, and they will all roll up their billing to the mgmt account). 
* **Step 4:** Set up AWS IAM Identity Center in your org management account
* **Step 5:** Configure profiles using aws-vault, aws-sso-util 
* **Step 6:** Configure Pathfinder Labs' terraform.tfvars with the three AWS profiles to use for prod, dev, and ops
* **Step 7:** Deploy Pathfinder Labs
* **Step 8:** Run `create_pathfinder_profiles.sh` to create the remaining profiles. 

### Access Path Modules

#### Cross-Account Privilege Escalation

| Module | Description |
|--------|-------------|
| [x-account-from-dev-to-prod-role-assumption-s3-access](./modules/paths/x-account-from-dev-to-prod-role-assumption-s3-access/README.md) | From dev to prod via role assumption with S3 access |
| [x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin](./modules/paths/x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin/README.md) | Cross-account PassRole privilege escalation to Lambda admin |
| [x-account-from-dev-to-prod-multi-hop-privesc-both-sides](./modules/paths/x-account-from-dev-to-prod-multi-hop-privesc-both-sides/README.md) | Multi-hop cross-account privilege escalation using login profiles |
| [x-account-from-operations-to-prod-simple-role-assumption](./modules/paths/x-account-from-operations-to-prod-simple-role-assumption/README.md) | From operations to prod via role assumption |

#### Intra-Account Privilege Escalation - Attacking other principals

| Module | Description |
|--------|-------------|
| [prod_role_has_putrolepolicy_on_non_admin_role](./modules/paths/prod_role_has_putrolepolicy_on_non_admin_role/README.md) | PutRolePolicy privilege escalation to admin access |
| [prod_role_with_multiple_privesc_paths](./modules/paths/prod_role_with_multiple_privesc_paths/README.md) | Multiple privilege escalation paths via EC2, Lambda, and CloudFormation |
| [prod_simple_explicit_role_assumption_chain](./modules/paths/prod_simple_explicit_role_assumption_chain/README.md) | 3-hop role assumption chain in prod environment |
| [dev__user_has_createAccessKey_to_admin](./modules/paths/dev__user_has_createAccessKey_to_admin/README.md) | User privilege escalation via CreateAccessKey on admin user |


#### Intra-Account Privilege Escalation - Self-escalation

| Module | Description |
|--------|-------------|
| [prod_self_privesc_putRolePolicy](./modules/paths/prod_self_privesc_putRolePolicy/README.md) | Self-privilege escalation via PutRolePolicy on own role |
| [prod_self_privesc_attachRolePolicy](./modules/paths/prod_self_privesc_attachRolePolicy/README.md) | Self-privilege escalation via AttachRolePolicy on own role |
| [prod_self_privesc_createPolicyVersion](./modules/paths/prod_self_privesc_createPolicyVersion/README.md) | Self-privilege escalation via CreatePolicyVersion on own policy |


#### Accessing S3 Bucket through lateral movement without full admin access

| Module | Description |
|--------|-------------|
| [prod_role_has_access_to_bucket_through_resource_policy](./modules/paths/prod_role_has_access_to_bucket_through_resource_policy/README.md) | S3 bucket access through resource policy bypassing IAM restrictions |
| [prod_role_has_exclusive_access_to_bucket_through_resource_policy](./modules/paths/prod_role_has_exclusive_access_to_bucket_through_resource_policy/README.md) | Exclusive S3 bucket access through restrictive resource policy with explicit deny for others |

#### Misc

| Module | Description |
|--------|-------------|
| [dev_lambda_admin](./modules/paths/dev_lambda_admin/README.md) | Lambda admin access patterns in dev environment |

### Environment Modules

| Module | Description |
|--------|-------------|
| [dev](./modules/environments/dev/README.md) | Development environment resources |
| [prod](./modules/environments/prod/README.md) | Production environment resources |
| [operations](./modules/environments/operations/README.md) | Operations environment resources |

### Testing Framework

| Module | Description |
|--------|-------------|
| [tests/](./tests/README.md) | Automated testing framework for all modules |

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
