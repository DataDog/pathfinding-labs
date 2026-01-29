terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

locals {
  # Fall back to prod profile when dev/ops profiles are not configured
  # This allows single-account mode to work without errors
  effective_dev_profile = coalesce(var.dev_account_aws_profile, var.prod_account_aws_profile)
  effective_ops_profile = coalesce(var.operations_account_aws_profile, var.prod_account_aws_profile)
}

provider "aws" {
  alias   = "dev"
  profile = local.effective_dev_profile
  region  = var.aws_region
}

provider "aws" {
  alias   = "operations"
  profile = local.effective_ops_profile
  region  = var.aws_region
}

provider "aws" {
  alias   = "prod"
  profile = var.prod_account_aws_profile
  region  = var.aws_region
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
# ENVIRONMENT MODULES
##############################################################################

# Prod environment (enabled by default)
module "prod_environment" {
  count  = var.enable_prod_environment ? 1 : 0
  source = "./environments/prod"
  providers = {
    aws = aws.prod
  }
  dev_account_id        = var.dev_account_id
  prod_account_id       = var.prod_account_id
  operations_account_id = var.operations_account_id
  resource_suffix       = random_string.resource_suffix.result
}

# Dev environment is optional (for cross-account scenarios)
module "dev_environment" {
  count  = var.enable_dev_environment ? 1 : 0
  source = "./environments/dev"
  providers = {
    aws = aws.dev
  }
  dev_account_id        = var.dev_account_id
  prod_account_id       = var.prod_account_id
  operations_account_id = var.operations_account_id
  resource_suffix       = random_string.resource_suffix.result
}

# Ops environment is optional (for cross-account scenarios)
module "ops_environment" {
  count  = var.enable_ops_environment ? 1 : 0
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

module "single_account_privesc_self_escalation_to_admin_iam_005_iam_putrolepolicy" {
  count  = var.enable_single_account_privesc_self_escalation_to_admin_iam_005_iam_putrolepolicy ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-self-escalation/to-admin/iam-005-iam-putrolepolicy"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_self_escalation_to_admin_iam_009_iam_attachrolepolicy" {
  count  = var.enable_single_account_privesc_self_escalation_to_admin_iam_009_iam_attachrolepolicy ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-self-escalation/to-admin/iam-009-iam-attachrolepolicy"
  providers = {
    aws.prod = aws.prod
  }
  prod_account_id       = var.prod_account_id
  dev_account_id        = var.dev_account_id
  operations_account_id = var.operations_account_id
  resource_suffix       = random_string.resource_suffix.result
}

module "single_account_privesc_self_escalation_to_admin_iam_001_iam_createpolicyversion" {
  count  = var.enable_single_account_privesc_self_escalation_to_admin_iam_001_iam_createpolicyversion ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-self-escalation/to-admin/iam-001-iam-createpolicyversion"
  providers = {
    aws.prod = aws.prod
  }
  prod_account_id       = var.prod_account_id
  dev_account_id        = var.dev_account_id
  operations_account_id = var.operations_account_id
  resource_suffix       = random_string.resource_suffix.result
}

module "single_account_privesc_self_escalation_to_admin_iam_007_iam_putuserpolicy" {
  count  = var.enable_single_account_privesc_self_escalation_to_admin_iam_007_iam_putuserpolicy ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-self-escalation/to-admin/iam-007-iam-putuserpolicy"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_self_escalation_to_admin_iam_011_iam_putgrouppolicy" {
  count  = var.enable_single_account_privesc_self_escalation_to_admin_iam_011_iam_putgrouppolicy ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-self-escalation/to-admin/iam-011-iam-putgrouppolicy"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_self_escalation_to_admin_iam_013_iam_addusertogroup" {
  count  = var.enable_single_account_privesc_self_escalation_to_admin_iam_013_iam_addusertogroup ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-self-escalation/to-admin/iam-013-iam-addusertogroup"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_self_escalation_to_admin_iam_008_iam_attachuserpolicy" {
  count  = var.enable_single_account_privesc_self_escalation_to_admin_iam_008_iam_attachuserpolicy ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-self-escalation/to-admin/iam-008-iam-attachuserpolicy"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_self_escalation_to_admin_iam_010_iam_attachgrouppolicy" {
  count  = var.enable_single_account_privesc_self_escalation_to_admin_iam_010_iam_attachgrouppolicy ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-self-escalation/to-admin/iam-010-iam-attachgrouppolicy"
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

module "single_account_privesc_one_hop_to_admin_iam_019_iam_attachrolepolicy_iam_updateassumerolepolicy" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_iam_019_iam_attachrolepolicy_iam_updateassumerolepolicy ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/iam-019-iam-attachrolepolicy+iam-updateassumerolepolicy"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_iam_014_iam_attachrolepolicy_sts_assumerole" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_iam_014_iam_attachrolepolicy_sts_assumerole ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/iam-014-iam-attachrolepolicy+sts-assumerole"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_iam_015_iam_attachuserpolicy_iam_createaccesskey" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_iam_015_iam_attachuserpolicy_iam_createaccesskey ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/iam-015-iam-attachuserpolicy+iam-createaccesskey"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_apprunner_002_apprunner_updateservice" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_apprunner_002_apprunner_updateservice ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/apprunner-002-apprunner-updateservice"
  providers = {
    aws.prod = aws.prod
  }
  account_id                        = var.prod_account_id
  environment                       = "prod"
  resource_suffix                   = random_string.resource_suffix.result
  apprunner_service_linked_role_id  = module.prod_environment[0].apprunner_service_linked_role_id

  # Ensure service-linked role is created first and destroyed last
  depends_on = [module.prod_environment]
}

module "single_account_privesc_one_hop_to_admin_iam_002_iam_createaccesskey" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_iam_002_iam_createaccesskey ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/iam-002-iam-createaccesskey"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_iam_003_iam_deleteaccesskey_createaccesskey" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_iam_003_iam_deleteaccesskey_createaccesskey ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/iam-003-iam-deleteaccesskey+createaccesskey"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_apprunner_001_iam_passrole_apprunner_createservice" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_apprunner_001_iam_passrole_apprunner_createservice ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/apprunner-001-iam-passrole+apprunner-createservice"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_bedrock_001_iam_passrole_bedrockagentcore_codeinterpreter" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_bedrock_001_iam_passrole_bedrockagentcore_codeinterpreter ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/bedrock-001-iam-passrole+bedrockagentcore-codeinterpreter"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_bedrock_002_bedrockagentcore_startsession_invoke" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_bedrock_002_bedrockagentcore_startsession_invoke ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/bedrock-002-bedrockagentcore-startsession+invoke"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_ec2_001_iam_passrole_ec2_runinstances" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_ec2_001_iam_passrole_ec2_runinstances ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/ec2-001-iam-passrole+ec2-runinstances"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_ec2_004_iam_passrole_ec2_requestspotinstances" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_ec2_004_iam_passrole_ec2_requestspotinstances ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/ec2-004-iam-passrole+ec2-requestspotinstances"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/ec2-005-ec2-createlaunchtemplateversion+ec2-modifylaunchtemplate"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_ecs_002_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_runtask" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_ecs_002_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_runtask ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/ecs-002-iam-passrole+ecs-createcluster+ecs-registertaskdefinition+ecs-runtask"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_ecs_004_iam_passrole_ecs_registertaskdefinition_ecs_runtask" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_ecs_004_iam_passrole_ecs_registertaskdefinition_ecs_runtask ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/ecs-004-iam-passrole+ecs-registertaskdefinition+ecs-runtask"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_ecs_005_iam_passrole_ecs_registertaskdefinition_ecs_starttask" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_ecs_005_iam_passrole_ecs_registertaskdefinition_ecs_starttask ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/ecs-005-iam-passrole+ecs-registertaskdefinition+ecs-starttask"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_ecs_003_iam_passrole_ecs_registertaskdefinition_ecs_createservice" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_ecs_003_iam_passrole_ecs_registertaskdefinition_ecs_createservice ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/ecs-003-iam-passrole+ecs-registertaskdefinition+ecs-createservice"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_ecs_001_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_createservice" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_ecs_001_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_createservice ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/ecs-001-iam-passrole+ecs-createcluster+ecs-registertaskdefinition+ecs-createservice"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_ecs_006_ecs_executecommand" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_ecs_006_ecs_executecommand ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/ecs-006-ecs-executecommand"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_sts_001_sts_assumerole" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_sts_001_sts_assumerole ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/sts-001-sts-assumerole"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_iam_012_iam_updateassumerolepolicy" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_iam_012_iam_updateassumerolepolicy ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/iam-012-iam-updateassumerolepolicy"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_iam_004_iam_createloginprofile" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_iam_004_iam_createloginprofile ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/iam-004-iam-createloginprofile"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_iam_020_iam_createpolicyversion_iam_updateassumerolepolicy" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_iam_020_iam_createpolicyversion_iam_updateassumerolepolicy ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/iam-020-iam-createpolicyversion+iam-updateassumerolepolicy"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_iam_016_iam_createpolicyversion_sts_assumerole" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_iam_016_iam_createpolicyversion_sts_assumerole ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/iam-016-iam-createpolicyversion+sts-assumerole"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_iam_006_iam_updateloginprofile" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_iam_006_iam_updateloginprofile ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/iam-006-iam-updateloginprofile"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_lambda_006_iam_passrole_lambda_createfunction_lambda_addpermission" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_lambda_006_iam_passrole_lambda_createfunction_lambda_addpermission ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/lambda-006-iam-passrole+lambda-createfunction+lambda-addpermission"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_lambda_001_iam_passrole_lambda_createfunction_lambda_invokefunction" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_lambda_001_iam_passrole_lambda_createfunction_lambda_invokefunction ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/lambda-001-iam-passrole+lambda-createfunction+lambda-invokefunction"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_cloudformation_005_cloudformation_createchangeset_executechangeset" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_cloudformation_005_cloudformation_createchangeset_executechangeset ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/cloudformation-005-cloudformation-createchangeset+executechangeset"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_cloudformation_002_cloudformation_updatestack" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_cloudformation_002_cloudformation_updatestack ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/cloudformation-002-cloudformation-updatestack"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_cloudformation_004_iam_passrole_cloudformation_updatestackset" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_cloudformation_004_iam_passrole_cloudformation_updatestackset ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/cloudformation-004-iam-passrole+cloudformation-updatestackset"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_cloudformation_001_iam_passrole_cloudformation" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_cloudformation_001_iam_passrole_cloudformation ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/cloudformation-001-iam-passrole-cloudformation"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_cloudformation_003_iam_passrole_cloudformation_createstackset_cloudformation_createstackinstances" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_cloudformation_003_iam_passrole_cloudformation_createstackset_cloudformation_createstackinstances ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/cloudformation-003-iam-passrole+cloudformation-createstackset+cloudformation-createstackinstances"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_codebuild_001_iam_passrole_codebuild_createproject_codebuild_startbuild" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_codebuild_001_iam_passrole_codebuild_createproject_codebuild_startbuild ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/codebuild-001-iam-passrole+codebuild-createproject+codebuild-startbuild"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_codebuild_004_iam_passrole_codebuild_createproject_codebuild_startbuildbatch" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_codebuild_004_iam_passrole_codebuild_createproject_codebuild_startbuildbatch ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/codebuild-004-iam-passrole+codebuild-createproject+codebuild-startbuildbatch"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_iam_021_iam_putrolepolicy_iam_updateassumerolepolicy" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_iam_021_iam_putrolepolicy_iam_updateassumerolepolicy ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/iam-021-iam-putrolepolicy+iam-updateassumerolepolicy"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_iam_017_iam_putrolepolicy_sts_assumerole" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_iam_017_iam_putrolepolicy_sts_assumerole ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/iam-017-iam-putrolepolicy+sts-assumerole"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_iam_018_iam_putuserpolicy_iam_createaccesskey" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_iam_018_iam_putuserpolicy_iam_createaccesskey ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/iam-018-iam-putuserpolicy+iam-createaccesskey"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_lambda_002_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_lambda_002_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/lambda-002-iam-passrole+lambda-createfunction+createeventsourcemapping-dynamodb"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_lambda_003_lambda_updatefunctioncode" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_lambda_003_lambda_updatefunctioncode ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/lambda-003-lambda-updatefunctioncode"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_lambda_005_lambda_updatefunctioncode_lambda_addpermission" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_lambda_005_lambda_updatefunctioncode_lambda_addpermission ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/lambda-005-lambda-updatefunctioncode+lambda-addpermission"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_lambda_004_lambda_updatefunctioncode_lambda_invokefunction" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_lambda_004_lambda_updatefunctioncode_lambda_invokefunction ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/lambda-004-lambda-updatefunctioncode+lambda-invokefunction"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_ssm_002_ssm_sendcommand" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_ssm_002_ssm_sendcommand ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/ssm-002-ssm-sendcommand"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_ssm_001_ssm_startsession" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_ssm_001_ssm_startsession ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/ssm-001-ssm-startsession"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_codebuild_002_codebuild_startbuild" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_codebuild_002_codebuild_startbuild ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/codebuild-002-codebuild-startbuild"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_codebuild_003_codebuild_startbuildbatch" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_codebuild_003_codebuild_startbuildbatch ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/codebuild-003-codebuild-startbuildbatch"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_ec2_003_ec2_instance_connect_sendsshpublickey" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_ec2_003_ec2_instance_connect_sendsshpublickey ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/ec2-003-ec2-instance-connect-sendsshpublickey"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_ec2_002_ec2_modifyinstanceattribute_stopinstances_startinstances" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_ec2_002_ec2_modifyinstanceattribute_stopinstances_startinstances ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/ec2-002-ec2-modifyinstanceattribute+stopinstances+startinstances"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_glue_001_iam_passrole_glue_createdevendpoint" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_glue_001_iam_passrole_glue_createdevendpoint ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/glue-001-iam-passrole+glue-createdevendpoint"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_glue_002_glue_updatedevendpoint" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_glue_002_glue_updatedevendpoint ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/glue-002-glue-updatedevendpoint"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_glue_004_iam_passrole_glue_createjob_glue_createtrigger" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_glue_004_iam_passrole_glue_createjob_glue_createtrigger ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/glue-004-iam-passrole+glue-createjob+glue-createtrigger"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_glue_003_iam_passrole_glue_createjob_glue_startjobrun" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_glue_003_iam_passrole_glue_createjob_glue_startjobrun ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/glue-003-iam-passrole+glue-createjob+glue-startjobrun"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_glue_005_iam_passrole_glue_updatejob_glue_startjobrun" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_glue_005_iam_passrole_glue_updatejob_glue_startjobrun ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/glue-005-iam-passrole+glue-updatejob+glue-startjobrun"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_glue_006_iam_passrole_glue_updatejob_glue_createtrigger" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_glue_006_iam_passrole_glue_updatejob_glue_createtrigger ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/glue-006-iam-passrole+glue-updatejob+glue-createtrigger"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_sagemaker_001_iam_passrole_sagemaker_createnotebookinstance" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_sagemaker_001_iam_passrole_sagemaker_createnotebookinstance ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/sagemaker-001-iam-passrole+sagemaker-createnotebookinstance"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_sagemaker_003_iam_passrole_sagemaker_createprocessingjob" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_sagemaker_003_iam_passrole_sagemaker_createprocessingjob ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/sagemaker-003-iam-passrole+sagemaker-createprocessingjob"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_sagemaker_002_iam_passrole_sagemaker_createtrainingjob" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_sagemaker_002_iam_passrole_sagemaker_createtrainingjob ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/sagemaker-002-iam-passrole+sagemaker-createtrainingjob"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_sagemaker_004_sagemaker_createpresignednotebookinstanceurl" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_sagemaker_004_sagemaker_createpresignednotebookinstanceurl ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/sagemaker-004-sagemaker-createpresignednotebookinstanceurl"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_admin_sagemaker_005_sagemaker_updatenotebook_lifecycle_config" {
  count  = var.enable_single_account_privesc_one_hop_to_admin_sagemaker_005_sagemaker_updatenotebook_lifecycle_config ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/sagemaker-005-sagemaker-updatenotebook-lifecycle-config"
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

module "single_account_privesc_self_escalation_to_bucket_iam_005_iam_putrolepolicy" {
  count  = var.enable_single_account_privesc_self_escalation_to_bucket_iam_005_iam_putrolepolicy ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-self-escalation/to-bucket/iam-005-iam-putrolepolicy"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_self_escalation_to_bucket_iam_009_iam_attachrolepolicy" {
  count  = var.enable_single_account_privesc_self_escalation_to_bucket_iam_009_iam_attachrolepolicy ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-self-escalation/to-bucket/iam-009-iam-attachrolepolicy"
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

module "single_account_privesc_one_hop_to_bucket_glue_001_iam_passrole_glue_createdevendpoint" {
  count  = var.enable_single_account_privesc_one_hop_to_bucket_glue_001_iam_passrole_glue_createdevendpoint ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-bucket/glue-001-iam-passrole+glue-createdevendpoint"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_bucket_iam_002_iam_createaccesskey" {
  count  = var.enable_single_account_privesc_one_hop_to_bucket_iam_002_iam_createaccesskey ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-bucket/iam-002-iam-createaccesskey"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_bucket_iam_004_iam_createloginprofile" {
  count  = var.enable_single_account_privesc_one_hop_to_bucket_iam_004_iam_createloginprofile ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-bucket/iam-004-iam-createloginprofile"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_bucket_iam_003_iam_deleteaccesskey_createaccesskey" {
  count  = var.enable_single_account_privesc_one_hop_to_bucket_iam_003_iam_deleteaccesskey_createaccesskey ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-bucket/iam-003-iam-deleteaccesskey+createaccesskey"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_bucket_iam_012_iam_updateassumerolepolicy" {
  count  = var.enable_single_account_privesc_one_hop_to_bucket_iam_012_iam_updateassumerolepolicy ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-bucket/iam-012-iam-updateassumerolepolicy"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_bucket_sts_001_sts_assumerole" {
  count  = var.enable_single_account_privesc_one_hop_to_bucket_sts_001_sts_assumerole ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-bucket/sts-001-sts-assumerole"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_bucket_iam_006_iam_updateloginprofile" {
  count  = var.enable_single_account_privesc_one_hop_to_bucket_iam_006_iam_updateloginprofile ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-bucket/iam-006-iam-updateloginprofile"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_bucket_ec2_003_ec2_instance_connect_sendsshpublickey" {
  count  = var.enable_single_account_privesc_one_hop_to_bucket_ec2_003_ec2_instance_connect_sendsshpublickey ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-bucket/ec2-003-ec2-instance-connect-sendsshpublickey"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_bucket_glue_002_glue_updatedevendpoint" {
  count  = var.enable_single_account_privesc_one_hop_to_bucket_glue_002_glue_updatedevendpoint ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-bucket/glue-002-glue-updatedevendpoint"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_bucket_ssm_002_ssm_sendcommand" {
  count  = var.enable_single_account_privesc_one_hop_to_bucket_ssm_002_ssm_sendcommand ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-bucket/ssm-002-ssm-sendcommand"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "single_account_privesc_one_hop_to_bucket_ssm_001_ssm_startsession" {
  count  = var.enable_single_account_privesc_one_hop_to_bucket_ssm_001_ssm_startsession ? 1 : 0
  source = "./modules/scenarios/single-account/privesc-one-hop/to-bucket/ssm-001-ssm-startsession"
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

module "tool_testing_test_reverse_blast_radius_direct_and_indirect_through_admin" {
  count  = var.enable_tool_testing_test_reverse_blast_radius_direct_and_indirect_through_admin ? 1 : 0
  source = "./modules/scenarios/tool-testing/test-reverse-blast-radius-direct-and-indirect-through-admin"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "tool_testing_test_reverse_blast_radius_direct_and_indirect_to_bucket" {
  count  = var.enable_tool_testing_test_reverse_blast_radius_direct_and_indirect_to_bucket ? 1 : 0
  source = "./modules/scenarios/tool-testing/test-reverse-blast-radius-direct-and-indirect-to-bucket"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
}

module "tool_testing_test_effective_permissions_evaluation" {
  count  = var.enable_tool_testing_test_effective_permissions_evaluation ? 1 : 0
  source = "./modules/scenarios/tool-testing/test-effective-permissions-evaluation"
  providers = {
    aws.prod = aws.prod
  }
  account_id      = var.prod_account_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
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
  dev_account_id  = var.dev_account_id
  prod_account_id = var.prod_account_id
  resource_suffix = random_string.resource_suffix.result
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

module "cross_account_dev_to_prod_one_hop_root_trust_role_assumption" {
  count  = var.enable_cross_account_dev_to_prod_one_hop_root_trust_role_assumption ? 1 : 0
  source = "./modules/scenarios/cross-account/dev-to-prod/one-hop/root-trust-role-assumption"
  providers = {
    aws.prod = aws.prod
    aws.dev  = aws.dev
  }
  dev_account_id  = var.dev_account_id
  prod_account_id = var.prod_account_id
  resource_suffix = random_string.resource_suffix.result
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
