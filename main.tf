terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  alias   = "dev"
  profile = var.dev_account_aws_profile
  region  = "us-west-2"
}

provider "aws" {
  alias   = "operations"
  profile = var.operations_account_aws_profile
  region  = "us-west-2"
}

provider "aws" {
  alias   = "prod"
  profile = var.prod_account_aws_profile
  region  = "us-west-2"
}

# Random suffix for globally namespaced resources to prevent conflicts
resource "random_string" "resource_suffix" {
  length  = 6
  upper   = false
  lower   = true
  numeric = true
  special = false
}

module "dev_resources" {
  source = "./modules/environments/dev"
  providers = {
    aws = aws.dev
  }
  dev_account_id         = var.dev_account_id
  prod_account_id        = var.prod_account_id
  operations_account_id  = var.operations_account_id
  resource_suffix        = random_string.resource_suffix.result
}

module "operations_resources" {
  source = "./modules/environments/operations"
  providers = {
    aws = aws.operations
  }
  dev_account_id         = var.dev_account_id
  prod_account_id        = var.prod_account_id
  operations_account_id  = var.operations_account_id
  github_repo           = var.github_repo
  resource_suffix        = random_string.resource_suffix.result
}

module "prod_resources" {
  source = "./modules/environments/prod"
  providers = {
    aws = aws.prod
  }
  dev_account_id         = var.dev_account_id
  prod_account_id        = var.prod_account_id
  operations_account_id  = var.operations_account_id
  resource_suffix        = random_string.resource_suffix.result
  github_repo            = var.github_repo
}

module "x_account_from_operations_to_prod_simple_role_assumption" {
  source = "./modules/paths/to-admin/x-account/x-account-from-operations-to-prod-simple-role-assumption"  
  providers = {
    aws.prod = aws.prod
    aws.operations = aws.operations
  } 
  dev_account_id         = var.dev_account_id
  prod_account_id        = var.prod_account_id
  operations_account_id  = var.operations_account_id
  resource_suffix        = random_string.resource_suffix.result
}

module "x_account_from_dev_to_prod_role_assumption_s3_access" {
  source = "./modules/paths/to-bucket/x-account/x-account-from-dev-to-prod-role-assumption-s3-access"
  providers = {
    aws.prod = aws.prod
    aws.dev = aws.dev
  }
  dev_account_id         = var.dev_account_id
  prod_account_id        = var.prod_account_id
  operations_account_id  = var.operations_account_id
  resource_suffix        = random_string.resource_suffix.result
}

module "dev_lambda_admin" {
  source = "./modules/paths/to-admin/dev/dev_lambda_admin"
  providers = {
    aws.dev = aws.dev
  }
  dev_account_id         = var.dev_account_id
  prod_account_id        = var.prod_account_id
  operations_account_id  = var.operations_account_id
  resource_suffix        = random_string.resource_suffix.result
}

module "prod_simple_explicit_role_assumption_chain" {
  source = "./modules/paths/to-bucket/prod/prod_simple_explicit_role_assumption_chain"
  providers = {
    aws.prod = aws.prod
  }
  prod_account_id        = var.prod_account_id
  operations_account_id  = var.operations_account_id
  resource_suffix        = random_string.resource_suffix.result
}

module "prod_role_has_putrolepolicy_on_non_admin_role" {
  source = "./modules/paths/to-admin/prod/prod_role_has_putrolepolicy_on_non_admin_role"
  providers = {
    aws.prod = aws.prod
  }
  prod_account_id = var.prod_account_id
  resource_suffix = random_string.resource_suffix.result
}

module "prod_self_privesc_putRolePolicy" {
  source = "./modules/paths/to-admin/prod/prod_self_privesc_putRolePolicy"
  providers = {
    aws.prod = aws.prod
  }
  dev_account_id         = var.dev_account_id
  prod_account_id        = var.prod_account_id
  operations_account_id  = var.operations_account_id
  resource_suffix        = random_string.resource_suffix.result
}

