# Outputs for pathfinding starting users
output "dev_pathfinding_starting_user_access_key_id" {
  description = "Access key ID for the pathfinding starting user in dev environment"
  value       = var.enable_dev_environment ? module.dev_environment[0].pathfinding_starting_user_access_key_id : null
  sensitive   = true
}

output "dev_pathfinding_starting_user_secret_access_key" {
  description = "Secret access key for the pathfinding starting user in dev environment"
  value       = var.enable_dev_environment ? module.dev_environment[0].pathfinding_starting_user_secret_access_key : null
  sensitive   = true
}


output "operations_pathfinding_starting_user_access_key_id" {
  description = "Access key ID for the pathfinding starting user in operations environment"
  value       = var.enable_ops_environment ? module.ops_environment[0].pathfinding_starting_user_access_key_id : null
  sensitive   = true
}

output "operations_pathfinding_starting_user_secret_access_key" {
  description = "Secret access key for the pathfinding starting user in operations environment"
  value       = var.enable_ops_environment ? module.ops_environment[0].pathfinding_starting_user_secret_access_key : null
  sensitive   = true
}

# Resource suffix for globally unique resources
output "resource_suffix" {
  description = "Random suffix used for globally unique resources"
  value       = random_string.resource_suffix.result
}

# Admin cleanup user outputs
output "dev_admin_user_for_cleanup_access_key_id" {
  description = "Access key ID for the admin cleanup user in dev environment"
  value       = var.enable_dev_environment ? module.dev_environment[0].admin_user_for_cleanup_access_key_id : null
  sensitive   = true
}

output "dev_admin_user_for_cleanup_secret_access_key" {
  description = "Secret access key for the admin cleanup user in dev environment"
  value       = var.enable_dev_environment ? module.dev_environment[0].admin_user_for_cleanup_secret_access_key : null
  sensitive   = true
}

output "prod_admin_user_for_cleanup_access_key_id" {
  description = "Access key ID for the admin cleanup user in prod environment"
  value       = var.enable_prod_environment ? module.prod_environment[0].admin_user_for_cleanup_access_key_id : null
  sensitive   = true
}

output "prod_admin_user_for_cleanup_secret_access_key" {
  description = "Secret access key for the admin cleanup user in prod environment"
  value       = var.enable_prod_environment ? module.prod_environment[0].admin_user_for_cleanup_secret_access_key : null
  sensitive   = true
}

output "operations_admin_user_for_cleanup_access_key_id" {
  description = "Access key ID for the admin cleanup user in operations environment"
  value       = var.enable_ops_environment ? module.ops_environment[0].admin_user_for_cleanup_access_key_id : null
  sensitive   = true
}

output "operations_admin_user_for_cleanup_secret_access_key" {
  description = "Secret access key for the admin cleanup user in operations environment"
  value       = var.enable_ops_environment ? module.ops_environment[0].admin_user_for_cleanup_secret_access_key : null
  sensitive   = true
}

##############################################################################
# CONDITIONAL SCENARIO OUTPUTS
# Only output if the scenario is enabled
##############################################################################


output "prod_multi_hop_to_bucket_role_chain_s3_bucket_name" {
  description = "Name of the S3 bucket in prod multi-hop role-chain-to-s3 scenario"
  value       = var.enable_single_account_privesc_multi_hop_to_bucket_role_chain_to_s3 ? module.single_account_privesc_multi_hop_to_bucket_role_chain_to_s3[0].s3_bucket_name : null
}

output "prod_account_id" {
  description = "ID of the prod account (derived from AWS profile)"
  value       = local.prod_account_id
}

output "dev_account_id" {
  description = "ID of the dev account (derived from AWS profile)"
  value       = local.dev_account_id
}

output "operations_account_id" {
  description = "ID of the operations account (derived from AWS profile)"
  value       = local.operations_account_id
}

output "aws_region" {
  description = "AWS region for resources"
  value       = var.aws_region
}

##############################################################################
# GROUPED SCENARIO OUTPUTS (for demo scripts)
# These group all related outputs for a scenario into a single object
##############################################################################

