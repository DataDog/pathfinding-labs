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

##############################################################################
# ENVIRONMENT MODULES (Always Deployed)
##############################################################################

module "prod_environment" {
  source = "./environments/prod"
  providers = {
    aws = aws.prod
  }
  dev_account_id        = var.dev_account_id
  prod_account_id       = var.prod_account_id
  operations_account_id = var.operations_account_id
  resource_suffix       = random_string.resource_suffix.result
}

module "dev_environment" {
  source = "./environments/dev"
  providers = {
    aws = aws.dev
  }
  dev_account_id        = var.dev_account_id
  prod_account_id       = var.prod_account_id
  operations_account_id = var.operations_account_id
  resource_suffix       = random_string.resource_suffix.result
}

module "ops_environment" {
  source = "./environments/ops"
  providers = {
    aws = aws.operations
  }
  dev_account_id        = var.dev_account_id
  prod_account_id       = var.prod_account_id
  operations_account_id = var.operations_account_id
  resource_suffix       = random_string.resource_suffix.result
}

##############################################################################
# PROD SELF ESCALATION TO-ADMIN SCENARIOS
##############################################################################

module "single_account_privesc_self_escalation_to_admin_iam_putrolepolicy" {
  count  = var.enable_single_account_privesc_self_escalation_to_admin_iam_putrolepolicy ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-self-escalation/to-admin/iam-putrolepolicy"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_self_escalation_to_admin_iam_attachrolepolicy" {
  count  = var.enable_single_account_privesc_self_escalation_to_admin_iam_attachrolepolicy ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-self-escalation/to-admin/iam-attachrolepolicy"
  providers = {
    aws.prod = aws.prod
  }
  prod_account_id       = var.prod_account_id
  dev_account_id        = var.dev_account_id
  operations_account_id = var.operations_account_id
  resource_suffix       = random_string.resource_suffix.result
}

module "single_account_privesc_self_escalation_to_admin_iam_createpolicyversion" {
  count  = var.enable_single_account_privesc_self_escalation_to_admin_iam_createpolicyversion ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-self-escalation/to-admin/iam-createpolicyversion"
  providers = {
    aws.prod = aws.prod
  }
  prod_account_id       = var.prod_account_id
  dev_account_id        = var.dev_account_id
  operations_account_id = var.operations_account_id
  resource_suffix       = random_string.resource_suffix.result
}

module "single_account_privesc_self_escalation_to_admin_iam_putuserpolicy" {
  count  = var.enable_single_account_privesc_self_escalation_to_admin_iam_putuserpolicy ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-self-escalation/to-admin/iam-putuserpolicy"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_self_escalation_to_admin_iam_putgrouppolicy" {
  count  = var.enable_single_account_privesc_self_escalation_to_admin_iam_putgrouppolicy ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-self-escalation/to-admin/iam-putgrouppolicy"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_self_escalation_to_admin_iam_addusertogroup" {
  count  = var.enable_single_account_privesc_self_escalation_to_admin_iam_addusertogroup ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-self-escalation/to-admin/iam-addusertogroup"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_self_escalation_to_admin_iam_attachuserpolicy" {
  count  = var.enable_single_account_privesc_self_escalation_to_admin_iam_attachuserpolicy ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-self-escalation/to-admin/iam-attachuserpolicy"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_self_escalation_to_admin_iam_attachgrouppolicy" {
  count  = var.enable_single_account_privesc_self_escalation_to_admin_iam_attachgrouppolicy ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-self-escalation/to-admin/iam-attachgrouppolicy"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}


##############################################################################
# PROD ONE-HOP TO-ADMIN SCENARIOS
##############################################################################



module "single_account_privesc_one_hop_to_admin_iam_createaccesskey" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_iam_createaccesskey ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/iam-createaccesskey"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_iam_passrole_ec2_runinstances" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_iam_passrole_ec2_runinstances ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/iam-passrole+ec2-runinstances"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_sts_assumerole" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_sts_assumerole ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/sts-assumerole"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_iam_updateassumerolepolicy" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_iam_updateassumerolepolicy ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/iam-updateassumerolepolicy"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_iam_createloginprofile" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_iam_createloginprofile ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/iam-createloginprofile"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_iam_updateloginprofile" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_iam_updateloginprofile ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/iam-updateloginprofile"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}



module "single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/iam-passrole+lambda-createfunction+lambda-invokefunction"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_iam_passrole_cloudformation" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_iam_passrole_cloudformation ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/iam-passrole-cloudformation"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/iam-passrole+lambda-createfunction+createeventsourcemapping-dynamodb"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_lambda_updatefunctioncode" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_lambda_updatefunctioncode ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/lambda-updatefunctioncode"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_ssm_sendcommand" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_ssm_sendcommand ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/ssm-sendcommand"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}



##############################################################################
# PROD SELF_ESCALATION TO-BUCKET SCENARIOS
##############################################################################

module "single_account_privesc_self_escalation_to_bucket_iam_putrolepolicy" {
  count  = var.enable_single_account_privesc_self_escalation_to_bucket_iam_putrolepolicy ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-self-escalation/to-bucket/iam-putrolepolicy"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_self_escalation_to_bucket_iam_attachrolepolicy" {
  count  = var.enable_single_account_privesc_self_escalation_to_bucket_iam_attachrolepolicy ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-self-escalation/to-bucket/iam-attachrolepolicy"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}


##############################################################################
# PROD ONE-HOP TO-BUCKET SCENARIOS
##############################################################################



module "single_account_privesc_one_hop_to_bucket_iam_createaccesskey" {
  count  = var.enable_single_account_privesc_one_hop_to_bucket_iam_createaccesskey ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-bucket/iam-createaccesskey"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_bucket_iam_createloginprofile" {
  count  = var.enable_single_account_privesc_one_hop_to_bucket_iam_createloginprofile ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-bucket/iam-createloginprofile"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_bucket_iam_updateassumerolepolicy" {
  count  = var.enable_single_account_privesc_one_hop_to_bucket_iam_updateassumerolepolicy ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-bucket/iam-updateassumerolepolicy"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_bucket_sts_assumerole" {
  count  = var.enable_single_account_privesc_one_hop_to_bucket_sts_assumerole ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-bucket/sts-assumerole"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_bucket_iam_updateloginprofile" {
  count  = var.enable_single_account_privesc_one_hop_to_bucket_iam_updateloginprofile ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-bucket/iam-updateloginprofile"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_bucket_ssm_sendcommand" {
  count  = var.enable_single_account_privesc_one_hop_to_bucket_ssm_sendcommand ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-bucket/ssm-sendcommand"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

##############################################################################
# PROD MULTI-HOP TO-ADMIN SCENARIOS
##############################################################################

module "single_account_privesc_multi_hop_to_admin_putrolepolicy_on_other" {
  count  = var.enable_single_account_privesc_multi_hop_to_admin_putrolepolicy_on_other ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-multi-hop/to-admin/putrolepolicy-on-other"
  providers = {
    aws.prod = aws.prod
  }
  prod_account_id = var.prod_account_id
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_multi_hop_to_admin_multiple_paths_combined" {
  count  = var.enable_single_account_privesc_multi_hop_to_admin_multiple_paths_combined ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-multi-hop/to-admin/multiple-paths-combined"
  providers = {
    aws.prod = aws.prod
  }
  dev_account_id        = var.dev_account_id
  prod_account_id       = var.prod_account_id
  operations_account_id = var.operations_account_id
  resource_suffix       = random_string.resource_suffix.result
}

##############################################################################
# PROD MULTI-HOP TO-BUCKET SCENARIOS
##############################################################################

module "single_account_privesc_multi_hop_to_bucket_role_chain_to_s3" {
  count  = var.enable_single_account_privesc_multi_hop_to_bucket_role_chain_to_s3 ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-multi-hop/to-bucket/role-chain-to-s3"
  providers = {
    aws.prod = aws.prod
  }
  prod_account_id       = var.prod_account_id
  operations_account_id = var.operations_account_id
  resource_suffix       = random_string.resource_suffix.result
}

module "tool_testing_resource_policy_bypass" {
  count  = var.enable_tool_testing_resource_policy_bypass ? 1 : 0
  source = "./modules/scenarios/tool-testing/resource-policy-bypass"
  providers = {
    aws.prod = aws.prod
  }
  dev_account_id        = var.dev_account_id
  prod_account_id       = var.prod_account_id
  operations_account_id = var.operations_account_id
  resource_suffix       = random_string.resource_suffix.result
}

module "tool_testing_exclusive_resource_policy" {
  count  = var.enable_tool_testing_exclusive_resource_policy ? 1 : 0
  source = "./modules/scenarios/tool-testing/exclusive-resource-policy"
  providers = {
    aws.prod = aws.prod
  }
  dev_account_id        = var.dev_account_id
  prod_account_id       = var.prod_account_id
  operations_account_id = var.operations_account_id
  resource_suffix       = random_string.resource_suffix.result
}

##############################################################################
# PROD TOXIC-COMBO SCENARIOS
##############################################################################

module "single_account_toxic_combo_public_lambda_with_admin" {
  count  = var.enable_single_account_toxic_combo_public_lambda_with_admin ? 1 : 0
  source = "./modules/scenarios/single-account/toxic-combo/public-lambda-with-admin"
  providers = {
    aws.dev = aws.dev
  }
  dev_account_id        = var.dev_account_id
  prod_account_id       = var.prod_account_id
  operations_account_id = var.operations_account_id
  resource_suffix       = random_string.resource_suffix.result
}

##############################################################################
# CROSS-ACCOUNT DEV-TO-PROD SCENARIOS
##############################################################################

module "cross_account_dev_to_prod_one_hop_simple_role_assumption" {
  count  = var.enable_cross_account_dev_to_prod_one_hop_simple_role_assumption ? 1 : 0
  source = "./modules/scenarios/cross-account/dev-to-prod/one-hop/simple-role-assumption"
  providers = {
    aws.prod = aws.prod
    aws.dev  = aws.dev
  }
  dev_account_id        = var.dev_account_id
  prod_account_id       = var.prod_account_id
  operations_account_id = var.operations_account_id
  resource_suffix       = random_string.resource_suffix.result
}

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

module "cross_account_dev_to_prod_multi_hop_multi_hop_both_sides" {
  count  = var.enable_cross_account_dev_to_prod_multi_hop_multi_hop_both_sides ? 1 : 0
  source = "./modules/scenarios/cross-account/dev-to-prod/multi-hop/multi-hop-both-sides"
  providers = {
    aws.dev  = aws.dev
    aws.prod = aws.prod
  }
  dev_account_id        = var.dev_account_id
  prod_account_id       = var.prod_account_id
  operations_account_id = var.operations_account_id
  resource_suffix       = random_string.resource_suffix.result
}

module "cross_account_dev_to_prod_multi_hop_lambda_invoke_update" {
  count  = var.enable_cross_account_dev_to_prod_multi_hop_lambda_invoke_update ? 1 : 0
  source = "./modules/scenarios/cross-account/dev-to-prod/multi-hop/lambda-invoke-update"
  providers = {
    aws.dev  = aws.dev
    aws.prod = aws.prod
  }
  dev_account_id        = var.dev_account_id
  prod_account_id       = var.prod_account_id
  operations_account_id = var.operations_account_id
  resource_suffix       = random_string.resource_suffix.result
}

##############################################################################
# CROSS-ACCOUNT OPS-TO-PROD SCENARIOS
##############################################################################

module "cross_account_ops_to_prod_one_hop_simple_role_assumption" {
  count  = var.enable_cross_account_ops_to_prod_one_hop_simple_role_assumption ? 1 : 0
  source = "./modules/scenarios/cross-account/ops-to-prod/one-hop/simple-role-assumption"
  providers = {
    aws.prod       = aws.prod
    aws.operations = aws.operations
  }
  dev_account_id        = var.dev_account_id
  prod_account_id       = var.prod_account_id
  operations_account_id = var.operations_account_id
  resource_suffix       = random_string.resource_suffix.result
}