module "prod_self_privesc_attachRolePolicy" {
  source = "./modules/paths/to-admin/prod/prod_self_privesc_attachRolePolicy"
  providers = {
    aws.prod = aws.prod
  }
  dev_account_id         = var.dev_account_id
  prod_account_id        = var.prod_account_id
  operations_account_id  = var.operations_account_id
  resource_suffix        = random_string.resource_suffix.result
}

module "prod_self_privesc_createPolicyVersion" {
  source = "./modules/paths/to-admin/prod/prod_self_privesc_createPolicyVersion"
  providers = {
    aws.prod = aws.prod
  }
  dev_account_id         = var.dev_account_id
  prod_account_id        = var.prod_account_id
  operations_account_id  = var.operations_account_id
  resource_suffix        = random_string.resource_suffix.result
}

module "prod_role_with_multiple_privesc_paths" {
  source = "./modules/paths/to-admin/prod/prod_role_with_multiple_privesc_paths"
  providers = {
    aws.prod = aws.prod
  }
  dev_account_id         = var.dev_account_id
  prod_account_id        = var.prod_account_id
  operations_account_id  = var.operations_account_id
  resource_suffix        = random_string.resource_suffix.result
}

module "dev__user_has_createAccessKey_to_admin" {
  source = "./modules/paths/to-admin/dev/dev__user_has_createAccessKey_to_admin"
  providers = {
    aws.dev = aws.dev
  }
  dev_account_id         = var.dev_account_id
  prod_account_id        = var.prod_account_id
  operations_account_id  = var.operations_account_id
  resource_suffix        = random_string.resource_suffix.result
}

module "x_account_from_dev_to_prod_role_assumption_passrole_to_lambda_admin" {
  source = "./modules/paths/to-admin/x-account/x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin"
  providers = {
    aws.dev = aws.dev
    aws.prod = aws.prod
  }
  dev_account_id         = var.dev_account_id
  prod_account_id        = var.prod_account_id
  operations_account_id  = var.operations_account_id
  resource_suffix        = random_string.resource_suffix.result
}

module "x_account_from_dev_to_prod_multi_hop_privesc_both_sides" {
  source = "./modules/paths/to-admin/x-account/x-account-from-dev-to-prod-multi-hop-privesc-both-sides"
  providers = {
    aws.dev = aws.dev
    aws.prod = aws.prod
  }
  dev_account_id         = var.dev_account_id
  prod_account_id        = var.prod_account_id
  operations_account_id  = var.operations_account_id
  resource_suffix        = random_string.resource_suffix.result
}

module "prod_role_has_access_to_bucket_through_resource_policy" {
  source = "./modules/paths/to-bucket/prod/prod_role_has_access_to_bucket_through_resource_policy"
  providers = {
    aws.prod = aws.prod
  }
  dev_account_id         = var.dev_account_id
  prod_account_id        = var.prod_account_id
  operations_account_id  = var.operations_account_id
  resource_suffix        = random_string.resource_suffix.result
}

module "prod_role_has_exclusive_access_to_bucket_through_resource_policy" {
  source = "./modules/paths/to-bucket/prod/prod_role_has_exclusive_access_to_bucket_through_resource_policy"
  providers = {
    aws.prod = aws.prod
  }
  dev_account_id         = var.dev_account_id
  prod_account_id        = var.prod_account_id
  operations_account_id  = var.operations_account_id
  resource_suffix        = random_string.resource_suffix.result
}

module "x_account_from_dev_to_prod_invoke_and_update_on_prod_lambda" {
  source = "./modules/paths/to-admin/x-account/x-account-from-dev-to-prod-invoke-and-update-on-prod-lambda"
  providers = {
    aws.dev = aws.dev
    aws.prod = aws.prod
  }
  dev_account_id         = var.dev_account_id
  prod_account_id        = var.prod_account_id
  operations_account_id  = var.operations_account_id
  resource_suffix        = random_string.resource_suffix.result
}