# Self-escalation to-admin scenarios
output "single_account_privesc_self_escalation_to_admin_iam_008_iam_attachuserpolicy" {
  description = "All outputs for iam-008-iam-attachuserpolicy self-escalation scenario"
  value = var.enable_single_account_privesc_self_escalation_to_admin_iam_008_iam_attachuserpolicy ? {
    starting_user_name              = module.single_account_privesc_self_escalation_to_admin_iam_008_iam_attachuserpolicy[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_self_escalation_to_admin_iam_008_iam_attachuserpolicy[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_self_escalation_to_admin_iam_008_iam_attachuserpolicy[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_self_escalation_to_admin_iam_008_iam_attachuserpolicy[0].starting_user_secret_access_key
    attack_path                     = module.single_account_privesc_self_escalation_to_admin_iam_008_iam_attachuserpolicy[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_self_escalation_to_admin_iam_007_iam_putuserpolicy" {
  description = "All outputs for iam-007-iam-putuserpolicy self-escalation scenario"
  value = var.enable_single_account_privesc_self_escalation_to_admin_iam_007_iam_putuserpolicy ? {
    starting_user_name              = module.single_account_privesc_self_escalation_to_admin_iam_007_iam_putuserpolicy[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_self_escalation_to_admin_iam_007_iam_putuserpolicy[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_self_escalation_to_admin_iam_007_iam_putuserpolicy[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_self_escalation_to_admin_iam_007_iam_putuserpolicy[0].starting_user_secret_access_key
    attack_path                     = module.single_account_privesc_self_escalation_to_admin_iam_007_iam_putuserpolicy[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_self_escalation_to_admin_iam_005_iam_putrolepolicy" {
  description = "All outputs for iam-005-iam-putrolepolicy self-escalation scenario"
  value = var.enable_single_account_privesc_self_escalation_to_admin_iam_005_iam_putrolepolicy ? {
    starting_user_name              = module.single_account_privesc_self_escalation_to_admin_iam_005_iam_putrolepolicy[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_self_escalation_to_admin_iam_005_iam_putrolepolicy[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_self_escalation_to_admin_iam_005_iam_putrolepolicy[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_self_escalation_to_admin_iam_005_iam_putrolepolicy[0].starting_user_secret_access_key
    starting_role_arn               = module.single_account_privesc_self_escalation_to_admin_iam_005_iam_putrolepolicy[0].starting_role_arn
    starting_role_name              = module.single_account_privesc_self_escalation_to_admin_iam_005_iam_putrolepolicy[0].starting_role_name
    policy_arn                      = module.single_account_privesc_self_escalation_to_admin_iam_005_iam_putrolepolicy[0].policy_arn
    attack_path                     = module.single_account_privesc_self_escalation_to_admin_iam_005_iam_putrolepolicy[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_self_escalation_to_admin_iam_009_iam_attachrolepolicy" {
  description = "All outputs for iam-009-iam-attachrolepolicy self-escalation scenario"
  value = var.enable_single_account_privesc_self_escalation_to_admin_iam_009_iam_attachrolepolicy ? {
    starting_user_name              = module.single_account_privesc_self_escalation_to_admin_iam_009_iam_attachrolepolicy[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_self_escalation_to_admin_iam_009_iam_attachrolepolicy[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_self_escalation_to_admin_iam_009_iam_attachrolepolicy[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_self_escalation_to_admin_iam_009_iam_attachrolepolicy[0].starting_user_secret_access_key
    starting_role_arn               = module.single_account_privesc_self_escalation_to_admin_iam_009_iam_attachrolepolicy[0].starting_role_arn
    starting_role_name              = module.single_account_privesc_self_escalation_to_admin_iam_009_iam_attachrolepolicy[0].starting_role_name
    policy_arn                      = module.single_account_privesc_self_escalation_to_admin_iam_009_iam_attachrolepolicy[0].policy_arn
    attack_path                     = module.single_account_privesc_self_escalation_to_admin_iam_009_iam_attachrolepolicy[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_self_escalation_to_admin_iam_001_iam_createpolicyversion" {
  description = "All outputs for iam-001-iam-createpolicyversion self-escalation scenario"
  value = var.enable_single_account_privesc_self_escalation_to_admin_iam_001_iam_createpolicyversion ? {
    starting_user_name              = module.single_account_privesc_self_escalation_to_admin_iam_001_iam_createpolicyversion[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_self_escalation_to_admin_iam_001_iam_createpolicyversion[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_self_escalation_to_admin_iam_001_iam_createpolicyversion[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_self_escalation_to_admin_iam_001_iam_createpolicyversion[0].starting_user_secret_access_key
    starting_role_arn               = module.single_account_privesc_self_escalation_to_admin_iam_001_iam_createpolicyversion[0].starting_role_arn
    starting_role_name              = module.single_account_privesc_self_escalation_to_admin_iam_001_iam_createpolicyversion[0].starting_role_name
    policy_arn                      = module.single_account_privesc_self_escalation_to_admin_iam_001_iam_createpolicyversion[0].policy_arn
    attack_path                     = module.single_account_privesc_self_escalation_to_admin_iam_001_iam_createpolicyversion[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_self_escalation_to_admin_iam_013_iam_addusertogroup" {
  description = "All outputs for iam-013-iam-addusertogroup self-escalation scenario"
  value = var.enable_single_account_privesc_self_escalation_to_admin_iam_013_iam_addusertogroup ? {
    start_user_name              = module.single_account_privesc_self_escalation_to_admin_iam_013_iam_addusertogroup[0].start_user_name
    start_user_arn               = module.single_account_privesc_self_escalation_to_admin_iam_013_iam_addusertogroup[0].start_user_arn
    start_user_access_key_id     = module.single_account_privesc_self_escalation_to_admin_iam_013_iam_addusertogroup[0].start_user_access_key_id
    start_user_secret_access_key = module.single_account_privesc_self_escalation_to_admin_iam_013_iam_addusertogroup[0].start_user_secret_access_key
    admin_group_name             = module.single_account_privesc_self_escalation_to_admin_iam_013_iam_addusertogroup[0].admin_group_name
    admin_group_arn              = module.single_account_privesc_self_escalation_to_admin_iam_013_iam_addusertogroup[0].admin_group_arn
    attack_path                  = module.single_account_privesc_self_escalation_to_admin_iam_013_iam_addusertogroup[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_self_escalation_to_admin_iam_010_iam_attachgrouppolicy" {
  description = "All outputs for iam-010-iam-attachgrouppolicy self-escalation scenario"
  value = var.enable_single_account_privesc_self_escalation_to_admin_iam_010_iam_attachgrouppolicy ? {
    starting_user_name              = module.single_account_privesc_self_escalation_to_admin_iam_010_iam_attachgrouppolicy[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_self_escalation_to_admin_iam_010_iam_attachgrouppolicy[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_self_escalation_to_admin_iam_010_iam_attachgrouppolicy[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_self_escalation_to_admin_iam_010_iam_attachgrouppolicy[0].starting_user_secret_access_key
    group_name                      = module.single_account_privesc_self_escalation_to_admin_iam_010_iam_attachgrouppolicy[0].group_name
    group_arn                       = module.single_account_privesc_self_escalation_to_admin_iam_010_iam_attachgrouppolicy[0].group_arn
    attack_path                     = module.single_account_privesc_self_escalation_to_admin_iam_010_iam_attachgrouppolicy[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_self_escalation_to_admin_iam_011_iam_putgrouppolicy" {
  description = "All outputs for iam-011-iam-putgrouppolicy self-escalation scenario"
  value = var.enable_single_account_privesc_self_escalation_to_admin_iam_011_iam_putgrouppolicy ? {
    privesc_user_name              = module.single_account_privesc_self_escalation_to_admin_iam_011_iam_putgrouppolicy[0].privesc_user_name
    privesc_user_arn               = module.single_account_privesc_self_escalation_to_admin_iam_011_iam_putgrouppolicy[0].privesc_user_arn
    privesc_user_access_key_id     = module.single_account_privesc_self_escalation_to_admin_iam_011_iam_putgrouppolicy[0].privesc_user_access_key_id
    privesc_user_secret_access_key = module.single_account_privesc_self_escalation_to_admin_iam_011_iam_putgrouppolicy[0].privesc_user_secret_access_key
    target_group_name              = module.single_account_privesc_self_escalation_to_admin_iam_011_iam_putgrouppolicy[0].target_group_name
    target_group_arn               = module.single_account_privesc_self_escalation_to_admin_iam_011_iam_putgrouppolicy[0].target_group_arn
    attack_path                    = module.single_account_privesc_self_escalation_to_admin_iam_011_iam_putgrouppolicy[0].attack_path
  } : null
  sensitive = true
}

# One-hop to-admin scenarios
output "single_account_privesc_one_hop_to_admin_iam_019_iam_attachrolepolicy_iam_updateassumerolepolicy" {
  description = "All outputs for iam-019-iam-attachrolepolicy+iam-updateassumerolepolicy one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_019_iam_attachrolepolicy_iam_updateassumerolepolicy ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_019_iam_attachrolepolicy_iam_updateassumerolepolicy[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_019_iam_attachrolepolicy_iam_updateassumerolepolicy[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_019_iam_attachrolepolicy_iam_updateassumerolepolicy[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_019_iam_attachrolepolicy_iam_updateassumerolepolicy[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_iam_019_iam_attachrolepolicy_iam_updateassumerolepolicy[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_iam_019_iam_attachrolepolicy_iam_updateassumerolepolicy[0].target_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_019_iam_attachrolepolicy_iam_updateassumerolepolicy[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_014_iam_attachrolepolicy_sts_assumerole" {
  description = "All outputs for iam-014-iam-attachrolepolicy+sts-assumerole one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_014_iam_attachrolepolicy_sts_assumerole ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_014_iam_attachrolepolicy_sts_assumerole[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_014_iam_attachrolepolicy_sts_assumerole[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_014_iam_attachrolepolicy_sts_assumerole[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_014_iam_attachrolepolicy_sts_assumerole[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_iam_014_iam_attachrolepolicy_sts_assumerole[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_iam_014_iam_attachrolepolicy_sts_assumerole[0].target_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_014_iam_attachrolepolicy_sts_assumerole[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_015_iam_attachuserpolicy_iam_createaccesskey" {
  description = "All outputs for iam-015-iam-attachuserpolicy+iam-createaccesskey one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_015_iam_attachuserpolicy_iam_createaccesskey ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_015_iam_attachuserpolicy_iam_createaccesskey[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_015_iam_attachuserpolicy_iam_createaccesskey[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_015_iam_attachuserpolicy_iam_createaccesskey[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_015_iam_attachuserpolicy_iam_createaccesskey[0].starting_user_secret_access_key
    target_user_name                = module.single_account_privesc_one_hop_to_admin_iam_015_iam_attachuserpolicy_iam_createaccesskey[0].target_user_name
    target_user_arn                 = module.single_account_privesc_one_hop_to_admin_iam_015_iam_attachuserpolicy_iam_createaccesskey[0].target_user_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_015_iam_attachuserpolicy_iam_createaccesskey[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_apprunner_002_apprunner_updateservice" {
  description = "All outputs for apprunner-002-apprunner-updateservice one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_apprunner_002_apprunner_updateservice ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_apprunner_002_apprunner_updateservice[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_apprunner_002_apprunner_updateservice[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_apprunner_002_apprunner_updateservice[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_apprunner_002_apprunner_updateservice[0].starting_user_secret_access_key
    target_service_name             = module.single_account_privesc_one_hop_to_admin_apprunner_002_apprunner_updateservice[0].target_service_name
    target_service_arn              = module.single_account_privesc_one_hop_to_admin_apprunner_002_apprunner_updateservice[0].target_service_arn
    target_role_name                = module.single_account_privesc_one_hop_to_admin_apprunner_002_apprunner_updateservice[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_apprunner_002_apprunner_updateservice[0].target_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_apprunner_002_apprunner_updateservice[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_012_iam_updateassumerolepolicy" {
  description = "All outputs for iam-012-iam-updateassumerolepolicy one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_012_iam_updateassumerolepolicy ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_012_iam_updateassumerolepolicy[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_012_iam_updateassumerolepolicy[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_012_iam_updateassumerolepolicy[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_012_iam_updateassumerolepolicy[0].starting_user_secret_access_key
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_iam_012_iam_updateassumerolepolicy[0].target_role_arn
    target_role_name                = module.single_account_privesc_one_hop_to_admin_iam_012_iam_updateassumerolepolicy[0].target_role_name
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_012_iam_updateassumerolepolicy[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_004_iam_createloginprofile" {
  description = "All outputs for iam-004-iam-createloginprofile one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_004_iam_createloginprofile ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_004_iam_createloginprofile[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_004_iam_createloginprofile[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_004_iam_createloginprofile[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_004_iam_createloginprofile[0].starting_user_secret_access_key
    starting_role_arn               = module.single_account_privesc_one_hop_to_admin_iam_004_iam_createloginprofile[0].starting_role_arn
    starting_role_name              = module.single_account_privesc_one_hop_to_admin_iam_004_iam_createloginprofile[0].starting_role_name
    admin_user_arn                  = module.single_account_privesc_one_hop_to_admin_iam_004_iam_createloginprofile[0].admin_user_arn
    admin_user_name                 = module.single_account_privesc_one_hop_to_admin_iam_004_iam_createloginprofile[0].admin_user_name
    admin_access_key_id             = module.single_account_privesc_one_hop_to_admin_iam_004_iam_createloginprofile[0].admin_access_key_id
    admin_secret_access_key         = module.single_account_privesc_one_hop_to_admin_iam_004_iam_createloginprofile[0].admin_secret_access_key
    console_login_url               = module.single_account_privesc_one_hop_to_admin_iam_004_iam_createloginprofile[0].console_login_url
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_004_iam_createloginprofile[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_020_iam_createpolicyversion_iam_updateassumerolepolicy" {
  description = "All outputs for iam-020-iam-createpolicyversion+iam-updateassumerolepolicy one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_020_iam_createpolicyversion_iam_updateassumerolepolicy ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_020_iam_createpolicyversion_iam_updateassumerolepolicy[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_020_iam_createpolicyversion_iam_updateassumerolepolicy[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_020_iam_createpolicyversion_iam_updateassumerolepolicy[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_020_iam_createpolicyversion_iam_updateassumerolepolicy[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_iam_020_iam_createpolicyversion_iam_updateassumerolepolicy[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_iam_020_iam_createpolicyversion_iam_updateassumerolepolicy[0].target_role_arn
    target_policy_name              = module.single_account_privesc_one_hop_to_admin_iam_020_iam_createpolicyversion_iam_updateassumerolepolicy[0].target_policy_name
    target_policy_arn               = module.single_account_privesc_one_hop_to_admin_iam_020_iam_createpolicyversion_iam_updateassumerolepolicy[0].target_policy_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_020_iam_createpolicyversion_iam_updateassumerolepolicy[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_016_iam_createpolicyversion_sts_assumerole" {
  description = "All outputs for iam-016-iam-createpolicyversion+sts-assumerole one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_016_iam_createpolicyversion_sts_assumerole ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_016_iam_createpolicyversion_sts_assumerole[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_016_iam_createpolicyversion_sts_assumerole[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_016_iam_createpolicyversion_sts_assumerole[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_016_iam_createpolicyversion_sts_assumerole[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_iam_016_iam_createpolicyversion_sts_assumerole[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_iam_016_iam_createpolicyversion_sts_assumerole[0].target_role_arn
    target_policy_name              = module.single_account_privesc_one_hop_to_admin_iam_016_iam_createpolicyversion_sts_assumerole[0].target_policy_name
    target_policy_arn               = module.single_account_privesc_one_hop_to_admin_iam_016_iam_createpolicyversion_sts_assumerole[0].target_policy_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_016_iam_createpolicyversion_sts_assumerole[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_006_iam_updateloginprofile" {
  description = "All outputs for iam-006-iam-updateloginprofile one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_006_iam_updateloginprofile ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_006_iam_updateloginprofile[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_006_iam_updateloginprofile[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_006_iam_updateloginprofile[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_006_iam_updateloginprofile[0].starting_user_secret_access_key
    admin_user_arn                  = module.single_account_privesc_one_hop_to_admin_iam_006_iam_updateloginprofile[0].admin_user_arn
    admin_user_name                 = module.single_account_privesc_one_hop_to_admin_iam_006_iam_updateloginprofile[0].admin_user_name
    original_password               = module.single_account_privesc_one_hop_to_admin_iam_006_iam_updateloginprofile[0].original_password
    console_login_url               = module.single_account_privesc_one_hop_to_admin_iam_006_iam_updateloginprofile[0].console_login_url
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_006_iam_updateloginprofile[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_sts_001_sts_assumerole" {
  description = "All outputs for sts-001-sts-assumerole one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_sts_001_sts_assumerole ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_sts_001_sts_assumerole[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_sts_001_sts_assumerole[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_sts_001_sts_assumerole[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_sts_001_sts_assumerole[0].starting_user_secret_access_key
    admin_role_arn                  = module.single_account_privesc_one_hop_to_admin_sts_001_sts_assumerole[0].admin_role_arn
    admin_role_name                 = module.single_account_privesc_one_hop_to_admin_sts_001_sts_assumerole[0].admin_role_name
    attack_path                     = module.single_account_privesc_one_hop_to_admin_sts_001_sts_assumerole[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_002_iam_createaccesskey" {
  description = "All outputs for iam-002-iam-createaccesskey one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_002_iam_createaccesskey ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_002_iam_createaccesskey[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_002_iam_createaccesskey[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_002_iam_createaccesskey[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_002_iam_createaccesskey[0].starting_user_secret_access_key
    admin_user_name                 = module.single_account_privesc_one_hop_to_admin_iam_002_iam_createaccesskey[0].admin_user_name
    admin_user_arn                  = module.single_account_privesc_one_hop_to_admin_iam_002_iam_createaccesskey[0].admin_user_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_002_iam_createaccesskey[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_003_iam_deleteaccesskey_createaccesskey" {
  description = "All outputs for iam-003-iam-deleteaccesskey+createaccesskey one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_003_iam_deleteaccesskey_createaccesskey ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_003_iam_deleteaccesskey_createaccesskey[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_003_iam_deleteaccesskey_createaccesskey[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_003_iam_deleteaccesskey_createaccesskey[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_003_iam_deleteaccesskey_createaccesskey[0].starting_user_secret_access_key
    admin_user_name                 = module.single_account_privesc_one_hop_to_admin_iam_003_iam_deleteaccesskey_createaccesskey[0].admin_user_name
    admin_user_arn                  = module.single_account_privesc_one_hop_to_admin_iam_003_iam_deleteaccesskey_createaccesskey[0].admin_user_arn
    admin_user_existing_key_1_id    = module.single_account_privesc_one_hop_to_admin_iam_003_iam_deleteaccesskey_createaccesskey[0].admin_user_existing_key_1_id
    admin_user_existing_key_2_id    = module.single_account_privesc_one_hop_to_admin_iam_003_iam_deleteaccesskey_createaccesskey[0].admin_user_existing_key_2_id
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_003_iam_deleteaccesskey_createaccesskey[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_apprunner_001_iam_passrole_apprunner_createservice" {
  description = "All outputs for apprunner-001-iam-passrole+apprunner-createservice one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_apprunner_001_iam_passrole_apprunner_createservice ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_apprunner_001_iam_passrole_apprunner_createservice[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_apprunner_001_iam_passrole_apprunner_createservice[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_apprunner_001_iam_passrole_apprunner_createservice[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_apprunner_001_iam_passrole_apprunner_createservice[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_apprunner_001_iam_passrole_apprunner_createservice[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_apprunner_001_iam_passrole_apprunner_createservice[0].target_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_apprunner_001_iam_passrole_apprunner_createservice[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_bedrock_001_iam_passrole_bedrockagentcore_codeinterpreter" {
  description = "All outputs for iam-passrole+bedrockagentcore-codeinterpreter one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_bedrock_001_iam_passrole_bedrockagentcore_codeinterpreter ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_bedrock_001_iam_passrole_bedrockagentcore_codeinterpreter[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_bedrock_001_iam_passrole_bedrockagentcore_codeinterpreter[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_bedrock_001_iam_passrole_bedrockagentcore_codeinterpreter[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_bedrock_001_iam_passrole_bedrockagentcore_codeinterpreter[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_bedrock_001_iam_passrole_bedrockagentcore_codeinterpreter[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_bedrock_001_iam_passrole_bedrockagentcore_codeinterpreter[0].target_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_bedrock_001_iam_passrole_bedrockagentcore_codeinterpreter[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_bedrock_002_bedrockagentcore_startsession_invoke" {
  description = "All outputs for bedrock-002-bedrockagentcore-startsession+invoke one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_bedrock_002_bedrockagentcore_startsession_invoke ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_bedrock_002_bedrockagentcore_startsession_invoke[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_bedrock_002_bedrockagentcore_startsession_invoke[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_bedrock_002_bedrockagentcore_startsession_invoke[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_bedrock_002_bedrockagentcore_startsession_invoke[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_bedrock_002_bedrockagentcore_startsession_invoke[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_bedrock_002_bedrockagentcore_startsession_invoke[0].target_role_arn
    existing_interpreter_id         = module.single_account_privesc_one_hop_to_admin_bedrock_002_bedrockagentcore_startsession_invoke[0].existing_interpreter_id
    existing_interpreter_arn        = module.single_account_privesc_one_hop_to_admin_bedrock_002_bedrockagentcore_startsession_invoke[0].existing_interpreter_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_bedrock_002_bedrockagentcore_startsession_invoke[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_ec2_001_iam_passrole_ec2_runinstances" {
  description = "All outputs for ec2-001-iam-passrole+ec2-runinstances one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_ec2_001_iam_passrole_ec2_runinstances ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_ec2_001_iam_passrole_ec2_runinstances[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_ec2_001_iam_passrole_ec2_runinstances[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_ec2_001_iam_passrole_ec2_runinstances[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_ec2_001_iam_passrole_ec2_runinstances[0].starting_user_secret_access_key
    admin_role_arn                  = module.single_account_privesc_one_hop_to_admin_ec2_001_iam_passrole_ec2_runinstances[0].admin_role_arn
    admin_role_name                 = module.single_account_privesc_one_hop_to_admin_ec2_001_iam_passrole_ec2_runinstances[0].admin_role_name
    instance_profile_arn            = module.single_account_privesc_one_hop_to_admin_ec2_001_iam_passrole_ec2_runinstances[0].instance_profile_arn
    instance_profile_name           = module.single_account_privesc_one_hop_to_admin_ec2_001_iam_passrole_ec2_runinstances[0].instance_profile_name
    security_group_id               = module.single_account_privesc_one_hop_to_admin_ec2_001_iam_passrole_ec2_runinstances[0].security_group_id
    default_subnet_id               = module.single_account_privesc_one_hop_to_admin_ec2_001_iam_passrole_ec2_runinstances[0].default_subnet_id
    ami_id                          = module.single_account_privesc_one_hop_to_admin_ec2_001_iam_passrole_ec2_runinstances[0].ami_id
    attack_path                     = module.single_account_privesc_one_hop_to_admin_ec2_001_iam_passrole_ec2_runinstances[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_ec2_004_iam_passrole_ec2_requestspotinstances" {
  description = "All outputs for ec2-004-iam-passrole+ec2-requestspotinstances one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_ec2_004_iam_passrole_ec2_requestspotinstances ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_ec2_004_iam_passrole_ec2_requestspotinstances[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_ec2_004_iam_passrole_ec2_requestspotinstances[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_ec2_004_iam_passrole_ec2_requestspotinstances[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_ec2_004_iam_passrole_ec2_requestspotinstances[0].starting_user_secret_access_key
    admin_role_arn                  = module.single_account_privesc_one_hop_to_admin_ec2_004_iam_passrole_ec2_requestspotinstances[0].admin_role_arn
    admin_role_name                 = module.single_account_privesc_one_hop_to_admin_ec2_004_iam_passrole_ec2_requestspotinstances[0].admin_role_name
    instance_profile_arn            = module.single_account_privesc_one_hop_to_admin_ec2_004_iam_passrole_ec2_requestspotinstances[0].instance_profile_arn
    instance_profile_name           = module.single_account_privesc_one_hop_to_admin_ec2_004_iam_passrole_ec2_requestspotinstances[0].instance_profile_name
    security_group_id               = module.single_account_privesc_one_hop_to_admin_ec2_004_iam_passrole_ec2_requestspotinstances[0].security_group_id
    default_subnet_id               = module.single_account_privesc_one_hop_to_admin_ec2_004_iam_passrole_ec2_requestspotinstances[0].default_subnet_id
    ami_id                          = module.single_account_privesc_one_hop_to_admin_ec2_004_iam_passrole_ec2_requestspotinstances[0].ami_id
    attack_path                     = module.single_account_privesc_one_hop_to_admin_ec2_004_iam_passrole_ec2_requestspotinstances[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate" {
  description = "All outputs for ec2-005 → ec2-createlaunchtemplateversion+ec2-modifylaunchtemplate one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate ? {
    starting_user_name                    = module.single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate[0].starting_user_name
    starting_user_arn                     = module.single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate[0].starting_user_arn
    starting_user_access_key_id           = module.single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate[0].starting_user_access_key_id
    starting_user_secret_access_key       = module.single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate[0].starting_user_secret_access_key
    lowpriv_role_arn                      = module.single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate[0].lowpriv_role_arn
    lowpriv_role_name                     = module.single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate[0].lowpriv_role_name
    lowpriv_instance_profile_arn          = module.single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate[0].lowpriv_instance_profile_arn
    target_admin_role_arn                 = module.single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate[0].target_admin_role_arn
    target_admin_role_name                = module.single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate[0].target_admin_role_name
    target_admin_instance_profile_arn     = module.single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate[0].target_admin_instance_profile_arn
    target_admin_instance_profile_name    = module.single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate[0].target_admin_instance_profile_name
    victim_launch_template_id             = module.single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate[0].victim_launch_template_id
    victim_launch_template_name           = module.single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate[0].victim_launch_template_name
    victim_launch_template_latest_version = module.single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate[0].victim_launch_template_latest_version
    victim_asg_name                       = module.single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate[0].victim_asg_name
    victim_security_group_id              = module.single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate[0].victim_security_group_id
    attack_path                           = module.single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_ecs_002_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_runtask" {
  description = "All outputs for ecs-002-iam-passrole+ecs-createcluster+ecs-registertaskdefinition+ecs-runtask one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_ecs_002_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_runtask ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_ecs_002_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_runtask[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_ecs_002_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_runtask[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_ecs_002_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_runtask[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_ecs_002_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_runtask[0].starting_user_secret_access_key
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_ecs_002_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_runtask[0].target_role_arn
    target_role_name                = module.single_account_privesc_one_hop_to_admin_ecs_002_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_runtask[0].target_role_name
    account_id                      = module.single_account_privesc_one_hop_to_admin_ecs_002_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_runtask[0].account_id
    attack_path                     = module.single_account_privesc_one_hop_to_admin_ecs_002_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_runtask[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_ecs_004_iam_passrole_ecs_registertaskdefinition_ecs_runtask" {
  description = "All outputs for iam-passrole+ecs-registertaskdefinition+ecs-runtask one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_ecs_004_iam_passrole_ecs_registertaskdefinition_ecs_runtask ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_ecs_004_iam_passrole_ecs_registertaskdefinition_ecs_runtask[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_ecs_004_iam_passrole_ecs_registertaskdefinition_ecs_runtask[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_ecs_004_iam_passrole_ecs_registertaskdefinition_ecs_runtask[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_ecs_004_iam_passrole_ecs_registertaskdefinition_ecs_runtask[0].starting_user_secret_access_key
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_ecs_004_iam_passrole_ecs_registertaskdefinition_ecs_runtask[0].target_role_arn
    target_role_name                = module.single_account_privesc_one_hop_to_admin_ecs_004_iam_passrole_ecs_registertaskdefinition_ecs_runtask[0].target_role_name
    ecs_cluster_name                = module.single_account_privesc_one_hop_to_admin_ecs_004_iam_passrole_ecs_registertaskdefinition_ecs_runtask[0].ecs_cluster_name
    ecs_cluster_arn                 = module.single_account_privesc_one_hop_to_admin_ecs_004_iam_passrole_ecs_registertaskdefinition_ecs_runtask[0].ecs_cluster_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_ecs_004_iam_passrole_ecs_registertaskdefinition_ecs_runtask[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_ecs_005_iam_passrole_ecs_registertaskdefinition_ecs_starttask" {
  description = "All outputs for ecs-005-iam-passrole+ecs-registertaskdefinition+ecs-starttask one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_ecs_005_iam_passrole_ecs_registertaskdefinition_ecs_starttask ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_ecs_005_iam_passrole_ecs_registertaskdefinition_ecs_starttask[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_ecs_005_iam_passrole_ecs_registertaskdefinition_ecs_starttask[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_ecs_005_iam_passrole_ecs_registertaskdefinition_ecs_starttask[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_ecs_005_iam_passrole_ecs_registertaskdefinition_ecs_starttask[0].starting_user_secret_access_key
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_ecs_005_iam_passrole_ecs_registertaskdefinition_ecs_starttask[0].target_role_arn
    target_role_name                = module.single_account_privesc_one_hop_to_admin_ecs_005_iam_passrole_ecs_registertaskdefinition_ecs_starttask[0].target_role_name
    ecs_cluster_name                = module.single_account_privesc_one_hop_to_admin_ecs_005_iam_passrole_ecs_registertaskdefinition_ecs_starttask[0].ecs_cluster_name
    ecs_cluster_arn                 = module.single_account_privesc_one_hop_to_admin_ecs_005_iam_passrole_ecs_registertaskdefinition_ecs_starttask[0].ecs_cluster_arn
    container_instance_id           = module.single_account_privesc_one_hop_to_admin_ecs_005_iam_passrole_ecs_registertaskdefinition_ecs_starttask[0].container_instance_id
    container_instance_arn          = module.single_account_privesc_one_hop_to_admin_ecs_005_iam_passrole_ecs_registertaskdefinition_ecs_starttask[0].container_instance_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_ecs_005_iam_passrole_ecs_registertaskdefinition_ecs_starttask[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_ecs_003_iam_passrole_ecs_registertaskdefinition_ecs_createservice" {
  description = "All outputs for ecs-003-iam-passrole+ecs-registertaskdefinition+ecs-createservice one-hop to-admin scenario [Path ID: ecs-003]"
  value = var.enable_single_account_privesc_one_hop_to_admin_ecs_003_iam_passrole_ecs_registertaskdefinition_ecs_createservice ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_ecs_003_iam_passrole_ecs_registertaskdefinition_ecs_createservice[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_ecs_003_iam_passrole_ecs_registertaskdefinition_ecs_createservice[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_ecs_003_iam_passrole_ecs_registertaskdefinition_ecs_createservice[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_ecs_003_iam_passrole_ecs_registertaskdefinition_ecs_createservice[0].starting_user_secret_access_key
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_ecs_003_iam_passrole_ecs_registertaskdefinition_ecs_createservice[0].target_role_arn
    target_role_name                = module.single_account_privesc_one_hop_to_admin_ecs_003_iam_passrole_ecs_registertaskdefinition_ecs_createservice[0].target_role_name
    ecs_cluster_name                = module.single_account_privesc_one_hop_to_admin_ecs_003_iam_passrole_ecs_registertaskdefinition_ecs_createservice[0].ecs_cluster_name
    ecs_cluster_arn                 = module.single_account_privesc_one_hop_to_admin_ecs_003_iam_passrole_ecs_registertaskdefinition_ecs_createservice[0].ecs_cluster_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_ecs_003_iam_passrole_ecs_registertaskdefinition_ecs_createservice[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_ecs_001_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_createservice" {
  description = "All outputs for ecs-001-iam-passrole+ecs-createcluster+ecs-registertaskdefinition+ecs-createservice one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_ecs_001_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_createservice ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_ecs_001_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_createservice[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_ecs_001_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_createservice[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_ecs_001_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_createservice[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_ecs_001_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_createservice[0].starting_user_secret_access_key
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_ecs_001_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_createservice[0].target_role_arn
    target_role_name                = module.single_account_privesc_one_hop_to_admin_ecs_001_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_createservice[0].target_role_name
    attack_path                     = module.single_account_privesc_one_hop_to_admin_ecs_001_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_createservice[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_ecs_006_ecs_executecommand_describetasks" {
  description = "All outputs for ecs-006-ecs-executecommand+describetasks one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_ecs_006_ecs_executecommand_describetasks ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_ecs_006_ecs_executecommand_describetasks[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_ecs_006_ecs_executecommand_describetasks[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_ecs_006_ecs_executecommand_describetasks[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_ecs_006_ecs_executecommand_describetasks[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_ecs_006_ecs_executecommand_describetasks[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_ecs_006_ecs_executecommand_describetasks[0].target_role_arn
    ecs_cluster_name                = module.single_account_privesc_one_hop_to_admin_ecs_006_ecs_executecommand_describetasks[0].ecs_cluster_name
    ecs_cluster_arn                 = module.single_account_privesc_one_hop_to_admin_ecs_006_ecs_executecommand_describetasks[0].ecs_cluster_arn
    ecs_service_name                = module.single_account_privesc_one_hop_to_admin_ecs_006_ecs_executecommand_describetasks[0].ecs_service_name
    attack_path                     = module.single_account_privesc_one_hop_to_admin_ecs_006_ecs_executecommand_describetasks[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_glue_001_iam_passrole_glue_createdevendpoint" {
  description = "All outputs for glue-001-iam-passrole+glue-createdevendpoint one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_glue_001_iam_passrole_glue_createdevendpoint ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_glue_001_iam_passrole_glue_createdevendpoint[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_glue_001_iam_passrole_glue_createdevendpoint[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_glue_001_iam_passrole_glue_createdevendpoint[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_glue_001_iam_passrole_glue_createdevendpoint[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_glue_001_iam_passrole_glue_createdevendpoint[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_glue_001_iam_passrole_glue_createdevendpoint[0].target_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_glue_001_iam_passrole_glue_createdevendpoint[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_glue_002_glue_updatedevendpoint" {
  description = "All outputs for glue-002-glue-updatedevendpoint one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_glue_002_glue_updatedevendpoint ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_glue_002_glue_updatedevendpoint[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_glue_002_glue_updatedevendpoint[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_glue_002_glue_updatedevendpoint[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_glue_002_glue_updatedevendpoint[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_glue_002_glue_updatedevendpoint[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_glue_002_glue_updatedevendpoint[0].target_role_arn
    dev_endpoint_name               = module.single_account_privesc_one_hop_to_admin_glue_002_glue_updatedevendpoint[0].dev_endpoint_name
    dev_endpoint_arn                = module.single_account_privesc_one_hop_to_admin_glue_002_glue_updatedevendpoint[0].dev_endpoint_arn
    dev_endpoint_address            = module.single_account_privesc_one_hop_to_admin_glue_002_glue_updatedevendpoint[0].dev_endpoint_address
    attack_path                     = module.single_account_privesc_one_hop_to_admin_glue_002_glue_updatedevendpoint[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_glue_004_iam_passrole_glue_createjob_glue_createtrigger" {
  description = "All outputs for iam-passrole+glue-createjob+glue-createtrigger one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_glue_004_iam_passrole_glue_createjob_glue_createtrigger ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_glue_004_iam_passrole_glue_createjob_glue_createtrigger[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_glue_004_iam_passrole_glue_createjob_glue_createtrigger[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_glue_004_iam_passrole_glue_createjob_glue_createtrigger[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_glue_004_iam_passrole_glue_createjob_glue_createtrigger[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_glue_004_iam_passrole_glue_createjob_glue_createtrigger[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_glue_004_iam_passrole_glue_createjob_glue_createtrigger[0].target_role_arn
    script_bucket_name              = module.single_account_privesc_one_hop_to_admin_glue_004_iam_passrole_glue_createjob_glue_createtrigger[0].script_bucket_name
    script_s3_path                  = module.single_account_privesc_one_hop_to_admin_glue_004_iam_passrole_glue_createjob_glue_createtrigger[0].script_s3_path
    attack_path                     = module.single_account_privesc_one_hop_to_admin_glue_004_iam_passrole_glue_createjob_glue_createtrigger[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_glue_003_iam_passrole_glue_createjob_glue_startjobrun" {
  description = "All outputs for iam-passrole+glue-createjob+glue-startjobrun one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_glue_003_iam_passrole_glue_createjob_glue_startjobrun ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_glue_003_iam_passrole_glue_createjob_glue_startjobrun[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_glue_003_iam_passrole_glue_createjob_glue_startjobrun[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_glue_003_iam_passrole_glue_createjob_glue_startjobrun[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_glue_003_iam_passrole_glue_createjob_glue_startjobrun[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_glue_003_iam_passrole_glue_createjob_glue_startjobrun[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_glue_003_iam_passrole_glue_createjob_glue_startjobrun[0].target_role_arn
    script_bucket_name              = module.single_account_privesc_one_hop_to_admin_glue_003_iam_passrole_glue_createjob_glue_startjobrun[0].script_bucket_name
    script_s3_path                  = module.single_account_privesc_one_hop_to_admin_glue_003_iam_passrole_glue_createjob_glue_startjobrun[0].script_s3_path
    attack_path                     = module.single_account_privesc_one_hop_to_admin_glue_003_iam_passrole_glue_createjob_glue_startjobrun[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_glue_005_iam_passrole_glue_updatejob_glue_startjobrun" {
  description = "All outputs for iam-passrole+glue-updatejob+glue-startjobrun one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_glue_005_iam_passrole_glue_updatejob_glue_startjobrun ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_glue_005_iam_passrole_glue_updatejob_glue_startjobrun[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_glue_005_iam_passrole_glue_updatejob_glue_startjobrun[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_glue_005_iam_passrole_glue_updatejob_glue_startjobrun[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_glue_005_iam_passrole_glue_updatejob_glue_startjobrun[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_glue_005_iam_passrole_glue_updatejob_glue_startjobrun[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_glue_005_iam_passrole_glue_updatejob_glue_startjobrun[0].target_role_arn
    initial_role_name               = module.single_account_privesc_one_hop_to_admin_glue_005_iam_passrole_glue_updatejob_glue_startjobrun[0].initial_role_name
    initial_role_arn                = module.single_account_privesc_one_hop_to_admin_glue_005_iam_passrole_glue_updatejob_glue_startjobrun[0].initial_role_arn
    glue_job_name                   = module.single_account_privesc_one_hop_to_admin_glue_005_iam_passrole_glue_updatejob_glue_startjobrun[0].glue_job_name
    script_bucket_name              = module.single_account_privesc_one_hop_to_admin_glue_005_iam_passrole_glue_updatejob_glue_startjobrun[0].script_bucket_name
    benign_script_s3_path           = module.single_account_privesc_one_hop_to_admin_glue_005_iam_passrole_glue_updatejob_glue_startjobrun[0].benign_script_s3_path
    malicious_script_s3_path        = module.single_account_privesc_one_hop_to_admin_glue_005_iam_passrole_glue_updatejob_glue_startjobrun[0].malicious_script_s3_path
    attack_path                     = module.single_account_privesc_one_hop_to_admin_glue_005_iam_passrole_glue_updatejob_glue_startjobrun[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_glue_006_iam_passrole_glue_updatejob_glue_createtrigger" {
  description = "All outputs for glue-006-iam-passrole+glue-updatejob+glue-createtrigger one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_glue_006_iam_passrole_glue_updatejob_glue_createtrigger ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_glue_006_iam_passrole_glue_updatejob_glue_createtrigger[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_glue_006_iam_passrole_glue_updatejob_glue_createtrigger[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_glue_006_iam_passrole_glue_updatejob_glue_createtrigger[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_glue_006_iam_passrole_glue_updatejob_glue_createtrigger[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_glue_006_iam_passrole_glue_updatejob_glue_createtrigger[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_glue_006_iam_passrole_glue_updatejob_glue_createtrigger[0].target_role_arn
    initial_role_name               = module.single_account_privesc_one_hop_to_admin_glue_006_iam_passrole_glue_updatejob_glue_createtrigger[0].initial_role_name
    initial_role_arn                = module.single_account_privesc_one_hop_to_admin_glue_006_iam_passrole_glue_updatejob_glue_createtrigger[0].initial_role_arn
    glue_job_name                   = module.single_account_privesc_one_hop_to_admin_glue_006_iam_passrole_glue_updatejob_glue_createtrigger[0].glue_job_name
    script_bucket_name              = module.single_account_privesc_one_hop_to_admin_glue_006_iam_passrole_glue_updatejob_glue_createtrigger[0].script_bucket_name
    benign_script_s3_path           = module.single_account_privesc_one_hop_to_admin_glue_006_iam_passrole_glue_updatejob_glue_createtrigger[0].benign_script_s3_path
    malicious_script_s3_path        = module.single_account_privesc_one_hop_to_admin_glue_006_iam_passrole_glue_updatejob_glue_createtrigger[0].malicious_script_s3_path
    attack_path                     = module.single_account_privesc_one_hop_to_admin_glue_006_iam_passrole_glue_updatejob_glue_createtrigger[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_lambda_006_iam_passrole_lambda_createfunction_lambda_addpermission" {
  description = "All outputs for lambda-006-iam-passrole+lambda-createfunction+lambda-addpermission one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_lambda_006_iam_passrole_lambda_createfunction_lambda_addpermission ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_lambda_006_iam_passrole_lambda_createfunction_lambda_addpermission[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_lambda_006_iam_passrole_lambda_createfunction_lambda_addpermission[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_lambda_006_iam_passrole_lambda_createfunction_lambda_addpermission[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_lambda_006_iam_passrole_lambda_createfunction_lambda_addpermission[0].starting_user_secret_access_key
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_lambda_006_iam_passrole_lambda_createfunction_lambda_addpermission[0].target_role_arn
    target_role_name                = module.single_account_privesc_one_hop_to_admin_lambda_006_iam_passrole_lambda_createfunction_lambda_addpermission[0].target_role_name
    attack_path                     = module.single_account_privesc_one_hop_to_admin_lambda_006_iam_passrole_lambda_createfunction_lambda_addpermission[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_lambda_001_iam_passrole_lambda_createfunction_lambda_invokefunction" {
  description = "All outputs for lambda-001-iam-passrole+lambda-createfunction+lambda-invokefunction one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_lambda_001_iam_passrole_lambda_createfunction_lambda_invokefunction ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_lambda_001_iam_passrole_lambda_createfunction_lambda_invokefunction[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_lambda_001_iam_passrole_lambda_createfunction_lambda_invokefunction[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_lambda_001_iam_passrole_lambda_createfunction_lambda_invokefunction[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_lambda_001_iam_passrole_lambda_createfunction_lambda_invokefunction[0].starting_user_secret_access_key
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_lambda_001_iam_passrole_lambda_createfunction_lambda_invokefunction[0].target_role_arn
    target_role_name                = module.single_account_privesc_one_hop_to_admin_lambda_001_iam_passrole_lambda_createfunction_lambda_invokefunction[0].target_role_name
    attack_path                     = module.single_account_privesc_one_hop_to_admin_lambda_001_iam_passrole_lambda_createfunction_lambda_invokefunction[0].attack_path
  } : null
  sensitive = true
}

# Self-escalation to-bucket scenarios
output "single_account_privesc_self_escalation_to_bucket_iam_005_iam_putrolepolicy" {
  description = "All outputs for iam-005 (iam-putrolepolicy) self-escalation to-bucket scenario"
  value = var.enable_single_account_privesc_self_escalation_to_bucket_iam_005_iam_putrolepolicy ? {
    starting_user_name              = module.single_account_privesc_self_escalation_to_bucket_iam_005_iam_putrolepolicy[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_self_escalation_to_bucket_iam_005_iam_putrolepolicy[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_self_escalation_to_bucket_iam_005_iam_putrolepolicy[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_self_escalation_to_bucket_iam_005_iam_putrolepolicy[0].starting_user_secret_access_key
    starting_role_arn               = module.single_account_privesc_self_escalation_to_bucket_iam_005_iam_putrolepolicy[0].starting_role_arn
    starting_role_name              = module.single_account_privesc_self_escalation_to_bucket_iam_005_iam_putrolepolicy[0].starting_role_name
    target_role_arn                 = module.single_account_privesc_self_escalation_to_bucket_iam_005_iam_putrolepolicy[0].target_role_arn
    target_role_name                = module.single_account_privesc_self_escalation_to_bucket_iam_005_iam_putrolepolicy[0].target_role_name
    bucket_name                     = module.single_account_privesc_self_escalation_to_bucket_iam_005_iam_putrolepolicy[0].bucket_name
    bucket_arn                      = module.single_account_privesc_self_escalation_to_bucket_iam_005_iam_putrolepolicy[0].bucket_arn
    attack_path                     = module.single_account_privesc_self_escalation_to_bucket_iam_005_iam_putrolepolicy[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_self_escalation_to_bucket_iam_009_iam_attachrolepolicy" {
  description = "All outputs for iam-009-iam-attachrolepolicy self-escalation to-bucket scenario"
  value = var.enable_single_account_privesc_self_escalation_to_bucket_iam_009_iam_attachrolepolicy ? {
    starting_user_name              = module.single_account_privesc_self_escalation_to_bucket_iam_009_iam_attachrolepolicy[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_self_escalation_to_bucket_iam_009_iam_attachrolepolicy[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_self_escalation_to_bucket_iam_009_iam_attachrolepolicy[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_self_escalation_to_bucket_iam_009_iam_attachrolepolicy[0].starting_user_secret_access_key
    starting_role_arn               = module.single_account_privesc_self_escalation_to_bucket_iam_009_iam_attachrolepolicy[0].starting_role_arn
    starting_role_name              = module.single_account_privesc_self_escalation_to_bucket_iam_009_iam_attachrolepolicy[0].starting_role_name
    bucket_name                     = module.single_account_privesc_self_escalation_to_bucket_iam_009_iam_attachrolepolicy[0].bucket_name
    bucket_arn                      = module.single_account_privesc_self_escalation_to_bucket_iam_009_iam_attachrolepolicy[0].bucket_arn
    bucket_access_policy_arn        = module.single_account_privesc_self_escalation_to_bucket_iam_009_iam_attachrolepolicy[0].bucket_access_policy_arn
    attack_path                     = module.single_account_privesc_self_escalation_to_bucket_iam_009_iam_attachrolepolicy[0].attack_path
  } : null
  sensitive = true
}

# One-hop to-bucket scenarios
output "single_account_privesc_one_hop_to_bucket_iam_012_iam_updateassumerolepolicy" {
  description = "All outputs for iam-012-iam-updateassumerolepolicy one-hop to-bucket scenario"
  value = var.enable_single_account_privesc_one_hop_to_bucket_iam_012_iam_updateassumerolepolicy ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_bucket_iam_012_iam_updateassumerolepolicy[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_bucket_iam_012_iam_updateassumerolepolicy[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_bucket_iam_012_iam_updateassumerolepolicy[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_bucket_iam_012_iam_updateassumerolepolicy[0].starting_user_secret_access_key
    starting_role_arn               = module.single_account_privesc_one_hop_to_bucket_iam_012_iam_updateassumerolepolicy[0].starting_role_arn
    starting_role_name              = module.single_account_privesc_one_hop_to_bucket_iam_012_iam_updateassumerolepolicy[0].starting_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_bucket_iam_012_iam_updateassumerolepolicy[0].target_role_arn
    target_role_name                = module.single_account_privesc_one_hop_to_bucket_iam_012_iam_updateassumerolepolicy[0].target_role_name
    bucket_name                     = module.single_account_privesc_one_hop_to_bucket_iam_012_iam_updateassumerolepolicy[0].bucket_name
    bucket_arn                      = module.single_account_privesc_one_hop_to_bucket_iam_012_iam_updateassumerolepolicy[0].bucket_arn
    attack_path                     = module.single_account_privesc_one_hop_to_bucket_iam_012_iam_updateassumerolepolicy[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_cloudformation_005_cloudformation_createchangeset_executechangeset" {
  description = "All outputs for cloudformation-005-cloudformation-createchangeset+executechangeset one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_cloudformation_005_cloudformation_createchangeset_executechangeset ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_cloudformation_005_cloudformation_createchangeset_executechangeset[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_cloudformation_005_cloudformation_createchangeset_executechangeset[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_cloudformation_005_cloudformation_createchangeset_executechangeset[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_cloudformation_005_cloudformation_createchangeset_executechangeset[0].starting_user_secret_access_key
    stack_name                      = module.single_account_privesc_one_hop_to_admin_cloudformation_005_cloudformation_createchangeset_executechangeset[0].stack_name
    stack_role_arn                  = module.single_account_privesc_one_hop_to_admin_cloudformation_005_cloudformation_createchangeset_executechangeset[0].stack_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_cloudformation_005_cloudformation_createchangeset_executechangeset[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_cloudformation_002_cloudformation_updatestack" {
  description = "All outputs for cloudformation-002-cloudformation-updatestack one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_cloudformation_002_cloudformation_updatestack ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_cloudformation_002_cloudformation_updatestack[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_cloudformation_002_cloudformation_updatestack[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_cloudformation_002_cloudformation_updatestack[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_cloudformation_002_cloudformation_updatestack[0].starting_user_secret_access_key
    stack_name                      = module.single_account_privesc_one_hop_to_admin_cloudformation_002_cloudformation_updatestack[0].stack_name
    stack_role_arn                  = module.single_account_privesc_one_hop_to_admin_cloudformation_002_cloudformation_updatestack[0].stack_role_arn
    escalated_role_name             = module.single_account_privesc_one_hop_to_admin_cloudformation_002_cloudformation_updatestack[0].escalated_role_name
    attack_path                     = module.single_account_privesc_one_hop_to_admin_cloudformation_002_cloudformation_updatestack[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_cloudformation_004_iam_passrole_cloudformation_updatestackset" {
  description = "All outputs for cloudformation-004-iam-passrole+cloudformation-updatestackset one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_cloudformation_004_iam_passrole_cloudformation_updatestackset ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_cloudformation_004_iam_passrole_cloudformation_updatestackset[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_cloudformation_004_iam_passrole_cloudformation_updatestackset[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_cloudformation_004_iam_passrole_cloudformation_updatestackset[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_cloudformation_004_iam_passrole_cloudformation_updatestackset[0].starting_user_secret_access_key
    stackset_name                   = module.single_account_privesc_one_hop_to_admin_cloudformation_004_iam_passrole_cloudformation_updatestackset[0].stackset_name
    stackset_id                     = module.single_account_privesc_one_hop_to_admin_cloudformation_004_iam_passrole_cloudformation_updatestackset[0].stackset_id
    execution_role_name             = module.single_account_privesc_one_hop_to_admin_cloudformation_004_iam_passrole_cloudformation_updatestackset[0].execution_role_name
    execution_role_arn              = module.single_account_privesc_one_hop_to_admin_cloudformation_004_iam_passrole_cloudformation_updatestackset[0].execution_role_arn
    administration_role_name        = module.single_account_privesc_one_hop_to_admin_cloudformation_004_iam_passrole_cloudformation_updatestackset[0].administration_role_name
    administration_role_arn         = module.single_account_privesc_one_hop_to_admin_cloudformation_004_iam_passrole_cloudformation_updatestackset[0].administration_role_arn
    escalated_role_name             = module.single_account_privesc_one_hop_to_admin_cloudformation_004_iam_passrole_cloudformation_updatestackset[0].escalated_role_name
    attack_path                     = module.single_account_privesc_one_hop_to_admin_cloudformation_004_iam_passrole_cloudformation_updatestackset[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_cloudformation_001_iam_passrole_cloudformation" {
  description = "All outputs for cloudformation-001-iam-passrole-cloudformation one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_cloudformation_001_iam_passrole_cloudformation ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_cloudformation_001_iam_passrole_cloudformation[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_cloudformation_001_iam_passrole_cloudformation[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_cloudformation_001_iam_passrole_cloudformation[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_cloudformation_001_iam_passrole_cloudformation[0].starting_user_secret_access_key
    admin_role_arn                  = module.single_account_privesc_one_hop_to_admin_cloudformation_001_iam_passrole_cloudformation[0].admin_role_arn
    admin_role_name                 = module.single_account_privesc_one_hop_to_admin_cloudformation_001_iam_passrole_cloudformation[0].admin_role_name
    escalated_role_name             = module.single_account_privesc_one_hop_to_admin_cloudformation_001_iam_passrole_cloudformation[0].escalated_role_name
    attack_path                     = module.single_account_privesc_one_hop_to_admin_cloudformation_001_iam_passrole_cloudformation[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_cloudformation_003_iam_passrole_cloudformation_createstackset_cloudformation_createstackinstances" {
  description = "All outputs for cloudformation-003-iam-passrole+cloudformation-createstackset+cloudformation-createstackinstances one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_cloudformation_003_iam_passrole_cloudformation_createstackset_cloudformation_createstackinstances ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_cloudformation_003_iam_passrole_cloudformation_createstackset_cloudformation_createstackinstances[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_cloudformation_003_iam_passrole_cloudformation_createstackset_cloudformation_createstackinstances[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_cloudformation_003_iam_passrole_cloudformation_createstackset_cloudformation_createstackinstances[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_cloudformation_003_iam_passrole_cloudformation_createstackset_cloudformation_createstackinstances[0].starting_user_secret_access_key
    execution_role_arn              = module.single_account_privesc_one_hop_to_admin_cloudformation_003_iam_passrole_cloudformation_createstackset_cloudformation_createstackinstances[0].execution_role_arn
    execution_role_name             = module.single_account_privesc_one_hop_to_admin_cloudformation_003_iam_passrole_cloudformation_createstackset_cloudformation_createstackinstances[0].execution_role_name
    administration_role_arn         = module.single_account_privesc_one_hop_to_admin_cloudformation_003_iam_passrole_cloudformation_createstackset_cloudformation_createstackinstances[0].administration_role_arn
    administration_role_name        = module.single_account_privesc_one_hop_to_admin_cloudformation_003_iam_passrole_cloudformation_createstackset_cloudformation_createstackinstances[0].administration_role_name
    escalated_role_name             = module.single_account_privesc_one_hop_to_admin_cloudformation_003_iam_passrole_cloudformation_createstackset_cloudformation_createstackinstances[0].escalated_role_name
    attack_path                     = module.single_account_privesc_one_hop_to_admin_cloudformation_003_iam_passrole_cloudformation_createstackset_cloudformation_createstackinstances[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_codebuild_001_iam_passrole_codebuild_createproject_codebuild_startbuild" {
  description = "All outputs for codebuild-001-iam-passrole+codebuild-createproject+codebuild-startbuild one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_codebuild_001_iam_passrole_codebuild_createproject_codebuild_startbuild ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_codebuild_001_iam_passrole_codebuild_createproject_codebuild_startbuild[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_codebuild_001_iam_passrole_codebuild_createproject_codebuild_startbuild[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_codebuild_001_iam_passrole_codebuild_createproject_codebuild_startbuild[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_codebuild_001_iam_passrole_codebuild_createproject_codebuild_startbuild[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_codebuild_001_iam_passrole_codebuild_createproject_codebuild_startbuild[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_codebuild_001_iam_passrole_codebuild_createproject_codebuild_startbuild[0].target_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_codebuild_001_iam_passrole_codebuild_createproject_codebuild_startbuild[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_codebuild_004_iam_passrole_codebuild_createproject_codebuild_startbuildbatch" {
  description = "All outputs for codebuild-004-iam-passrole+codebuild-createproject+codebuild-startbuildbatch one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_codebuild_004_iam_passrole_codebuild_createproject_codebuild_startbuildbatch ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_codebuild_004_iam_passrole_codebuild_createproject_codebuild_startbuildbatch[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_codebuild_004_iam_passrole_codebuild_createproject_codebuild_startbuildbatch[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_codebuild_004_iam_passrole_codebuild_createproject_codebuild_startbuildbatch[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_codebuild_004_iam_passrole_codebuild_createproject_codebuild_startbuildbatch[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_codebuild_004_iam_passrole_codebuild_createproject_codebuild_startbuildbatch[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_codebuild_004_iam_passrole_codebuild_createproject_codebuild_startbuildbatch[0].target_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_codebuild_004_iam_passrole_codebuild_createproject_codebuild_startbuildbatch[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_021_iam_putrolepolicy_iam_updateassumerolepolicy" {
  description = "All outputs for iam-021-iam-putrolepolicy+iam-updateassumerolepolicy one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_021_iam_putrolepolicy_iam_updateassumerolepolicy ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_021_iam_putrolepolicy_iam_updateassumerolepolicy[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_021_iam_putrolepolicy_iam_updateassumerolepolicy[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_021_iam_putrolepolicy_iam_updateassumerolepolicy[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_021_iam_putrolepolicy_iam_updateassumerolepolicy[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_iam_021_iam_putrolepolicy_iam_updateassumerolepolicy[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_iam_021_iam_putrolepolicy_iam_updateassumerolepolicy[0].target_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_021_iam_putrolepolicy_iam_updateassumerolepolicy[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_017_iam_putrolepolicy_sts_assumerole" {
  description = "All outputs for iam-017-iam-putrolepolicy+sts-assumerole one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_017_iam_putrolepolicy_sts_assumerole ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_017_iam_putrolepolicy_sts_assumerole[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_017_iam_putrolepolicy_sts_assumerole[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_017_iam_putrolepolicy_sts_assumerole[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_017_iam_putrolepolicy_sts_assumerole[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_iam_017_iam_putrolepolicy_sts_assumerole[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_iam_017_iam_putrolepolicy_sts_assumerole[0].target_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_017_iam_putrolepolicy_sts_assumerole[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_018_iam_putuserpolicy_iam_createaccesskey" {
  description = "All outputs for iam-018-iam-putuserpolicy+iam-createaccesskey one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_018_iam_putuserpolicy_iam_createaccesskey ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_018_iam_putuserpolicy_iam_createaccesskey[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_018_iam_putuserpolicy_iam_createaccesskey[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_018_iam_putuserpolicy_iam_createaccesskey[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_018_iam_putuserpolicy_iam_createaccesskey[0].starting_user_secret_access_key
    target_user_name                = module.single_account_privesc_one_hop_to_admin_iam_018_iam_putuserpolicy_iam_createaccesskey[0].target_user_name
    target_user_arn                 = module.single_account_privesc_one_hop_to_admin_iam_018_iam_putuserpolicy_iam_createaccesskey[0].target_user_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_018_iam_putuserpolicy_iam_createaccesskey[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_lambda_002_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb" {
  description = "All outputs for lambda-002-iam-passrole+lambda-createfunction+createeventsourcemapping-dynamodb one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_lambda_002_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_lambda_002_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_lambda_002_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_lambda_002_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_lambda_002_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_lambda_002_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_lambda_002_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb[0].target_role_arn
    dynamodb_table_name             = module.single_account_privesc_one_hop_to_admin_lambda_002_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb[0].dynamodb_table_name
    dynamodb_stream_arn             = module.single_account_privesc_one_hop_to_admin_lambda_002_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb[0].dynamodb_stream_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_lambda_002_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_lambda_003_lambda_updatefunctioncode" {
  description = "All outputs for lambda-003-lambda-updatefunctioncode one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_lambda_003_lambda_updatefunctioncode ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_lambda_003_lambda_updatefunctioncode[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_lambda_003_lambda_updatefunctioncode[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_lambda_003_lambda_updatefunctioncode[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_lambda_003_lambda_updatefunctioncode[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_lambda_003_lambda_updatefunctioncode[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_lambda_003_lambda_updatefunctioncode[0].target_role_arn
    target_lambda_function_name     = module.single_account_privesc_one_hop_to_admin_lambda_003_lambda_updatefunctioncode[0].target_lambda_function_name
    target_lambda_function_arn      = module.single_account_privesc_one_hop_to_admin_lambda_003_lambda_updatefunctioncode[0].target_lambda_function_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_lambda_003_lambda_updatefunctioncode[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_lambda_005_lambda_updatefunctioncode_lambda_addpermission" {
  description = "All outputs for lambda-005-lambda-updatefunctioncode+lambda-addpermission one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_lambda_005_lambda_updatefunctioncode_lambda_addpermission ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_lambda_005_lambda_updatefunctioncode_lambda_addpermission[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_lambda_005_lambda_updatefunctioncode_lambda_addpermission[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_lambda_005_lambda_updatefunctioncode_lambda_addpermission[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_lambda_005_lambda_updatefunctioncode_lambda_addpermission[0].starting_user_secret_access_key
    target_lambda_function_name     = module.single_account_privesc_one_hop_to_admin_lambda_005_lambda_updatefunctioncode_lambda_addpermission[0].target_lambda_function_name
    target_lambda_function_arn      = module.single_account_privesc_one_hop_to_admin_lambda_005_lambda_updatefunctioncode_lambda_addpermission[0].target_lambda_function_arn
    target_role_name                = module.single_account_privesc_one_hop_to_admin_lambda_005_lambda_updatefunctioncode_lambda_addpermission[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_lambda_005_lambda_updatefunctioncode_lambda_addpermission[0].target_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_lambda_005_lambda_updatefunctioncode_lambda_addpermission[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_lambda_004_lambda_updatefunctioncode_lambda_invokefunction" {
  description = "All outputs for lambda-004-lambda-updatefunctioncode+lambda-invokefunction one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_lambda_004_lambda_updatefunctioncode_lambda_invokefunction ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_lambda_004_lambda_updatefunctioncode_lambda_invokefunction[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_lambda_004_lambda_updatefunctioncode_lambda_invokefunction[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_lambda_004_lambda_updatefunctioncode_lambda_invokefunction[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_lambda_004_lambda_updatefunctioncode_lambda_invokefunction[0].starting_user_secret_access_key
    target_lambda_function_name     = module.single_account_privesc_one_hop_to_admin_lambda_004_lambda_updatefunctioncode_lambda_invokefunction[0].target_lambda_function_name
    target_lambda_function_arn      = module.single_account_privesc_one_hop_to_admin_lambda_004_lambda_updatefunctioncode_lambda_invokefunction[0].target_lambda_function_arn
    target_role_name                = module.single_account_privesc_one_hop_to_admin_lambda_004_lambda_updatefunctioncode_lambda_invokefunction[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_lambda_004_lambda_updatefunctioncode_lambda_invokefunction[0].target_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_lambda_004_lambda_updatefunctioncode_lambda_invokefunction[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_sagemaker_001_iam_passrole_sagemaker_createnotebookinstance" {
  description = "All outputs for sagemaker-001 iam-passrole+sagemaker-createnotebookinstance one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_sagemaker_001_iam_passrole_sagemaker_createnotebookinstance ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_sagemaker_001_iam_passrole_sagemaker_createnotebookinstance[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_sagemaker_001_iam_passrole_sagemaker_createnotebookinstance[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_sagemaker_001_iam_passrole_sagemaker_createnotebookinstance[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_sagemaker_001_iam_passrole_sagemaker_createnotebookinstance[0].starting_user_secret_access_key
    passable_role_name              = module.single_account_privesc_one_hop_to_admin_sagemaker_001_iam_passrole_sagemaker_createnotebookinstance[0].passable_role_name
    passable_role_arn               = module.single_account_privesc_one_hop_to_admin_sagemaker_001_iam_passrole_sagemaker_createnotebookinstance[0].passable_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_sagemaker_001_iam_passrole_sagemaker_createnotebookinstance[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_sagemaker_003_iam_passrole_sagemaker_createprocessingjob" {
  description = "All outputs for sagemaker-003 iam-passrole+sagemaker-createprocessingjob one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_sagemaker_003_iam_passrole_sagemaker_createprocessingjob ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_sagemaker_003_iam_passrole_sagemaker_createprocessingjob[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_sagemaker_003_iam_passrole_sagemaker_createprocessingjob[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_sagemaker_003_iam_passrole_sagemaker_createprocessingjob[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_sagemaker_003_iam_passrole_sagemaker_createprocessingjob[0].starting_user_secret_access_key
    passable_role_name              = module.single_account_privesc_one_hop_to_admin_sagemaker_003_iam_passrole_sagemaker_createprocessingjob[0].passable_role_name
    passable_role_arn               = module.single_account_privesc_one_hop_to_admin_sagemaker_003_iam_passrole_sagemaker_createprocessingjob[0].passable_role_arn
    bucket_name                     = module.single_account_privesc_one_hop_to_admin_sagemaker_003_iam_passrole_sagemaker_createprocessingjob[0].bucket_name
    bucket_arn                      = module.single_account_privesc_one_hop_to_admin_sagemaker_003_iam_passrole_sagemaker_createprocessingjob[0].bucket_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_sagemaker_003_iam_passrole_sagemaker_createprocessingjob[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_sagemaker_004_sagemaker_createpresignednotebookinstanceurl" {
  description = "All outputs for sagemaker-004-sagemaker-createpresignednotebookinstanceurl one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_sagemaker_004_sagemaker_createpresignednotebookinstanceurl ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_sagemaker_004_sagemaker_createpresignednotebookinstanceurl[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_sagemaker_004_sagemaker_createpresignednotebookinstanceurl[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_sagemaker_004_sagemaker_createpresignednotebookinstanceurl[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_sagemaker_004_sagemaker_createpresignednotebookinstanceurl[0].starting_user_secret_access_key
    notebook_instance_name          = module.single_account_privesc_one_hop_to_admin_sagemaker_004_sagemaker_createpresignednotebookinstanceurl[0].notebook_instance_name
    notebook_instance_arn           = module.single_account_privesc_one_hop_to_admin_sagemaker_004_sagemaker_createpresignednotebookinstanceurl[0].notebook_instance_arn
    notebook_execution_role_name    = module.single_account_privesc_one_hop_to_admin_sagemaker_004_sagemaker_createpresignednotebookinstanceurl[0].notebook_execution_role_name
    notebook_execution_role_arn     = module.single_account_privesc_one_hop_to_admin_sagemaker_004_sagemaker_createpresignednotebookinstanceurl[0].notebook_execution_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_sagemaker_004_sagemaker_createpresignednotebookinstanceurl[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_sagemaker_005_sagemaker_updatenotebook_lifecycle_config" {
  description = "All outputs for sagemaker-005-sagemaker-updatenotebook-lifecycle-config one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_sagemaker_005_sagemaker_updatenotebook_lifecycle_config ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_sagemaker_005_sagemaker_updatenotebook_lifecycle_config[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_sagemaker_005_sagemaker_updatenotebook_lifecycle_config[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_sagemaker_005_sagemaker_updatenotebook_lifecycle_config[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_sagemaker_005_sagemaker_updatenotebook_lifecycle_config[0].starting_user_secret_access_key
    notebook_instance_name          = module.single_account_privesc_one_hop_to_admin_sagemaker_005_sagemaker_updatenotebook_lifecycle_config[0].notebook_instance_name
    notebook_instance_arn           = module.single_account_privesc_one_hop_to_admin_sagemaker_005_sagemaker_updatenotebook_lifecycle_config[0].notebook_instance_arn
    notebook_execution_role_arn     = module.single_account_privesc_one_hop_to_admin_sagemaker_005_sagemaker_updatenotebook_lifecycle_config[0].notebook_execution_role_arn
    notebook_execution_role_name    = module.single_account_privesc_one_hop_to_admin_sagemaker_005_sagemaker_updatenotebook_lifecycle_config[0].notebook_execution_role_name
    attack_path                     = module.single_account_privesc_one_hop_to_admin_sagemaker_005_sagemaker_updatenotebook_lifecycle_config[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_sagemaker_002_iam_passrole_sagemaker_createtrainingjob" {
  description = "All outputs for sagemaker-002-iam-passrole+sagemaker-createtrainingjob one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_sagemaker_002_iam_passrole_sagemaker_createtrainingjob ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_sagemaker_002_iam_passrole_sagemaker_createtrainingjob[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_sagemaker_002_iam_passrole_sagemaker_createtrainingjob[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_sagemaker_002_iam_passrole_sagemaker_createtrainingjob[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_sagemaker_002_iam_passrole_sagemaker_createtrainingjob[0].starting_user_secret_access_key
    passable_role_name              = module.single_account_privesc_one_hop_to_admin_sagemaker_002_iam_passrole_sagemaker_createtrainingjob[0].passable_role_name
    passable_role_arn               = module.single_account_privesc_one_hop_to_admin_sagemaker_002_iam_passrole_sagemaker_createtrainingjob[0].passable_role_arn
    bucket_name                     = module.single_account_privesc_one_hop_to_admin_sagemaker_002_iam_passrole_sagemaker_createtrainingjob[0].bucket_name
    bucket_arn                      = module.single_account_privesc_one_hop_to_admin_sagemaker_002_iam_passrole_sagemaker_createtrainingjob[0].bucket_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_sagemaker_002_iam_passrole_sagemaker_createtrainingjob[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_ssm_002_ssm_sendcommand" {
  description = "All outputs for ssm-002-ssm-sendcommand one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_ssm_002_ssm_sendcommand ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_ssm_002_ssm_sendcommand[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_ssm_002_ssm_sendcommand[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_ssm_002_ssm_sendcommand[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_ssm_002_ssm_sendcommand[0].starting_user_secret_access_key
    ec2_instance_id                 = module.single_account_privesc_one_hop_to_admin_ssm_002_ssm_sendcommand[0].ec2_instance_id
    ec2_instance_arn                = module.single_account_privesc_one_hop_to_admin_ssm_002_ssm_sendcommand[0].ec2_instance_arn
    ec2_admin_role_name             = module.single_account_privesc_one_hop_to_admin_ssm_002_ssm_sendcommand[0].ec2_admin_role_name
    ec2_admin_role_arn              = module.single_account_privesc_one_hop_to_admin_ssm_002_ssm_sendcommand[0].ec2_admin_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_ssm_002_ssm_sendcommand[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_ssm_001_ssm_startsession" {
  description = "All outputs for ssm-001-ssm-startsession one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_ssm_001_ssm_startsession ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_ssm_001_ssm_startsession[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_ssm_001_ssm_startsession[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_ssm_001_ssm_startsession[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_ssm_001_ssm_startsession[0].starting_user_secret_access_key
    ec2_instance_id                 = module.single_account_privesc_one_hop_to_admin_ssm_001_ssm_startsession[0].ec2_instance_id
    ec2_instance_arn                = module.single_account_privesc_one_hop_to_admin_ssm_001_ssm_startsession[0].ec2_instance_arn
    ec2_admin_role_name             = module.single_account_privesc_one_hop_to_admin_ssm_001_ssm_startsession[0].ec2_admin_role_name
    ec2_admin_role_arn              = module.single_account_privesc_one_hop_to_admin_ssm_001_ssm_startsession[0].ec2_admin_role_arn
    target_admin_role_name          = module.single_account_privesc_one_hop_to_admin_ssm_001_ssm_startsession[0].target_admin_role_name
    target_admin_role_arn           = module.single_account_privesc_one_hop_to_admin_ssm_001_ssm_startsession[0].target_admin_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_ssm_001_ssm_startsession[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_codebuild_002_codebuild_startbuild" {
  description = "All outputs for codebuild-002-codebuild-startbuild one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_codebuild_002_codebuild_startbuild ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_codebuild_002_codebuild_startbuild[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_codebuild_002_codebuild_startbuild[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_codebuild_002_codebuild_startbuild[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_codebuild_002_codebuild_startbuild[0].starting_user_secret_access_key
    project_role_name               = module.single_account_privesc_one_hop_to_admin_codebuild_002_codebuild_startbuild[0].project_role_name
    project_role_arn                = module.single_account_privesc_one_hop_to_admin_codebuild_002_codebuild_startbuild[0].project_role_arn
    codebuild_project_name          = module.single_account_privesc_one_hop_to_admin_codebuild_002_codebuild_startbuild[0].codebuild_project_name
    codebuild_project_arn           = module.single_account_privesc_one_hop_to_admin_codebuild_002_codebuild_startbuild[0].codebuild_project_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_codebuild_002_codebuild_startbuild[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_codebuild_003_codebuild_startbuildbatch" {
  description = "All outputs for codebuild-003-codebuild-startbuildbatch one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_codebuild_003_codebuild_startbuildbatch ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_codebuild_003_codebuild_startbuildbatch[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_codebuild_003_codebuild_startbuildbatch[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_codebuild_003_codebuild_startbuildbatch[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_codebuild_003_codebuild_startbuildbatch[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_codebuild_003_codebuild_startbuildbatch[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_codebuild_003_codebuild_startbuildbatch[0].target_role_arn
    codebuild_project_name          = module.single_account_privesc_one_hop_to_admin_codebuild_003_codebuild_startbuildbatch[0].codebuild_project_name
    codebuild_project_arn           = module.single_account_privesc_one_hop_to_admin_codebuild_003_codebuild_startbuildbatch[0].codebuild_project_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_codebuild_003_codebuild_startbuildbatch[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_ec2_003_ec2_instance_connect_sendsshpublickey" {
  description = "All outputs for ec2-003-ec2-instance-connect-sendsshpublickey one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_ec2_003_ec2_instance_connect_sendsshpublickey ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_ec2_003_ec2_instance_connect_sendsshpublickey[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_ec2_003_ec2_instance_connect_sendsshpublickey[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_ec2_003_ec2_instance_connect_sendsshpublickey[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_ec2_003_ec2_instance_connect_sendsshpublickey[0].starting_user_secret_access_key
    ec2_instance_id                 = module.single_account_privesc_one_hop_to_admin_ec2_003_ec2_instance_connect_sendsshpublickey[0].ec2_instance_id
    ec2_instance_arn                = module.single_account_privesc_one_hop_to_admin_ec2_003_ec2_instance_connect_sendsshpublickey[0].ec2_instance_arn
    ec2_instance_public_ip          = module.single_account_privesc_one_hop_to_admin_ec2_003_ec2_instance_connect_sendsshpublickey[0].ec2_instance_public_ip
    ec2_admin_role_name             = module.single_account_privesc_one_hop_to_admin_ec2_003_ec2_instance_connect_sendsshpublickey[0].ec2_admin_role_name
    ec2_admin_role_arn              = module.single_account_privesc_one_hop_to_admin_ec2_003_ec2_instance_connect_sendsshpublickey[0].ec2_admin_role_arn
    allowed_ssh_ip                  = module.single_account_privesc_one_hop_to_admin_ec2_003_ec2_instance_connect_sendsshpublickey[0].allowed_ssh_ip
    attack_path                     = module.single_account_privesc_one_hop_to_admin_ec2_003_ec2_instance_connect_sendsshpublickey[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_ec2_002_ec2_modifyinstanceattribute_stopinstances_startinstances" {
  description = "All outputs for ec2-002 ec2-modifyinstanceattribute+stopinstances+startinstances one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_ec2_002_ec2_modifyinstanceattribute_stopinstances_startinstances ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_ec2_002_ec2_modifyinstanceattribute_stopinstances_startinstances[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_ec2_002_ec2_modifyinstanceattribute_stopinstances_startinstances[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_ec2_002_ec2_modifyinstanceattribute_stopinstances_startinstances[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_ec2_002_ec2_modifyinstanceattribute_stopinstances_startinstances[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_ec2_002_ec2_modifyinstanceattribute_stopinstances_startinstances[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_ec2_002_ec2_modifyinstanceattribute_stopinstances_startinstances[0].target_role_arn
    target_instance_id              = module.single_account_privesc_one_hop_to_admin_ec2_002_ec2_modifyinstanceattribute_stopinstances_startinstances[0].target_instance_id
    initial_user_data               = module.single_account_privesc_one_hop_to_admin_ec2_002_ec2_modifyinstanceattribute_stopinstances_startinstances[0].initial_user_data
    attack_path                     = module.single_account_privesc_one_hop_to_admin_ec2_002_ec2_modifyinstanceattribute_stopinstances_startinstances[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_bucket_iam_002_iam_createaccesskey" {
  description = "All outputs for iam-002-iam-createaccesskey one-hop to-bucket scenario"
  value = var.enable_single_account_privesc_one_hop_to_bucket_iam_002_iam_createaccesskey ? {
    privesc_user_name              = module.single_account_privesc_one_hop_to_bucket_iam_002_iam_createaccesskey[0].privesc_user_name
    privesc_user_access_key_id     = module.single_account_privesc_one_hop_to_bucket_iam_002_iam_createaccesskey[0].privesc_user_access_key_id
    privesc_user_secret_access_key = module.single_account_privesc_one_hop_to_bucket_iam_002_iam_createaccesskey[0].privesc_user_secret_access_key
    bucket_access_user_name        = module.single_account_privesc_one_hop_to_bucket_iam_002_iam_createaccesskey[0].bucket_access_user_name
    target_bucket_name             = module.single_account_privesc_one_hop_to_bucket_iam_002_iam_createaccesskey[0].target_bucket_name
    attack_path                    = module.single_account_privesc_one_hop_to_bucket_iam_002_iam_createaccesskey[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_bucket_iam_004_iam_createloginprofile" {
  description = "All outputs for iam-004-iam-createloginprofile one-hop to-bucket scenario"
  value = var.enable_single_account_privesc_one_hop_to_bucket_iam_004_iam_createloginprofile ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_bucket_iam_004_iam_createloginprofile[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_bucket_iam_004_iam_createloginprofile[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_bucket_iam_004_iam_createloginprofile[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_bucket_iam_004_iam_createloginprofile[0].starting_user_secret_access_key
    hop1_user_name                  = module.single_account_privesc_one_hop_to_bucket_iam_004_iam_createloginprofile[0].hop1_user_name
    hop1_user_arn                   = module.single_account_privesc_one_hop_to_bucket_iam_004_iam_createloginprofile[0].hop1_user_arn
    sensitive_bucket_name           = module.single_account_privesc_one_hop_to_bucket_iam_004_iam_createloginprofile[0].sensitive_bucket_name
    sensitive_bucket_arn            = module.single_account_privesc_one_hop_to_bucket_iam_004_iam_createloginprofile[0].sensitive_bucket_arn
    console_login_url               = module.single_account_privesc_one_hop_to_bucket_iam_004_iam_createloginprofile[0].console_login_url
    attack_path                     = module.single_account_privesc_one_hop_to_bucket_iam_004_iam_createloginprofile[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_bucket_iam_003_iam_deleteaccesskey_createaccesskey" {
  description = "All outputs for iam-003-iam-deleteaccesskey+createaccesskey one-hop to-bucket scenario"
  value = var.enable_single_account_privesc_one_hop_to_bucket_iam_003_iam_deleteaccesskey_createaccesskey ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_bucket_iam_003_iam_deleteaccesskey_createaccesskey[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_bucket_iam_003_iam_deleteaccesskey_createaccesskey[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_bucket_iam_003_iam_deleteaccesskey_createaccesskey[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_bucket_iam_003_iam_deleteaccesskey_createaccesskey[0].starting_user_secret_access_key
    target_user_name                = module.single_account_privesc_one_hop_to_bucket_iam_003_iam_deleteaccesskey_createaccesskey[0].target_user_name
    target_user_arn                 = module.single_account_privesc_one_hop_to_bucket_iam_003_iam_deleteaccesskey_createaccesskey[0].target_user_arn
    target_user_key_1_id            = module.single_account_privesc_one_hop_to_bucket_iam_003_iam_deleteaccesskey_createaccesskey[0].target_user_key_1_id
    target_user_key_2_id            = module.single_account_privesc_one_hop_to_bucket_iam_003_iam_deleteaccesskey_createaccesskey[0].target_user_key_2_id
    target_bucket_name              = module.single_account_privesc_one_hop_to_bucket_iam_003_iam_deleteaccesskey_createaccesskey[0].target_bucket_name
    target_bucket_arn               = module.single_account_privesc_one_hop_to_bucket_iam_003_iam_deleteaccesskey_createaccesskey[0].target_bucket_arn
    attack_path                     = module.single_account_privesc_one_hop_to_bucket_iam_003_iam_deleteaccesskey_createaccesskey[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_bucket_sts_001_sts_assumerole" {
  description = "All outputs for sts-001-sts-assumerole one-hop to-bucket scenario"
  value = var.enable_single_account_privesc_one_hop_to_bucket_sts_001_sts_assumerole ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_bucket_sts_001_sts_assumerole[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_bucket_sts_001_sts_assumerole[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_bucket_sts_001_sts_assumerole[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_bucket_sts_001_sts_assumerole[0].starting_user_secret_access_key
    bucket_access_role_arn          = module.single_account_privesc_one_hop_to_bucket_sts_001_sts_assumerole[0].bucket_access_role_arn
    target_bucket_name              = module.single_account_privesc_one_hop_to_bucket_sts_001_sts_assumerole[0].target_bucket_name
    attack_path                     = module.single_account_privesc_one_hop_to_bucket_sts_001_sts_assumerole[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_bucket_iam_006_iam_updateloginprofile" {
  description = "All outputs for iam-006-iam-updateloginprofile one-hop to-bucket scenario"
  value = var.enable_single_account_privesc_one_hop_to_bucket_iam_006_iam_updateloginprofile ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_bucket_iam_006_iam_updateloginprofile[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_bucket_iam_006_iam_updateloginprofile[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_bucket_iam_006_iam_updateloginprofile[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_bucket_iam_006_iam_updateloginprofile[0].starting_user_secret_access_key
    target_user_name                = module.single_account_privesc_one_hop_to_bucket_iam_006_iam_updateloginprofile[0].target_user_name
    target_user_arn                 = module.single_account_privesc_one_hop_to_bucket_iam_006_iam_updateloginprofile[0].target_user_arn
    original_password               = module.single_account_privesc_one_hop_to_bucket_iam_006_iam_updateloginprofile[0].original_password
    sensitive_bucket_name           = module.single_account_privesc_one_hop_to_bucket_iam_006_iam_updateloginprofile[0].sensitive_bucket_name
    sensitive_bucket_arn            = module.single_account_privesc_one_hop_to_bucket_iam_006_iam_updateloginprofile[0].sensitive_bucket_arn
    console_login_url               = module.single_account_privesc_one_hop_to_bucket_iam_006_iam_updateloginprofile[0].console_login_url
    attack_path                     = module.single_account_privesc_one_hop_to_bucket_iam_006_iam_updateloginprofile[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_bucket_ec2_003_ec2_instance_connect_sendsshpublickey" {
  description = "All outputs for ec2-instance-connect-sendsshpublickey one-hop to-bucket scenario"
  value = var.enable_single_account_privesc_one_hop_to_bucket_ec2_003_ec2_instance_connect_sendsshpublickey ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_bucket_ec2_003_ec2_instance_connect_sendsshpublickey[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_bucket_ec2_003_ec2_instance_connect_sendsshpublickey[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_bucket_ec2_003_ec2_instance_connect_sendsshpublickey[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_bucket_ec2_003_ec2_instance_connect_sendsshpublickey[0].starting_user_secret_access_key
    ec2_instance_id                 = module.single_account_privesc_one_hop_to_bucket_ec2_003_ec2_instance_connect_sendsshpublickey[0].ec2_instance_id
    ec2_instance_arn                = module.single_account_privesc_one_hop_to_bucket_ec2_003_ec2_instance_connect_sendsshpublickey[0].ec2_instance_arn
    ec2_instance_public_ip          = module.single_account_privesc_one_hop_to_bucket_ec2_003_ec2_instance_connect_sendsshpublickey[0].ec2_instance_public_ip
    ec2_bucket_role_name            = module.single_account_privesc_one_hop_to_bucket_ec2_003_ec2_instance_connect_sendsshpublickey[0].ec2_bucket_role_name
    ec2_bucket_role_arn             = module.single_account_privesc_one_hop_to_bucket_ec2_003_ec2_instance_connect_sendsshpublickey[0].ec2_bucket_role_arn
    target_bucket_name              = module.single_account_privesc_one_hop_to_bucket_ec2_003_ec2_instance_connect_sendsshpublickey[0].target_bucket_name
    target_bucket_arn               = module.single_account_privesc_one_hop_to_bucket_ec2_003_ec2_instance_connect_sendsshpublickey[0].target_bucket_arn
    allowed_ssh_ip                  = module.single_account_privesc_one_hop_to_bucket_ec2_003_ec2_instance_connect_sendsshpublickey[0].allowed_ssh_ip
    attack_path                     = module.single_account_privesc_one_hop_to_bucket_ec2_003_ec2_instance_connect_sendsshpublickey[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_bucket_glue_002_glue_updatedevendpoint" {
  description = "All outputs for glue-002-glue-updatedevendpoint one-hop to-bucket scenario"
  value = var.enable_single_account_privesc_one_hop_to_bucket_glue_002_glue_updatedevendpoint ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_bucket_glue_002_glue_updatedevendpoint[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_bucket_glue_002_glue_updatedevendpoint[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_bucket_glue_002_glue_updatedevendpoint[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_bucket_glue_002_glue_updatedevendpoint[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_bucket_glue_002_glue_updatedevendpoint[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_bucket_glue_002_glue_updatedevendpoint[0].target_role_arn
    dev_endpoint_name               = module.single_account_privesc_one_hop_to_bucket_glue_002_glue_updatedevendpoint[0].dev_endpoint_name
    dev_endpoint_arn                = module.single_account_privesc_one_hop_to_bucket_glue_002_glue_updatedevendpoint[0].dev_endpoint_arn
    dev_endpoint_address            = module.single_account_privesc_one_hop_to_bucket_glue_002_glue_updatedevendpoint[0].dev_endpoint_address
    sensitive_bucket_name           = module.single_account_privesc_one_hop_to_bucket_glue_002_glue_updatedevendpoint[0].sensitive_bucket_name
    sensitive_bucket_arn            = module.single_account_privesc_one_hop_to_bucket_glue_002_glue_updatedevendpoint[0].sensitive_bucket_arn
    attack_path                     = module.single_account_privesc_one_hop_to_bucket_glue_002_glue_updatedevendpoint[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_bucket_ssm_002_ssm_sendcommand" {
  description = "All outputs for ssm-002-ssm-sendcommand one-hop to-bucket scenario"
  value = var.enable_single_account_privesc_one_hop_to_bucket_ssm_002_ssm_sendcommand ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_bucket_ssm_002_ssm_sendcommand[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_bucket_ssm_002_ssm_sendcommand[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_bucket_ssm_002_ssm_sendcommand[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_bucket_ssm_002_ssm_sendcommand[0].starting_user_secret_access_key
    ec2_instance_id                 = module.single_account_privesc_one_hop_to_bucket_ssm_002_ssm_sendcommand[0].ec2_instance_id
    ec2_instance_arn                = module.single_account_privesc_one_hop_to_bucket_ssm_002_ssm_sendcommand[0].ec2_instance_arn
    ec2_bucket_role_name            = module.single_account_privesc_one_hop_to_bucket_ssm_002_ssm_sendcommand[0].ec2_bucket_role_name
    ec2_bucket_role_arn             = module.single_account_privesc_one_hop_to_bucket_ssm_002_ssm_sendcommand[0].ec2_bucket_role_arn
    target_bucket_name              = module.single_account_privesc_one_hop_to_bucket_ssm_002_ssm_sendcommand[0].target_bucket_name
    target_bucket_arn               = module.single_account_privesc_one_hop_to_bucket_ssm_002_ssm_sendcommand[0].target_bucket_arn
    attack_path                     = module.single_account_privesc_one_hop_to_bucket_ssm_002_ssm_sendcommand[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_bucket_ssm_001_ssm_startsession" {
  description = "All outputs for ssm-001-ssm-startsession one-hop to-bucket scenario"
  value = var.enable_single_account_privesc_one_hop_to_bucket_ssm_001_ssm_startsession ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_bucket_ssm_001_ssm_startsession[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_bucket_ssm_001_ssm_startsession[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_bucket_ssm_001_ssm_startsession[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_bucket_ssm_001_ssm_startsession[0].starting_user_secret_access_key
    ec2_instance_id                 = module.single_account_privesc_one_hop_to_bucket_ssm_001_ssm_startsession[0].ec2_instance_id
    ec2_instance_arn                = module.single_account_privesc_one_hop_to_bucket_ssm_001_ssm_startsession[0].ec2_instance_arn
    ec2_bucket_role_name            = module.single_account_privesc_one_hop_to_bucket_ssm_001_ssm_startsession[0].ec2_bucket_role_name
    ec2_bucket_role_arn             = module.single_account_privesc_one_hop_to_bucket_ssm_001_ssm_startsession[0].ec2_bucket_role_arn
    target_bucket_name              = module.single_account_privesc_one_hop_to_bucket_ssm_001_ssm_startsession[0].target_bucket_name
    target_bucket_arn               = module.single_account_privesc_one_hop_to_bucket_ssm_001_ssm_startsession[0].target_bucket_arn
    attack_path                     = module.single_account_privesc_one_hop_to_bucket_ssm_001_ssm_startsession[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_bucket_glue_001_iam_passrole_glue_createdevendpoint" {
  description = "All outputs for glue-001 iam-passrole+glue-createdevendpoint one-hop to-bucket scenario"
  value = var.enable_single_account_privesc_one_hop_to_bucket_glue_001_iam_passrole_glue_createdevendpoint ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_bucket_glue_001_iam_passrole_glue_createdevendpoint[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_bucket_glue_001_iam_passrole_glue_createdevendpoint[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_bucket_glue_001_iam_passrole_glue_createdevendpoint[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_bucket_glue_001_iam_passrole_glue_createdevendpoint[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_bucket_glue_001_iam_passrole_glue_createdevendpoint[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_bucket_glue_001_iam_passrole_glue_createdevendpoint[0].target_role_arn
    sensitive_bucket_name           = module.single_account_privesc_one_hop_to_bucket_glue_001_iam_passrole_glue_createdevendpoint[0].sensitive_bucket_name
    sensitive_bucket_arn            = module.single_account_privesc_one_hop_to_bucket_glue_001_iam_passrole_glue_createdevendpoint[0].sensitive_bucket_arn
    attack_path                     = module.single_account_privesc_one_hop_to_bucket_glue_001_iam_passrole_glue_createdevendpoint[0].attack_path
  } : null
  sensitive = true
}

##############################################################################
# MULTI-HOP SCENARIO GROUPED OUTPUTS
##############################################################################

# Multi-hop to-admin scenarios
output "single_account_privesc_multi_hop_to_admin_multiple_paths_combined" {
  description = "All outputs for multiple-paths-combined multi-hop to-admin scenario"
  value = var.enable_single_account_privesc_multi_hop_to_admin_multiple_paths_combined ? {
    starting_user_name              = module.single_account_privesc_multi_hop_to_admin_multiple_paths_combined[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_multi_hop_to_admin_multiple_paths_combined[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_multi_hop_to_admin_multiple_paths_combined[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_multi_hop_to_admin_multiple_paths_combined[0].starting_user_secret_access_key
    privesc_role_arn                = module.single_account_privesc_multi_hop_to_admin_multiple_paths_combined[0].privesc_role_arn
    privesc_role_name               = module.single_account_privesc_multi_hop_to_admin_multiple_paths_combined[0].privesc_role_name
    ec2_admin_role_arn              = module.single_account_privesc_multi_hop_to_admin_multiple_paths_combined[0].ec2_admin_role_arn
    lambda_admin_role_arn           = module.single_account_privesc_multi_hop_to_admin_multiple_paths_combined[0].lambda_admin_role_arn
    cloudformation_admin_role_arn   = module.single_account_privesc_multi_hop_to_admin_multiple_paths_combined[0].cloudformation_admin_role_arn
    attack_path                     = module.single_account_privesc_multi_hop_to_admin_multiple_paths_combined[0].attack_path
  } : null
  sensitive = true
}


# Multi-hop to-bucket scenarios

##############################################################################
# TOOL TESTING SCENARIOS
##############################################################################

output "tool_testing_exclusive_resource_policy" {
  description = "All outputs for exclusive-resource-policy tool testing scenario"
  value = var.enable_tool_testing_exclusive_resource_policy ? {
    starting_user_name                     = module.tool_testing_exclusive_resource_policy[0].starting_user_name
    starting_user_arn                      = module.tool_testing_exclusive_resource_policy[0].starting_user_arn
    starting_user_access_key_id            = module.tool_testing_exclusive_resource_policy[0].starting_user_access_key_id
    starting_user_secret_access_key        = module.tool_testing_exclusive_resource_policy[0].starting_user_secret_access_key
    exclusive_bucket_access_role_name      = module.tool_testing_exclusive_resource_policy[0].exclusive_bucket_access_role_name
    exclusive_bucket_access_role_arn       = module.tool_testing_exclusive_resource_policy[0].exclusive_bucket_access_role_arn
    exclusive_sensitive_bucket_name        = module.tool_testing_exclusive_resource_policy[0].exclusive_sensitive_bucket_name
    exclusive_sensitive_bucket_arn         = module.tool_testing_exclusive_resource_policy[0].exclusive_sensitive_bucket_arn
    exclusive_sensitive_bucket_domain_name = module.tool_testing_exclusive_resource_policy[0].exclusive_sensitive_bucket_domain_name
    attack_path                            = module.tool_testing_exclusive_resource_policy[0].attack_path
  } : null
  sensitive = true
}

output "tool_testing_resource_policy_bypass" {
  description = "All outputs for resource-policy-bypass tool testing scenario"
  value = var.enable_tool_testing_resource_policy_bypass ? {
    starting_user_name              = module.tool_testing_resource_policy_bypass[0].starting_user_name
    starting_user_arn               = module.tool_testing_resource_policy_bypass[0].starting_user_arn
    starting_user_access_key_id     = module.tool_testing_resource_policy_bypass[0].starting_user_access_key_id
    starting_user_secret_access_key = module.tool_testing_resource_policy_bypass[0].starting_user_secret_access_key
    bucket_access_role_name         = module.tool_testing_resource_policy_bypass[0].bucket_access_role_name
    bucket_access_role_arn          = module.tool_testing_resource_policy_bypass[0].bucket_access_role_arn
    sensitive_bucket_name           = module.tool_testing_resource_policy_bypass[0].sensitive_bucket_name
    sensitive_bucket_arn            = module.tool_testing_resource_policy_bypass[0].sensitive_bucket_arn
    sensitive_bucket_domain_name    = module.tool_testing_resource_policy_bypass[0].sensitive_bucket_domain_name
    attack_path                     = module.tool_testing_resource_policy_bypass[0].attack_path
  } : null
  sensitive = true
}

output "tool_testing_test_reverse_blast_radius_direct_and_indirect_through_admin" {
  description = "All outputs for test-reverse-blast-radius-direct-and-indirect-through-admin tool testing scenario"
  value = var.enable_tool_testing_test_reverse_blast_radius_direct_and_indirect_through_admin ? {
    user1_name              = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_through_admin[0].user1_name
    user1_arn               = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_through_admin[0].user1_arn
    user1_access_key_id     = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_through_admin[0].user1_access_key_id
    user1_secret_access_key = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_through_admin[0].user1_secret_access_key
    user2_name              = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_through_admin[0].user2_name
    user2_arn               = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_through_admin[0].user2_arn
    user2_access_key_id     = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_through_admin[0].user2_access_key_id
    user2_secret_access_key = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_through_admin[0].user2_secret_access_key
    role3_name              = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_through_admin[0].role3_name
    role3_arn               = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_through_admin[0].role3_arn
    bucket_name             = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_through_admin[0].bucket_name
    bucket_arn              = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_through_admin[0].bucket_arn
    attack_path             = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_through_admin[0].attack_path
  } : null
  sensitive = true
}

output "tool_testing_test_reverse_blast_radius_direct_and_indirect_to_bucket" {
  description = "All outputs for test-reverse-blast-radius-direct-and-indirect-to-bucket tool testing scenario"
  value = var.enable_tool_testing_test_reverse_blast_radius_direct_and_indirect_to_bucket ? {
    user1_name              = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_to_bucket[0].user1_name
    user1_arn               = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_to_bucket[0].user1_arn
    user1_access_key_id     = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_to_bucket[0].user1_access_key_id
    user1_secret_access_key = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_to_bucket[0].user1_secret_access_key
    user2_name              = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_to_bucket[0].user2_name
    user2_arn               = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_to_bucket[0].user2_arn
    user2_access_key_id     = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_to_bucket[0].user2_access_key_id
    user2_secret_access_key = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_to_bucket[0].user2_secret_access_key
    role3_name              = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_to_bucket[0].role3_name
    role3_arn               = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_to_bucket[0].role3_arn
    bucket_name             = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_to_bucket[0].bucket_name
    bucket_arn              = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_to_bucket[0].bucket_arn
    attack_path             = module.tool_testing_test_reverse_blast_radius_direct_and_indirect_to_bucket[0].attack_path
  } : null
  sensitive = true
}

output "tool_testing_test_effective_permissions_evaluation" {
  description = "All outputs for test-effective-permissions-evaluation tool testing scenario"
  value = var.enable_tool_testing_test_effective_permissions_evaluation ? {
    # Starting user and target
    starting_user_name              = module.tool_testing_test_effective_permissions_evaluation[0].starting_user_name
    starting_user_arn               = module.tool_testing_test_effective_permissions_evaluation[0].starting_user_arn
    starting_user_access_key_id     = module.tool_testing_test_effective_permissions_evaluation[0].starting_user_access_key_id
    starting_user_secret_access_key = module.tool_testing_test_effective_permissions_evaluation[0].starting_user_secret_access_key
    target_bucket_name              = module.tool_testing_test_effective_permissions_evaluation[0].target_bucket_name
    target_bucket_arn               = module.tool_testing_test_effective_permissions_evaluation[0].target_bucket_arn
    scenario_summary                = module.tool_testing_test_effective_permissions_evaluation[0].scenario_summary

    # isAdmin Users (9 users)
    user_isadmin_awsmanaged_name                             = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_awsmanaged_name
    user_isadmin_awsmanaged_arn                              = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_awsmanaged_arn
    user_isadmin_awsmanaged_access_key_id                    = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_awsmanaged_access_key_id
    user_isadmin_awsmanaged_secret_access_key                = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_awsmanaged_secret_access_key
    user_isadmin_customermanaged_name                        = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_customermanaged_name
    user_isadmin_customermanaged_arn                         = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_customermanaged_arn
    user_isadmin_customermanaged_access_key_id               = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_customermanaged_access_key_id
    user_isadmin_customermanaged_secret_access_key           = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_customermanaged_secret_access_key
    user_isadmin_inline_name                                 = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_inline_name
    user_isadmin_inline_arn                                  = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_inline_arn
    user_isadmin_inline_access_key_id                        = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_inline_access_key_id
    user_isadmin_inline_secret_access_key                    = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_inline_secret_access_key
    user_isadmin_via_group_awsmanaged_name                   = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_via_group_awsmanaged_name
    user_isadmin_via_group_awsmanaged_arn                    = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_via_group_awsmanaged_arn
    user_isadmin_via_group_awsmanaged_access_key_id          = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_via_group_awsmanaged_access_key_id
    user_isadmin_via_group_awsmanaged_secret_access_key      = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_via_group_awsmanaged_secret_access_key
    user_isadmin_via_group_customermanaged_name              = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_via_group_customermanaged_name
    user_isadmin_via_group_customermanaged_arn               = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_via_group_customermanaged_arn
    user_isadmin_via_group_customermanaged_access_key_id     = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_via_group_customermanaged_access_key_id
    user_isadmin_via_group_customermanaged_secret_access_key = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_via_group_customermanaged_secret_access_key
    user_isadmin_via_group_inline_name                       = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_via_group_inline_name
    user_isadmin_via_group_inline_arn                        = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_via_group_inline_arn
    user_isadmin_via_group_inline_access_key_id              = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_via_group_inline_access_key_id
    user_isadmin_via_group_inline_secret_access_key          = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_via_group_inline_secret_access_key
    user_isadmin_split_iam_and_notiam_name                   = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_split_iam_and_notiam_name
    user_isadmin_split_iam_and_notiam_arn                    = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_split_iam_and_notiam_arn
    user_isadmin_split_iam_and_notiam_access_key_id          = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_split_iam_and_notiam_access_key_id
    user_isadmin_split_iam_and_notiam_secret_access_key      = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_split_iam_and_notiam_secret_access_key
    user_isadmin_split_s3_and_nots3_name                     = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_split_s3_and_nots3_name
    user_isadmin_split_s3_and_nots3_arn                      = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_split_s3_and_nots3_arn
    user_isadmin_split_s3_and_nots3_access_key_id            = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_split_s3_and_nots3_access_key_id
    user_isadmin_split_s3_and_nots3_secret_access_key        = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_split_s3_and_nots3_secret_access_key
    user_isadmin_many_services_combined_name                 = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_many_services_combined_name
    user_isadmin_many_services_combined_arn                  = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_many_services_combined_arn
    user_isadmin_many_services_combined_access_key_id        = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_many_services_combined_access_key_id
    user_isadmin_many_services_combined_secret_access_key    = module.tool_testing_test_effective_permissions_evaluation[0].user_isadmin_many_services_combined_secret_access_key

    # isAdmin Roles (6 roles)
    role_isadmin_awsmanaged_name             = module.tool_testing_test_effective_permissions_evaluation[0].role_isadmin_awsmanaged_name
    role_isadmin_awsmanaged_arn              = module.tool_testing_test_effective_permissions_evaluation[0].role_isadmin_awsmanaged_arn
    role_isadmin_customermanaged_name        = module.tool_testing_test_effective_permissions_evaluation[0].role_isadmin_customermanaged_name
    role_isadmin_customermanaged_arn         = module.tool_testing_test_effective_permissions_evaluation[0].role_isadmin_customermanaged_arn
    role_isadmin_inline_name                 = module.tool_testing_test_effective_permissions_evaluation[0].role_isadmin_inline_name
    role_isadmin_inline_arn                  = module.tool_testing_test_effective_permissions_evaluation[0].role_isadmin_inline_arn
    role_isadmin_split_iam_and_notiam_name   = module.tool_testing_test_effective_permissions_evaluation[0].role_isadmin_split_iam_and_notiam_name
    role_isadmin_split_iam_and_notiam_arn    = module.tool_testing_test_effective_permissions_evaluation[0].role_isadmin_split_iam_and_notiam_arn
    role_isadmin_split_s3_and_nots3_name     = module.tool_testing_test_effective_permissions_evaluation[0].role_isadmin_split_s3_and_nots3_name
    role_isadmin_split_s3_and_nots3_arn      = module.tool_testing_test_effective_permissions_evaluation[0].role_isadmin_split_s3_and_nots3_arn
    role_isadmin_many_services_combined_name = module.tool_testing_test_effective_permissions_evaluation[0].role_isadmin_many_services_combined_name
    role_isadmin_many_services_combined_arn  = module.tool_testing_test_effective_permissions_evaluation[0].role_isadmin_many_services_combined_arn

    # notAdmin Users - Single Deny (3 users)
    user_notadmin_adminpolicy_plus_denyall_name                            = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_denyall_name
    user_notadmin_adminpolicy_plus_denyall_arn                             = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_denyall_arn
    user_notadmin_adminpolicy_plus_denyall_access_key_id                   = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_denyall_access_key_id
    user_notadmin_adminpolicy_plus_denyall_secret_access_key               = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_denyall_secret_access_key
    user_notadmin_adminpolicy_plus_denynotaction_name                      = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_denynotaction_name
    user_notadmin_adminpolicy_plus_denynotaction_arn                       = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_denynotaction_arn
    user_notadmin_adminpolicy_plus_denynotaction_access_key_id             = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_denynotaction_access_key_id
    user_notadmin_adminpolicy_plus_denynotaction_secret_access_key         = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_denynotaction_secret_access_key
    user_notadmin_adminpolicy_plus_denynotaction_ec2only_name              = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_denynotaction_ec2only_name
    user_notadmin_adminpolicy_plus_denynotaction_ec2only_arn               = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_denynotaction_ec2only_arn
    user_notadmin_adminpolicy_plus_denynotaction_ec2only_access_key_id     = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_denynotaction_ec2only_access_key_id
    user_notadmin_adminpolicy_plus_denynotaction_ec2only_secret_access_key = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_denynotaction_ec2only_secret_access_key

    # notAdmin Roles - Single Deny (3 roles)
    role_notadmin_adminpolicy_plus_denyall_name               = module.tool_testing_test_effective_permissions_evaluation[0].role_notadmin_adminpolicy_plus_denyall_name
    role_notadmin_adminpolicy_plus_denyall_arn                = module.tool_testing_test_effective_permissions_evaluation[0].role_notadmin_adminpolicy_plus_denyall_arn
    role_notadmin_adminpolicy_plus_denynotaction_name         = module.tool_testing_test_effective_permissions_evaluation[0].role_notadmin_adminpolicy_plus_denynotaction_name
    role_notadmin_adminpolicy_plus_denynotaction_arn          = module.tool_testing_test_effective_permissions_evaluation[0].role_notadmin_adminpolicy_plus_denynotaction_arn
    role_notadmin_adminpolicy_plus_denynotaction_ec2only_name = module.tool_testing_test_effective_permissions_evaluation[0].role_notadmin_adminpolicy_plus_denynotaction_ec2only_name
    role_notadmin_adminpolicy_plus_denynotaction_ec2only_arn  = module.tool_testing_test_effective_permissions_evaluation[0].role_notadmin_adminpolicy_plus_denynotaction_ec2only_arn

    # notAdmin Users - Multi-Deny (3 users)
    user_notadmin_adminpolicy_plus_deny_split_iam_notiam_name              = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_deny_split_iam_notiam_name
    user_notadmin_adminpolicy_plus_deny_split_iam_notiam_arn               = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_deny_split_iam_notiam_arn
    user_notadmin_adminpolicy_plus_deny_split_iam_notiam_access_key_id     = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_deny_split_iam_notiam_access_key_id
    user_notadmin_adminpolicy_plus_deny_split_iam_notiam_secret_access_key = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_deny_split_iam_notiam_secret_access_key
    user_notadmin_adminpolicy_plus_deny_incremental_name                   = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_deny_incremental_name
    user_notadmin_adminpolicy_plus_deny_incremental_arn                    = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_deny_incremental_arn
    user_notadmin_adminpolicy_plus_deny_incremental_access_key_id          = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_deny_incremental_access_key_id
    user_notadmin_adminpolicy_plus_deny_incremental_secret_access_key      = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_deny_incremental_secret_access_key
    user_notadmin_split_allow_plus_denyall_name                            = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_split_allow_plus_denyall_name
    user_notadmin_split_allow_plus_denyall_arn                             = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_split_allow_plus_denyall_arn
    user_notadmin_split_allow_plus_denyall_access_key_id                   = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_split_allow_plus_denyall_access_key_id
    user_notadmin_split_allow_plus_denyall_secret_access_key               = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_split_allow_plus_denyall_secret_access_key

    # notAdmin Roles - Multi-Deny (3 roles)
    role_notadmin_adminpolicy_plus_deny_split_iam_notiam_name = module.tool_testing_test_effective_permissions_evaluation[0].role_notadmin_adminpolicy_plus_deny_split_iam_notiam_name
    role_notadmin_adminpolicy_plus_deny_split_iam_notiam_arn  = module.tool_testing_test_effective_permissions_evaluation[0].role_notadmin_adminpolicy_plus_deny_split_iam_notiam_arn
    role_notadmin_adminpolicy_plus_deny_incremental_name      = module.tool_testing_test_effective_permissions_evaluation[0].role_notadmin_adminpolicy_plus_deny_incremental_name
    role_notadmin_adminpolicy_plus_deny_incremental_arn       = module.tool_testing_test_effective_permissions_evaluation[0].role_notadmin_adminpolicy_plus_deny_incremental_arn
    role_notadmin_split_allow_plus_denyall_name               = module.tool_testing_test_effective_permissions_evaluation[0].role_notadmin_split_allow_plus_denyall_name
    role_notadmin_split_allow_plus_denyall_arn                = module.tool_testing_test_effective_permissions_evaluation[0].role_notadmin_split_allow_plus_denyall_arn

    # notAdmin Users - Single Boundary (3 users)
    user_notadmin_adminpolicy_plus_boundary_allows_nothing_name                 = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_boundary_allows_nothing_name
    user_notadmin_adminpolicy_plus_boundary_allows_nothing_arn                  = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_boundary_allows_nothing_arn
    user_notadmin_adminpolicy_plus_boundary_allows_nothing_access_key_id        = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_boundary_allows_nothing_access_key_id
    user_notadmin_adminpolicy_plus_boundary_allows_nothing_secret_access_key    = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_boundary_allows_nothing_secret_access_key
    user_notadmin_adminpolicy_plus_boundary_ec2only_name                        = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_boundary_ec2only_name
    user_notadmin_adminpolicy_plus_boundary_ec2only_arn                         = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_boundary_ec2only_arn
    user_notadmin_adminpolicy_plus_boundary_ec2only_access_key_id               = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_boundary_ec2only_access_key_id
    user_notadmin_adminpolicy_plus_boundary_ec2only_secret_access_key           = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_boundary_ec2only_secret_access_key
    user_notadmin_adminpolicy_plus_boundary_notaction_ec2only_name              = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_boundary_notaction_ec2only_name
    user_notadmin_adminpolicy_plus_boundary_notaction_ec2only_arn               = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_boundary_notaction_ec2only_arn
    user_notadmin_adminpolicy_plus_boundary_notaction_ec2only_access_key_id     = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_boundary_notaction_ec2only_access_key_id
    user_notadmin_adminpolicy_plus_boundary_notaction_ec2only_secret_access_key = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_adminpolicy_plus_boundary_notaction_ec2only_secret_access_key

    # notAdmin Roles - Single Boundary (3 roles)
    role_notadmin_adminpolicy_plus_boundary_allows_nothing_name    = module.tool_testing_test_effective_permissions_evaluation[0].role_notadmin_adminpolicy_plus_boundary_allows_nothing_name
    role_notadmin_adminpolicy_plus_boundary_allows_nothing_arn     = module.tool_testing_test_effective_permissions_evaluation[0].role_notadmin_adminpolicy_plus_boundary_allows_nothing_arn
    role_notadmin_adminpolicy_plus_boundary_ec2only_name           = module.tool_testing_test_effective_permissions_evaluation[0].role_notadmin_adminpolicy_plus_boundary_ec2only_name
    role_notadmin_adminpolicy_plus_boundary_ec2only_arn            = module.tool_testing_test_effective_permissions_evaluation[0].role_notadmin_adminpolicy_plus_boundary_ec2only_arn
    role_notadmin_adminpolicy_plus_boundary_notaction_ec2only_name = module.tool_testing_test_effective_permissions_evaluation[0].role_notadmin_adminpolicy_plus_boundary_notaction_ec2only_name
    role_notadmin_adminpolicy_plus_boundary_notaction_ec2only_arn  = module.tool_testing_test_effective_permissions_evaluation[0].role_notadmin_adminpolicy_plus_boundary_notaction_ec2only_arn

    # notAdmin Users - Multi-Policy + Boundary (3 users)
    user_notadmin_split_allow_boundary_allows_nothing_name              = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_split_allow_boundary_allows_nothing_name
    user_notadmin_split_allow_boundary_allows_nothing_arn               = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_split_allow_boundary_allows_nothing_arn
    user_notadmin_split_allow_boundary_allows_nothing_access_key_id     = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_split_allow_boundary_allows_nothing_access_key_id
    user_notadmin_split_allow_boundary_allows_nothing_secret_access_key = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_split_allow_boundary_allows_nothing_secret_access_key
    user_notadmin_split_allow_boundary_ec2only_name                     = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_split_allow_boundary_ec2only_name
    user_notadmin_split_allow_boundary_ec2only_arn                      = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_split_allow_boundary_ec2only_arn
    user_notadmin_split_allow_boundary_ec2only_access_key_id            = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_split_allow_boundary_ec2only_access_key_id
    user_notadmin_split_allow_boundary_ec2only_secret_access_key        = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_split_allow_boundary_ec2only_secret_access_key
    user_notadmin_split_boundary_mismatch_name                          = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_split_boundary_mismatch_name
    user_notadmin_split_boundary_mismatch_arn                           = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_split_boundary_mismatch_arn
    user_notadmin_split_boundary_mismatch_access_key_id                 = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_split_boundary_mismatch_access_key_id
    user_notadmin_split_boundary_mismatch_secret_access_key             = module.tool_testing_test_effective_permissions_evaluation[0].user_notadmin_split_boundary_mismatch_secret_access_key

    # notAdmin Roles - Multi-Policy + Boundary (3 roles)
    role_notadmin_split_allow_boundary_allows_nothing_name = module.tool_testing_test_effective_permissions_evaluation[0].role_notadmin_split_allow_boundary_allows_nothing_name
    role_notadmin_split_allow_boundary_allows_nothing_arn  = module.tool_testing_test_effective_permissions_evaluation[0].role_notadmin_split_allow_boundary_allows_nothing_arn
    role_notadmin_split_allow_boundary_ec2only_name        = module.tool_testing_test_effective_permissions_evaluation[0].role_notadmin_split_allow_boundary_ec2only_name
    role_notadmin_split_allow_boundary_ec2only_arn         = module.tool_testing_test_effective_permissions_evaluation[0].role_notadmin_split_allow_boundary_ec2only_arn
    role_notadmin_split_boundary_mismatch_name             = module.tool_testing_test_effective_permissions_evaluation[0].role_notadmin_split_boundary_mismatch_name
    role_notadmin_split_boundary_mismatch_arn              = module.tool_testing_test_effective_permissions_evaluation[0].role_notadmin_split_boundary_mismatch_arn
  } : null
  sensitive = true
}

output "single_account_privesc_multi_hop_to_bucket_role_chain_to_s3" {
  description = "All outputs for role-chain-to-s3 multi-hop to-bucket scenario"
  value = var.enable_single_account_privesc_multi_hop_to_bucket_role_chain_to_s3 ? {
    starting_user_name              = module.single_account_privesc_multi_hop_to_bucket_role_chain_to_s3[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_multi_hop_to_bucket_role_chain_to_s3[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_multi_hop_to_bucket_role_chain_to_s3[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_multi_hop_to_bucket_role_chain_to_s3[0].starting_user_secret_access_key
    s3_bucket_name                  = module.single_account_privesc_multi_hop_to_bucket_role_chain_to_s3[0].s3_bucket_name
    s3_bucket_arn                   = module.single_account_privesc_multi_hop_to_bucket_role_chain_to_s3[0].s3_bucket_arn
    initial_role_arn                = module.single_account_privesc_multi_hop_to_bucket_role_chain_to_s3[0].initial_role_arn
    initial_role_name               = module.single_account_privesc_multi_hop_to_bucket_role_chain_to_s3[0].initial_role_name
    intermediate_role_arn           = module.single_account_privesc_multi_hop_to_bucket_role_chain_to_s3[0].intermediate_role_arn
    intermediate_role_name          = module.single_account_privesc_multi_hop_to_bucket_role_chain_to_s3[0].intermediate_role_name
    s3_access_role_arn              = module.single_account_privesc_multi_hop_to_bucket_role_chain_to_s3[0].s3_access_role_arn
    s3_access_role_name             = module.single_account_privesc_multi_hop_to_bucket_role_chain_to_s3[0].s3_access_role_name
    chain_user_name                 = module.single_account_privesc_multi_hop_to_bucket_role_chain_to_s3[0].chain_user_name
    attack_path                     = module.single_account_privesc_multi_hop_to_bucket_role_chain_to_s3[0].attack_path
  } : null
  sensitive = true
}

##############################################################################
# CROSS-ACCOUNT SCENARIO GROUPED OUTPUTS
##############################################################################

output "cross_account_dev_to_prod_one_hop_simple_role_assumption" {
  description = "All outputs for cross-account dev-to-prod simple-role-assumption scenario"
  value = var.enable_cross_account_dev_to_prod_one_hop_simple_role_assumption ? {
    starting_user_name              = module.cross_account_dev_to_prod_one_hop_simple_role_assumption[0].starting_user_name
    starting_user_arn               = module.cross_account_dev_to_prod_one_hop_simple_role_assumption[0].starting_user_arn
    starting_user_access_key_id     = module.cross_account_dev_to_prod_one_hop_simple_role_assumption[0].starting_user_access_key_id
    starting_user_secret_access_key = module.cross_account_dev_to_prod_one_hop_simple_role_assumption[0].starting_user_secret_access_key
    target_role_arn                 = module.cross_account_dev_to_prod_one_hop_simple_role_assumption[0].target_role_arn
    target_role_name                = module.cross_account_dev_to_prod_one_hop_simple_role_assumption[0].target_role_name
    attack_path                     = module.cross_account_dev_to_prod_one_hop_simple_role_assumption[0].attack_path
  } : null
  sensitive = true
}

output "cross_account_dev_to_prod_one_hop_root_trust_role_assumption" {
  description = "All outputs for cross-account dev-to-prod root-trust-role-assumption scenario"
  value = var.enable_cross_account_dev_to_prod_one_hop_root_trust_role_assumption ? {
    starting_user_name              = module.cross_account_dev_to_prod_one_hop_root_trust_role_assumption[0].starting_user_name
    starting_user_arn               = module.cross_account_dev_to_prod_one_hop_root_trust_role_assumption[0].starting_user_arn
    starting_user_access_key_id     = module.cross_account_dev_to_prod_one_hop_root_trust_role_assumption[0].starting_user_access_key_id
    starting_user_secret_access_key = module.cross_account_dev_to_prod_one_hop_root_trust_role_assumption[0].starting_user_secret_access_key
    target_role_name                = module.cross_account_dev_to_prod_one_hop_root_trust_role_assumption[0].target_role_name
    target_role_arn                 = module.cross_account_dev_to_prod_one_hop_root_trust_role_assumption[0].target_role_arn
    attack_path                     = module.cross_account_dev_to_prod_one_hop_root_trust_role_assumption[0].attack_path
  } : null
  sensitive = true
}