# Outputs for pathfinder starting users
output "dev_pathfinder_starting_user_access_key_id" {
  description = "Access key ID for the pathfinder starting user in dev environment"
  value       = module.dev_environment.pathfinder_starting_user_access_key_id
  sensitive   = true
}

output "dev_pathfinder_starting_user_secret_access_key" {
  description = "Secret access key for the pathfinder starting user in dev environment"
  value       = module.dev_environment.pathfinder_starting_user_secret_access_key
  sensitive   = true
}


output "operations_pathfinder_starting_user_access_key_id" {
  description = "Access key ID for the pathfinder starting user in operations environment"
  value       = module.ops_environment.pathfinder_starting_user_access_key_id
  sensitive   = true
}

output "operations_pathfinder_starting_user_secret_access_key" {
  description = "Secret access key for the pathfinder starting user in operations environment"
  value       = module.ops_environment.pathfinder_starting_user_secret_access_key
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
  value       = module.dev_environment.admin_user_for_cleanup_access_key_id
  sensitive   = true
}

output "dev_admin_user_for_cleanup_secret_access_key" {
  description = "Secret access key for the admin cleanup user in dev environment"
  value       = module.dev_environment.admin_user_for_cleanup_secret_access_key
  sensitive   = true
}

output "prod_admin_user_for_cleanup_access_key_id" {
  description = "Access key ID for the admin cleanup user in prod environment"
  value       = module.prod_environment.admin_user_for_cleanup_access_key_id
  sensitive   = true
}

output "prod_admin_user_for_cleanup_secret_access_key" {
  description = "Secret access key for the admin cleanup user in prod environment"
  value       = module.prod_environment.admin_user_for_cleanup_secret_access_key
  sensitive   = true
}

output "operations_admin_user_for_cleanup_access_key_id" {
  description = "Access key ID for the admin cleanup user in operations environment"
  value       = module.ops_environment.admin_user_for_cleanup_access_key_id
  sensitive   = true
}

output "operations_admin_user_for_cleanup_secret_access_key" {
  description = "Secret access key for the admin cleanup user in operations environment"
  value       = module.ops_environment.admin_user_for_cleanup_secret_access_key
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
  description = "ID of the prod account"
  value       = var.prod_account_id
}

output "dev_account_id" {
  description = "ID of the dev account"
  value       = var.dev_account_id
}

output "operations_account_id" {
  description = "ID of the operations account"
  value       = var.operations_account_id
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
output "single_account_privesc_self_escalation_to_admin_iam_attachuserpolicy" {
  description = "All outputs for iam-attachuserpolicy self-escalation scenario"
  value = var.enable_single_account_privesc_self_escalation_to_admin_iam_attachuserpolicy ? {
    starting_user_name              = module.single_account_privesc_self_escalation_to_admin_iam_attachuserpolicy[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_self_escalation_to_admin_iam_attachuserpolicy[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_self_escalation_to_admin_iam_attachuserpolicy[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_self_escalation_to_admin_iam_attachuserpolicy[0].starting_user_secret_access_key
    attack_path                     = module.single_account_privesc_self_escalation_to_admin_iam_attachuserpolicy[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_self_escalation_to_admin_iam_putuserpolicy" {
  description = "All outputs for iam-putuserpolicy self-escalation scenario"
  value = var.enable_single_account_privesc_self_escalation_to_admin_iam_putuserpolicy ? {
    starting_user_name              = module.single_account_privesc_self_escalation_to_admin_iam_putuserpolicy[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_self_escalation_to_admin_iam_putuserpolicy[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_self_escalation_to_admin_iam_putuserpolicy[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_self_escalation_to_admin_iam_putuserpolicy[0].starting_user_secret_access_key
    attack_path                     = module.single_account_privesc_self_escalation_to_admin_iam_putuserpolicy[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_self_escalation_to_admin_iam_putrolepolicy" {
  description = "All outputs for iam-putrolepolicy self-escalation scenario"
  value = var.enable_single_account_privesc_self_escalation_to_admin_iam_putrolepolicy ? {
    starting_user_name              = module.single_account_privesc_self_escalation_to_admin_iam_putrolepolicy[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_self_escalation_to_admin_iam_putrolepolicy[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_self_escalation_to_admin_iam_putrolepolicy[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_self_escalation_to_admin_iam_putrolepolicy[0].starting_user_secret_access_key
    starting_role_arn               = module.single_account_privesc_self_escalation_to_admin_iam_putrolepolicy[0].starting_role_arn
    starting_role_name              = module.single_account_privesc_self_escalation_to_admin_iam_putrolepolicy[0].starting_role_name
    policy_arn                      = module.single_account_privesc_self_escalation_to_admin_iam_putrolepolicy[0].policy_arn
    attack_path                     = module.single_account_privesc_self_escalation_to_admin_iam_putrolepolicy[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_self_escalation_to_admin_iam_attachrolepolicy" {
  description = "All outputs for iam-attachrolepolicy self-escalation scenario"
  value = var.enable_single_account_privesc_self_escalation_to_admin_iam_attachrolepolicy ? {
    starting_user_name              = module.single_account_privesc_self_escalation_to_admin_iam_attachrolepolicy[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_self_escalation_to_admin_iam_attachrolepolicy[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_self_escalation_to_admin_iam_attachrolepolicy[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_self_escalation_to_admin_iam_attachrolepolicy[0].starting_user_secret_access_key
    starting_role_arn               = module.single_account_privesc_self_escalation_to_admin_iam_attachrolepolicy[0].starting_role_arn
    starting_role_name              = module.single_account_privesc_self_escalation_to_admin_iam_attachrolepolicy[0].starting_role_name
    policy_arn                      = module.single_account_privesc_self_escalation_to_admin_iam_attachrolepolicy[0].policy_arn
    attack_path                     = module.single_account_privesc_self_escalation_to_admin_iam_attachrolepolicy[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_self_escalation_to_admin_iam_createpolicyversion" {
  description = "All outputs for iam-createpolicyversion self-escalation scenario"
  value = var.enable_single_account_privesc_self_escalation_to_admin_iam_createpolicyversion ? {
    starting_user_name              = module.single_account_privesc_self_escalation_to_admin_iam_createpolicyversion[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_self_escalation_to_admin_iam_createpolicyversion[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_self_escalation_to_admin_iam_createpolicyversion[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_self_escalation_to_admin_iam_createpolicyversion[0].starting_user_secret_access_key
    starting_role_arn               = module.single_account_privesc_self_escalation_to_admin_iam_createpolicyversion[0].starting_role_arn
    starting_role_name              = module.single_account_privesc_self_escalation_to_admin_iam_createpolicyversion[0].starting_role_name
    policy_arn                      = module.single_account_privesc_self_escalation_to_admin_iam_createpolicyversion[0].policy_arn
    attack_path                     = module.single_account_privesc_self_escalation_to_admin_iam_createpolicyversion[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_self_escalation_to_admin_iam_addusertogroup" {
  description = "All outputs for iam-addusertogroup self-escalation scenario"
  value = var.enable_single_account_privesc_self_escalation_to_admin_iam_addusertogroup ? {
    start_user_name              = module.single_account_privesc_self_escalation_to_admin_iam_addusertogroup[0].start_user_name
    start_user_arn               = module.single_account_privesc_self_escalation_to_admin_iam_addusertogroup[0].start_user_arn
    start_user_access_key_id     = module.single_account_privesc_self_escalation_to_admin_iam_addusertogroup[0].start_user_access_key_id
    start_user_secret_access_key = module.single_account_privesc_self_escalation_to_admin_iam_addusertogroup[0].start_user_secret_access_key
    admin_group_name             = module.single_account_privesc_self_escalation_to_admin_iam_addusertogroup[0].admin_group_name
    admin_group_arn              = module.single_account_privesc_self_escalation_to_admin_iam_addusertogroup[0].admin_group_arn
    attack_path                  = module.single_account_privesc_self_escalation_to_admin_iam_addusertogroup[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_self_escalation_to_admin_iam_attachgrouppolicy" {
  description = "All outputs for iam-attachgrouppolicy self-escalation scenario"
  value = var.enable_single_account_privesc_self_escalation_to_admin_iam_attachgrouppolicy ? {
    starting_user_name              = module.single_account_privesc_self_escalation_to_admin_iam_attachgrouppolicy[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_self_escalation_to_admin_iam_attachgrouppolicy[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_self_escalation_to_admin_iam_attachgrouppolicy[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_self_escalation_to_admin_iam_attachgrouppolicy[0].starting_user_secret_access_key
    group_name                      = module.single_account_privesc_self_escalation_to_admin_iam_attachgrouppolicy[0].group_name
    group_arn                       = module.single_account_privesc_self_escalation_to_admin_iam_attachgrouppolicy[0].group_arn
    attack_path                     = module.single_account_privesc_self_escalation_to_admin_iam_attachgrouppolicy[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_self_escalation_to_admin_iam_putgrouppolicy" {
  description = "All outputs for iam-putgrouppolicy self-escalation scenario"
  value = var.enable_single_account_privesc_self_escalation_to_admin_iam_putgrouppolicy ? {
    privesc_user_name              = module.single_account_privesc_self_escalation_to_admin_iam_putgrouppolicy[0].privesc_user_name
    privesc_user_arn               = module.single_account_privesc_self_escalation_to_admin_iam_putgrouppolicy[0].privesc_user_arn
    privesc_user_access_key_id     = module.single_account_privesc_self_escalation_to_admin_iam_putgrouppolicy[0].privesc_user_access_key_id
    privesc_user_secret_access_key = module.single_account_privesc_self_escalation_to_admin_iam_putgrouppolicy[0].privesc_user_secret_access_key
    target_group_name              = module.single_account_privesc_self_escalation_to_admin_iam_putgrouppolicy[0].target_group_name
    target_group_arn               = module.single_account_privesc_self_escalation_to_admin_iam_putgrouppolicy[0].target_group_arn
    attack_path                    = module.single_account_privesc_self_escalation_to_admin_iam_putgrouppolicy[0].attack_path
  } : null
  sensitive = true
}

# One-hop to-admin scenarios
output "single_account_privesc_one_hop_to_admin_iam_attachrolepolicy_sts_assumerole" {
  description = "All outputs for iam-attachrolepolicy+sts-assumerole one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_attachrolepolicy_sts_assumerole ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_attachrolepolicy_sts_assumerole[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_attachrolepolicy_sts_assumerole[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_attachrolepolicy_sts_assumerole[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_attachrolepolicy_sts_assumerole[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_iam_attachrolepolicy_sts_assumerole[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_iam_attachrolepolicy_sts_assumerole[0].target_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_attachrolepolicy_sts_assumerole[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_attachuserpolicy_iam_createaccesskey" {
  description = "All outputs for iam-attachuserpolicy+iam-createaccesskey one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_attachuserpolicy_iam_createaccesskey ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_attachuserpolicy_iam_createaccesskey[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_attachuserpolicy_iam_createaccesskey[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_attachuserpolicy_iam_createaccesskey[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_attachuserpolicy_iam_createaccesskey[0].starting_user_secret_access_key
    target_user_name                = module.single_account_privesc_one_hop_to_admin_iam_attachuserpolicy_iam_createaccesskey[0].target_user_name
    target_user_arn                 = module.single_account_privesc_one_hop_to_admin_iam_attachuserpolicy_iam_createaccesskey[0].target_user_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_attachuserpolicy_iam_createaccesskey[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_apprunner_updateservice" {
  description = "All outputs for apprunner-updateservice one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_apprunner_updateservice ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_apprunner_updateservice[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_apprunner_updateservice[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_apprunner_updateservice[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_apprunner_updateservice[0].starting_user_secret_access_key
    target_service_name             = module.single_account_privesc_one_hop_to_admin_apprunner_updateservice[0].target_service_name
    target_service_arn              = module.single_account_privesc_one_hop_to_admin_apprunner_updateservice[0].target_service_arn
    target_role_name                = module.single_account_privesc_one_hop_to_admin_apprunner_updateservice[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_apprunner_updateservice[0].target_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_apprunner_updateservice[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_updateassumerolepolicy" {
  description = "All outputs for iam-updateassumerolepolicy one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_updateassumerolepolicy ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_updateassumerolepolicy[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_updateassumerolepolicy[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_updateassumerolepolicy[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_updateassumerolepolicy[0].starting_user_secret_access_key
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_iam_updateassumerolepolicy[0].target_role_arn
    target_role_name                = module.single_account_privesc_one_hop_to_admin_iam_updateassumerolepolicy[0].target_role_name
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_updateassumerolepolicy[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_createloginprofile" {
  description = "All outputs for iam-createloginprofile one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_createloginprofile ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_createloginprofile[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_createloginprofile[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_createloginprofile[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_createloginprofile[0].starting_user_secret_access_key
    starting_role_arn               = module.single_account_privesc_one_hop_to_admin_iam_createloginprofile[0].starting_role_arn
    starting_role_name              = module.single_account_privesc_one_hop_to_admin_iam_createloginprofile[0].starting_role_name
    admin_user_arn                  = module.single_account_privesc_one_hop_to_admin_iam_createloginprofile[0].admin_user_arn
    admin_user_name                 = module.single_account_privesc_one_hop_to_admin_iam_createloginprofile[0].admin_user_name
    admin_access_key_id             = module.single_account_privesc_one_hop_to_admin_iam_createloginprofile[0].admin_access_key_id
    admin_secret_access_key         = module.single_account_privesc_one_hop_to_admin_iam_createloginprofile[0].admin_secret_access_key
    console_login_url               = module.single_account_privesc_one_hop_to_admin_iam_createloginprofile[0].console_login_url
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_createloginprofile[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_createpolicyversion_sts_assumerole" {
  description = "All outputs for iam-createpolicyversion+sts-assumerole one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_createpolicyversion_sts_assumerole ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_createpolicyversion_sts_assumerole[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_createpolicyversion_sts_assumerole[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_createpolicyversion_sts_assumerole[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_createpolicyversion_sts_assumerole[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_iam_createpolicyversion_sts_assumerole[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_iam_createpolicyversion_sts_assumerole[0].target_role_arn
    target_policy_name              = module.single_account_privesc_one_hop_to_admin_iam_createpolicyversion_sts_assumerole[0].target_policy_name
    target_policy_arn               = module.single_account_privesc_one_hop_to_admin_iam_createpolicyversion_sts_assumerole[0].target_policy_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_createpolicyversion_sts_assumerole[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_updateloginprofile" {
  description = "All outputs for iam-updateloginprofile one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_updateloginprofile ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_updateloginprofile[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_updateloginprofile[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_updateloginprofile[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_updateloginprofile[0].starting_user_secret_access_key
    admin_user_arn                  = module.single_account_privesc_one_hop_to_admin_iam_updateloginprofile[0].admin_user_arn
    admin_user_name                 = module.single_account_privesc_one_hop_to_admin_iam_updateloginprofile[0].admin_user_name
    original_password               = module.single_account_privesc_one_hop_to_admin_iam_updateloginprofile[0].original_password
    console_login_url               = module.single_account_privesc_one_hop_to_admin_iam_updateloginprofile[0].console_login_url
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_updateloginprofile[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_sts_assumerole" {
  description = "All outputs for sts-assumerole one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_sts_assumerole ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_sts_assumerole[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_sts_assumerole[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_sts_assumerole[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_sts_assumerole[0].starting_user_secret_access_key
    admin_role_arn                  = module.single_account_privesc_one_hop_to_admin_sts_assumerole[0].admin_role_arn
    admin_role_name                 = module.single_account_privesc_one_hop_to_admin_sts_assumerole[0].admin_role_name
    attack_path                     = module.single_account_privesc_one_hop_to_admin_sts_assumerole[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_createaccesskey" {
  description = "All outputs for iam-createaccesskey one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_createaccesskey ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_createaccesskey[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_createaccesskey[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_createaccesskey[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_createaccesskey[0].starting_user_secret_access_key
    admin_user_name                 = module.single_account_privesc_one_hop_to_admin_iam_createaccesskey[0].admin_user_name
    admin_user_arn                  = module.single_account_privesc_one_hop_to_admin_iam_createaccesskey[0].admin_user_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_createaccesskey[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_passrole_apprunner_createservice" {
  description = "All outputs for iam-passrole+apprunner-createservice one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_passrole_apprunner_createservice ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_passrole_apprunner_createservice[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_passrole_apprunner_createservice[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_passrole_apprunner_createservice[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_passrole_apprunner_createservice[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_iam_passrole_apprunner_createservice[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_iam_passrole_apprunner_createservice[0].target_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_passrole_apprunner_createservice[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_passrole_bedrockagentcore_codeinterpreter" {
  description = "All outputs for iam-passrole+bedrockagentcore-codeinterpreter one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_passrole_bedrockagentcore_codeinterpreter ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_passrole_bedrockagentcore_codeinterpreter[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_passrole_bedrockagentcore_codeinterpreter[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_passrole_bedrockagentcore_codeinterpreter[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_passrole_bedrockagentcore_codeinterpreter[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_iam_passrole_bedrockagentcore_codeinterpreter[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_iam_passrole_bedrockagentcore_codeinterpreter[0].target_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_passrole_bedrockagentcore_codeinterpreter[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_bedrockagentcore_startsession_invoke" {
  description = "All outputs for bedrockagentcore-startsession+invoke one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_bedrockagentcore_startsession_invoke ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_bedrockagentcore_startsession_invoke[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_bedrockagentcore_startsession_invoke[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_bedrockagentcore_startsession_invoke[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_bedrockagentcore_startsession_invoke[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_bedrockagentcore_startsession_invoke[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_bedrockagentcore_startsession_invoke[0].target_role_arn
    existing_interpreter_id         = module.single_account_privesc_one_hop_to_admin_bedrockagentcore_startsession_invoke[0].existing_interpreter_id
    existing_interpreter_arn        = module.single_account_privesc_one_hop_to_admin_bedrockagentcore_startsession_invoke[0].existing_interpreter_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_bedrockagentcore_startsession_invoke[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_passrole_ec2_runinstances" {
  description = "All outputs for iam-passrole+ec2-runinstances one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_passrole_ec2_runinstances ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_passrole_ec2_runinstances[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_passrole_ec2_runinstances[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_passrole_ec2_runinstances[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_passrole_ec2_runinstances[0].starting_user_secret_access_key
    admin_role_arn                  = module.single_account_privesc_one_hop_to_admin_iam_passrole_ec2_runinstances[0].admin_role_arn
    admin_role_name                 = module.single_account_privesc_one_hop_to_admin_iam_passrole_ec2_runinstances[0].admin_role_name
    instance_profile_arn            = module.single_account_privesc_one_hop_to_admin_iam_passrole_ec2_runinstances[0].instance_profile_arn
    instance_profile_name           = module.single_account_privesc_one_hop_to_admin_iam_passrole_ec2_runinstances[0].instance_profile_name
    security_group_id               = module.single_account_privesc_one_hop_to_admin_iam_passrole_ec2_runinstances[0].security_group_id
    default_subnet_id               = module.single_account_privesc_one_hop_to_admin_iam_passrole_ec2_runinstances[0].default_subnet_id
    ami_id                          = module.single_account_privesc_one_hop_to_admin_iam_passrole_ec2_runinstances[0].ami_id
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_passrole_ec2_runinstances[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_passrole_glue_createdevendpoint" {
  description = "All outputs for iam-passrole+glue-createdevendpoint one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_passrole_glue_createdevendpoint ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_createdevendpoint[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_createdevendpoint[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_createdevendpoint[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_createdevendpoint[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_createdevendpoint[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_createdevendpoint[0].target_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_createdevendpoint[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_glue_updatedevendpoint" {
  description = "All outputs for glue-updatedevendpoint one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_glue_updatedevendpoint ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_glue_updatedevendpoint[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_glue_updatedevendpoint[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_glue_updatedevendpoint[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_glue_updatedevendpoint[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_glue_updatedevendpoint[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_glue_updatedevendpoint[0].target_role_arn
    dev_endpoint_name               = module.single_account_privesc_one_hop_to_admin_glue_updatedevendpoint[0].dev_endpoint_name
    dev_endpoint_arn                = module.single_account_privesc_one_hop_to_admin_glue_updatedevendpoint[0].dev_endpoint_arn
    dev_endpoint_address            = module.single_account_privesc_one_hop_to_admin_glue_updatedevendpoint[0].dev_endpoint_address
    attack_path                     = module.single_account_privesc_one_hop_to_admin_glue_updatedevendpoint[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_passrole_glue_createjob_glue_createtrigger" {
  description = "All outputs for iam-passrole+glue-createjob+glue-createtrigger one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_passrole_glue_createjob_glue_createtrigger ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_createjob_glue_createtrigger[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_createjob_glue_createtrigger[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_createjob_glue_createtrigger[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_createjob_glue_createtrigger[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_createjob_glue_createtrigger[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_createjob_glue_createtrigger[0].target_role_arn
    script_bucket_name              = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_createjob_glue_createtrigger[0].script_bucket_name
    script_s3_path                  = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_createjob_glue_createtrigger[0].script_s3_path
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_createjob_glue_createtrigger[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_passrole_glue_createjob_glue_startjobrun" {
  description = "All outputs for iam-passrole+glue-createjob+glue-startjobrun one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_passrole_glue_createjob_glue_startjobrun ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_createjob_glue_startjobrun[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_createjob_glue_startjobrun[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_createjob_glue_startjobrun[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_createjob_glue_startjobrun[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_createjob_glue_startjobrun[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_createjob_glue_startjobrun[0].target_role_arn
    script_bucket_name              = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_createjob_glue_startjobrun[0].script_bucket_name
    script_s3_path                  = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_createjob_glue_startjobrun[0].script_s3_path
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_createjob_glue_startjobrun[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_startjobrun" {
  description = "All outputs for iam-passrole+glue-updatejob+glue-startjobrun one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_startjobrun ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_startjobrun[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_startjobrun[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_startjobrun[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_startjobrun[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_startjobrun[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_startjobrun[0].target_role_arn
    initial_role_name               = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_startjobrun[0].initial_role_name
    initial_role_arn                = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_startjobrun[0].initial_role_arn
    glue_job_name                   = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_startjobrun[0].glue_job_name
    script_bucket_name              = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_startjobrun[0].script_bucket_name
    benign_script_s3_path           = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_startjobrun[0].benign_script_s3_path
    malicious_script_s3_path        = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_startjobrun[0].malicious_script_s3_path
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_startjobrun[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_createtrigger" {
  description = "All outputs for iam-passrole+glue-updatejob+glue-createtrigger one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_createtrigger ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_createtrigger[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_createtrigger[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_createtrigger[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_createtrigger[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_createtrigger[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_createtrigger[0].target_role_arn
    initial_role_name               = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_createtrigger[0].initial_role_name
    initial_role_arn                = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_createtrigger[0].initial_role_arn
    glue_job_name                   = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_createtrigger[0].glue_job_name
    script_bucket_name              = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_createtrigger[0].script_bucket_name
    benign_script_s3_path           = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_createtrigger[0].benign_script_s3_path
    malicious_script_s3_path        = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_createtrigger[0].malicious_script_s3_path
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_createtrigger[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_passrole_lambda" {
  description = "All outputs for iam-passrole+lambda one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction[0].starting_user_secret_access_key
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction[0].target_role_arn
    target_role_name                = module.single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction[0].target_role_name
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction[0].attack_path
  } : null
  sensitive = true
}

# Self-escalation to-bucket scenarios
output "single_account_privesc_self_escalation_to_bucket_iam_putrolepolicy" {
  description = "All outputs for iam-putrolepolicy self-escalation to-bucket scenario"
  value = var.enable_single_account_privesc_self_escalation_to_bucket_iam_putrolepolicy ? {
    starting_user_name              = module.single_account_privesc_self_escalation_to_bucket_iam_putrolepolicy[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_self_escalation_to_bucket_iam_putrolepolicy[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_self_escalation_to_bucket_iam_putrolepolicy[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_self_escalation_to_bucket_iam_putrolepolicy[0].starting_user_secret_access_key
    starting_role_arn               = module.single_account_privesc_self_escalation_to_bucket_iam_putrolepolicy[0].starting_role_arn
    starting_role_name              = module.single_account_privesc_self_escalation_to_bucket_iam_putrolepolicy[0].starting_role_name
    target_role_arn                 = module.single_account_privesc_self_escalation_to_bucket_iam_putrolepolicy[0].target_role_arn
    target_role_name                = module.single_account_privesc_self_escalation_to_bucket_iam_putrolepolicy[0].target_role_name
    bucket_name                     = module.single_account_privesc_self_escalation_to_bucket_iam_putrolepolicy[0].bucket_name
    bucket_arn                      = module.single_account_privesc_self_escalation_to_bucket_iam_putrolepolicy[0].bucket_arn
    attack_path                     = module.single_account_privesc_self_escalation_to_bucket_iam_putrolepolicy[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_self_escalation_to_bucket_iam_attachrolepolicy" {
  description = "All outputs for iam-attachrolepolicy self-escalation to-bucket scenario"
  value = var.enable_single_account_privesc_self_escalation_to_bucket_iam_attachrolepolicy ? {
    starting_user_name              = module.single_account_privesc_self_escalation_to_bucket_iam_attachrolepolicy[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_self_escalation_to_bucket_iam_attachrolepolicy[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_self_escalation_to_bucket_iam_attachrolepolicy[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_self_escalation_to_bucket_iam_attachrolepolicy[0].starting_user_secret_access_key
    starting_role_arn               = module.single_account_privesc_self_escalation_to_bucket_iam_attachrolepolicy[0].starting_role_arn
    starting_role_name              = module.single_account_privesc_self_escalation_to_bucket_iam_attachrolepolicy[0].starting_role_name
    bucket_name                     = module.single_account_privesc_self_escalation_to_bucket_iam_attachrolepolicy[0].bucket_name
    bucket_arn                      = module.single_account_privesc_self_escalation_to_bucket_iam_attachrolepolicy[0].bucket_arn
    bucket_access_policy_arn        = module.single_account_privesc_self_escalation_to_bucket_iam_attachrolepolicy[0].bucket_access_policy_arn
    attack_path                     = module.single_account_privesc_self_escalation_to_bucket_iam_attachrolepolicy[0].attack_path
  } : null
  sensitive = true
}

# One-hop to-bucket scenarios
output "single_account_privesc_one_hop_to_bucket_iam_updateassumerolepolicy" {
  description = "All outputs for iam-updateassumerolepolicy one-hop to-bucket scenario"
  value = var.enable_single_account_privesc_one_hop_to_bucket_iam_updateassumerolepolicy ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_bucket_iam_updateassumerolepolicy[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_bucket_iam_updateassumerolepolicy[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_bucket_iam_updateassumerolepolicy[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_bucket_iam_updateassumerolepolicy[0].starting_user_secret_access_key
    starting_role_arn               = module.single_account_privesc_one_hop_to_bucket_iam_updateassumerolepolicy[0].starting_role_arn
    starting_role_name              = module.single_account_privesc_one_hop_to_bucket_iam_updateassumerolepolicy[0].starting_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_bucket_iam_updateassumerolepolicy[0].target_role_arn
    target_role_name                = module.single_account_privesc_one_hop_to_bucket_iam_updateassumerolepolicy[0].target_role_name
    bucket_name                     = module.single_account_privesc_one_hop_to_bucket_iam_updateassumerolepolicy[0].bucket_name
    bucket_arn                      = module.single_account_privesc_one_hop_to_bucket_iam_updateassumerolepolicy[0].bucket_arn
    attack_path                     = module.single_account_privesc_one_hop_to_bucket_iam_updateassumerolepolicy[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_passrole_cloudformation" {
  description = "All outputs for iam-passrole-cloudformation one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_passrole_cloudformation ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_passrole_cloudformation[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_passrole_cloudformation[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_passrole_cloudformation[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_passrole_cloudformation[0].starting_user_secret_access_key
    admin_role_arn                  = module.single_account_privesc_one_hop_to_admin_iam_passrole_cloudformation[0].admin_role_arn
    admin_role_name                 = module.single_account_privesc_one_hop_to_admin_iam_passrole_cloudformation[0].admin_role_name
    escalated_role_name             = module.single_account_privesc_one_hop_to_admin_iam_passrole_cloudformation[0].escalated_role_name
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_passrole_cloudformation[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_passrole_codebuild_createproject_codebuild_startbuild" {
  description = "All outputs for iam-passrole+codebuild-createproject+codebuild-startbuild one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_passrole_codebuild_createproject_codebuild_startbuild ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_passrole_codebuild_createproject_codebuild_startbuild[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_passrole_codebuild_createproject_codebuild_startbuild[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_passrole_codebuild_createproject_codebuild_startbuild[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_passrole_codebuild_createproject_codebuild_startbuild[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_iam_passrole_codebuild_createproject_codebuild_startbuild[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_iam_passrole_codebuild_createproject_codebuild_startbuild[0].target_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_passrole_codebuild_createproject_codebuild_startbuild[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_passrole_codebuild_createproject_codebuild_startbuildbatch" {
  description = "All outputs for iam-passrole+codebuild-createproject+codebuild-startbuildbatch one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_passrole_codebuild_createproject_codebuild_startbuildbatch ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_passrole_codebuild_createproject_codebuild_startbuildbatch[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_passrole_codebuild_createproject_codebuild_startbuildbatch[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_passrole_codebuild_createproject_codebuild_startbuildbatch[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_passrole_codebuild_createproject_codebuild_startbuildbatch[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_iam_passrole_codebuild_createproject_codebuild_startbuildbatch[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_iam_passrole_codebuild_createproject_codebuild_startbuildbatch[0].target_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_passrole_codebuild_createproject_codebuild_startbuildbatch[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_putrolepolicy_sts_assumerole" {
  description = "All outputs for iam-putrolepolicy+sts-assumerole one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_putrolepolicy_sts_assumerole ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_putrolepolicy_sts_assumerole[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_putrolepolicy_sts_assumerole[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_putrolepolicy_sts_assumerole[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_putrolepolicy_sts_assumerole[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_iam_putrolepolicy_sts_assumerole[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_iam_putrolepolicy_sts_assumerole[0].target_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_putrolepolicy_sts_assumerole[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_putuserpolicy_iam_createaccesskey" {
  description = "All outputs for iam-putuserpolicy+iam-createaccesskey one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_putuserpolicy_iam_createaccesskey ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_putuserpolicy_iam_createaccesskey[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_putuserpolicy_iam_createaccesskey[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_putuserpolicy_iam_createaccesskey[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_putuserpolicy_iam_createaccesskey[0].starting_user_secret_access_key
    target_user_name                = module.single_account_privesc_one_hop_to_admin_iam_putuserpolicy_iam_createaccesskey[0].target_user_name
    target_user_arn                 = module.single_account_privesc_one_hop_to_admin_iam_putuserpolicy_iam_createaccesskey[0].target_user_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_putuserpolicy_iam_createaccesskey[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb" {
  description = "All outputs for iam-passrole+lambda-createfunction+createeventsourcemapping-dynamodb one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb[0].target_role_arn
    dynamodb_table_name             = module.single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb[0].dynamodb_table_name
    dynamodb_stream_arn             = module.single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb[0].dynamodb_stream_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_lambda_updatefunctioncode" {
  description = "All outputs for lambda-updatefunctioncode one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_lambda_updatefunctioncode ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_lambda_updatefunctioncode[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_lambda_updatefunctioncode[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_lambda_updatefunctioncode[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_lambda_updatefunctioncode[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_lambda_updatefunctioncode[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_lambda_updatefunctioncode[0].target_role_arn
    target_lambda_function_name     = module.single_account_privesc_one_hop_to_admin_lambda_updatefunctioncode[0].target_lambda_function_name
    target_lambda_function_arn      = module.single_account_privesc_one_hop_to_admin_lambda_updatefunctioncode[0].target_lambda_function_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_lambda_updatefunctioncode[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_ssm_sendcommand" {
  description = "All outputs for ssm-sendcommand one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_ssm_sendcommand ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_ssm_sendcommand[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_ssm_sendcommand[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_ssm_sendcommand[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_ssm_sendcommand[0].starting_user_secret_access_key
    ec2_instance_id                 = module.single_account_privesc_one_hop_to_admin_ssm_sendcommand[0].ec2_instance_id
    ec2_instance_arn                = module.single_account_privesc_one_hop_to_admin_ssm_sendcommand[0].ec2_instance_arn
    ec2_admin_role_name             = module.single_account_privesc_one_hop_to_admin_ssm_sendcommand[0].ec2_admin_role_name
    ec2_admin_role_arn              = module.single_account_privesc_one_hop_to_admin_ssm_sendcommand[0].ec2_admin_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_ssm_sendcommand[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_ssm_startsession" {
  description = "All outputs for ssm-startsession one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_ssm_startsession ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_ssm_startsession[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_ssm_startsession[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_ssm_startsession[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_ssm_startsession[0].starting_user_secret_access_key
    ec2_instance_id                 = module.single_account_privesc_one_hop_to_admin_ssm_startsession[0].ec2_instance_id
    ec2_instance_arn                = module.single_account_privesc_one_hop_to_admin_ssm_startsession[0].ec2_instance_arn
    ec2_admin_role_name             = module.single_account_privesc_one_hop_to_admin_ssm_startsession[0].ec2_admin_role_name
    ec2_admin_role_arn              = module.single_account_privesc_one_hop_to_admin_ssm_startsession[0].ec2_admin_role_arn
    target_admin_role_name          = module.single_account_privesc_one_hop_to_admin_ssm_startsession[0].target_admin_role_name
    target_admin_role_arn           = module.single_account_privesc_one_hop_to_admin_ssm_startsession[0].target_admin_role_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_ssm_startsession[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_codebuild_startbuild" {
  description = "All outputs for codebuild-startbuild one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_codebuild_startbuild ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_codebuild_startbuild[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_codebuild_startbuild[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_codebuild_startbuild[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_codebuild_startbuild[0].starting_user_secret_access_key
    project_role_name               = module.single_account_privesc_one_hop_to_admin_codebuild_startbuild[0].project_role_name
    project_role_arn                = module.single_account_privesc_one_hop_to_admin_codebuild_startbuild[0].project_role_arn
    codebuild_project_name          = module.single_account_privesc_one_hop_to_admin_codebuild_startbuild[0].codebuild_project_name
    codebuild_project_arn           = module.single_account_privesc_one_hop_to_admin_codebuild_startbuild[0].codebuild_project_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_codebuild_startbuild[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_codebuild_startbuildbatch" {
  description = "All outputs for codebuild-startbuildbatch one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_codebuild_startbuildbatch ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_codebuild_startbuildbatch[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_codebuild_startbuildbatch[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_codebuild_startbuildbatch[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_codebuild_startbuildbatch[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_codebuild_startbuildbatch[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_codebuild_startbuildbatch[0].target_role_arn
    codebuild_project_name          = module.single_account_privesc_one_hop_to_admin_codebuild_startbuildbatch[0].codebuild_project_name
    codebuild_project_arn           = module.single_account_privesc_one_hop_to_admin_codebuild_startbuildbatch[0].codebuild_project_arn
    attack_path                     = module.single_account_privesc_one_hop_to_admin_codebuild_startbuildbatch[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_ec2_instance_connect_sendsshpublickey" {
  description = "All outputs for ec2-instance-connect-sendsshpublickey one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_ec2_instance_connect_sendsshpublickey ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_ec2_instance_connect_sendsshpublickey[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_ec2_instance_connect_sendsshpublickey[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_ec2_instance_connect_sendsshpublickey[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_ec2_instance_connect_sendsshpublickey[0].starting_user_secret_access_key
    ec2_instance_id                 = module.single_account_privesc_one_hop_to_admin_ec2_instance_connect_sendsshpublickey[0].ec2_instance_id
    ec2_instance_arn                = module.single_account_privesc_one_hop_to_admin_ec2_instance_connect_sendsshpublickey[0].ec2_instance_arn
    ec2_instance_public_ip          = module.single_account_privesc_one_hop_to_admin_ec2_instance_connect_sendsshpublickey[0].ec2_instance_public_ip
    ec2_admin_role_name             = module.single_account_privesc_one_hop_to_admin_ec2_instance_connect_sendsshpublickey[0].ec2_admin_role_name
    ec2_admin_role_arn              = module.single_account_privesc_one_hop_to_admin_ec2_instance_connect_sendsshpublickey[0].ec2_admin_role_arn
    allowed_ssh_ip                  = module.single_account_privesc_one_hop_to_admin_ec2_instance_connect_sendsshpublickey[0].allowed_ssh_ip
    attack_path                     = module.single_account_privesc_one_hop_to_admin_ec2_instance_connect_sendsshpublickey[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_admin_ec2_modifyinstanceattribute_stopinstances_startinstances" {
  description = "All outputs for ec2-modifyinstanceattribute+stopinstances+startinstances one-hop to-admin scenario"
  value = var.enable_single_account_privesc_one_hop_to_admin_ec2_modifyinstanceattribute_stopinstances_startinstances ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_admin_ec2_modifyinstanceattribute_stopinstances_startinstances[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_admin_ec2_modifyinstanceattribute_stopinstances_startinstances[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_ec2_modifyinstanceattribute_stopinstances_startinstances[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_ec2_modifyinstanceattribute_stopinstances_startinstances[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_admin_ec2_modifyinstanceattribute_stopinstances_startinstances[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_admin_ec2_modifyinstanceattribute_stopinstances_startinstances[0].target_role_arn
    target_instance_id              = module.single_account_privesc_one_hop_to_admin_ec2_modifyinstanceattribute_stopinstances_startinstances[0].target_instance_id
    initial_user_data               = module.single_account_privesc_one_hop_to_admin_ec2_modifyinstanceattribute_stopinstances_startinstances[0].initial_user_data
    attack_path                     = module.single_account_privesc_one_hop_to_admin_ec2_modifyinstanceattribute_stopinstances_startinstances[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_bucket_iam_createaccesskey" {
  description = "All outputs for iam-createaccesskey one-hop to-bucket scenario"
  value = var.enable_single_account_privesc_one_hop_to_bucket_iam_createaccesskey ? {
    privesc_user_name               = module.single_account_privesc_one_hop_to_bucket_iam_createaccesskey[0].privesc_user_name
    privesc_user_access_key_id      = module.single_account_privesc_one_hop_to_bucket_iam_createaccesskey[0].privesc_user_access_key_id
    privesc_user_secret_access_key  = module.single_account_privesc_one_hop_to_bucket_iam_createaccesskey[0].privesc_user_secret_access_key
    bucket_access_user_name         = module.single_account_privesc_one_hop_to_bucket_iam_createaccesskey[0].bucket_access_user_name
    target_bucket_name              = module.single_account_privesc_one_hop_to_bucket_iam_createaccesskey[0].target_bucket_name
    attack_path                     = module.single_account_privesc_one_hop_to_bucket_iam_createaccesskey[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_bucket_iam_createloginprofile" {
  description = "All outputs for iam-createloginprofile one-hop to-bucket scenario"
  value = var.enable_single_account_privesc_one_hop_to_bucket_iam_createloginprofile ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_bucket_iam_createloginprofile[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_bucket_iam_createloginprofile[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_bucket_iam_createloginprofile[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_bucket_iam_createloginprofile[0].starting_user_secret_access_key
    hop1_user_name                  = module.single_account_privesc_one_hop_to_bucket_iam_createloginprofile[0].hop1_user_name
    hop1_user_arn                   = module.single_account_privesc_one_hop_to_bucket_iam_createloginprofile[0].hop1_user_arn
    sensitive_bucket_name           = module.single_account_privesc_one_hop_to_bucket_iam_createloginprofile[0].sensitive_bucket_name
    sensitive_bucket_arn            = module.single_account_privesc_one_hop_to_bucket_iam_createloginprofile[0].sensitive_bucket_arn
    console_login_url               = module.single_account_privesc_one_hop_to_bucket_iam_createloginprofile[0].console_login_url
    attack_path                     = module.single_account_privesc_one_hop_to_bucket_iam_createloginprofile[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_bucket_sts_assumerole" {
  description = "All outputs for sts-assumerole one-hop to-bucket scenario"
  value = var.enable_single_account_privesc_one_hop_to_bucket_sts_assumerole ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_bucket_sts_assumerole[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_bucket_sts_assumerole[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_bucket_sts_assumerole[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_bucket_sts_assumerole[0].starting_user_secret_access_key
    bucket_access_role_arn          = module.single_account_privesc_one_hop_to_bucket_sts_assumerole[0].bucket_access_role_arn
    target_bucket_name              = module.single_account_privesc_one_hop_to_bucket_sts_assumerole[0].target_bucket_name
    attack_path                     = module.single_account_privesc_one_hop_to_bucket_sts_assumerole[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_bucket_iam_updateloginprofile" {
  description = "All outputs for iam-updateloginprofile one-hop to-bucket scenario"
  value = var.enable_single_account_privesc_one_hop_to_bucket_iam_updateloginprofile ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_bucket_iam_updateloginprofile[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_bucket_iam_updateloginprofile[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_bucket_iam_updateloginprofile[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_bucket_iam_updateloginprofile[0].starting_user_secret_access_key
    target_user_name                = module.single_account_privesc_one_hop_to_bucket_iam_updateloginprofile[0].target_user_name
    target_user_arn                 = module.single_account_privesc_one_hop_to_bucket_iam_updateloginprofile[0].target_user_arn
    original_password               = module.single_account_privesc_one_hop_to_bucket_iam_updateloginprofile[0].original_password
    sensitive_bucket_name           = module.single_account_privesc_one_hop_to_bucket_iam_updateloginprofile[0].sensitive_bucket_name
    sensitive_bucket_arn            = module.single_account_privesc_one_hop_to_bucket_iam_updateloginprofile[0].sensitive_bucket_arn
    console_login_url               = module.single_account_privesc_one_hop_to_bucket_iam_updateloginprofile[0].console_login_url
    attack_path                     = module.single_account_privesc_one_hop_to_bucket_iam_updateloginprofile[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_bucket_ec2_instance_connect_sendsshpublickey" {
  description = "All outputs for ec2-instance-connect-sendsshpublickey one-hop to-bucket scenario"
  value = var.enable_single_account_privesc_one_hop_to_bucket_ec2_instance_connect_sendsshpublickey ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_bucket_ec2_instance_connect_sendsshpublickey[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_bucket_ec2_instance_connect_sendsshpublickey[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_bucket_ec2_instance_connect_sendsshpublickey[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_bucket_ec2_instance_connect_sendsshpublickey[0].starting_user_secret_access_key
    ec2_instance_id                 = module.single_account_privesc_one_hop_to_bucket_ec2_instance_connect_sendsshpublickey[0].ec2_instance_id
    ec2_instance_arn                = module.single_account_privesc_one_hop_to_bucket_ec2_instance_connect_sendsshpublickey[0].ec2_instance_arn
    ec2_instance_public_ip          = module.single_account_privesc_one_hop_to_bucket_ec2_instance_connect_sendsshpublickey[0].ec2_instance_public_ip
    ec2_bucket_role_name            = module.single_account_privesc_one_hop_to_bucket_ec2_instance_connect_sendsshpublickey[0].ec2_bucket_role_name
    ec2_bucket_role_arn             = module.single_account_privesc_one_hop_to_bucket_ec2_instance_connect_sendsshpublickey[0].ec2_bucket_role_arn
    target_bucket_name              = module.single_account_privesc_one_hop_to_bucket_ec2_instance_connect_sendsshpublickey[0].target_bucket_name
    target_bucket_arn               = module.single_account_privesc_one_hop_to_bucket_ec2_instance_connect_sendsshpublickey[0].target_bucket_arn
    allowed_ssh_ip                  = module.single_account_privesc_one_hop_to_bucket_ec2_instance_connect_sendsshpublickey[0].allowed_ssh_ip
    attack_path                     = module.single_account_privesc_one_hop_to_bucket_ec2_instance_connect_sendsshpublickey[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_bucket_glue_updatedevendpoint" {
  description = "All outputs for glue-updatedevendpoint one-hop to-bucket scenario"
  value = var.enable_single_account_privesc_one_hop_to_bucket_glue_updatedevendpoint ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_bucket_glue_updatedevendpoint[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_bucket_glue_updatedevendpoint[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_bucket_glue_updatedevendpoint[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_bucket_glue_updatedevendpoint[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_bucket_glue_updatedevendpoint[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_bucket_glue_updatedevendpoint[0].target_role_arn
    dev_endpoint_name               = module.single_account_privesc_one_hop_to_bucket_glue_updatedevendpoint[0].dev_endpoint_name
    dev_endpoint_arn                = module.single_account_privesc_one_hop_to_bucket_glue_updatedevendpoint[0].dev_endpoint_arn
    dev_endpoint_address            = module.single_account_privesc_one_hop_to_bucket_glue_updatedevendpoint[0].dev_endpoint_address
    sensitive_bucket_name           = module.single_account_privesc_one_hop_to_bucket_glue_updatedevendpoint[0].sensitive_bucket_name
    sensitive_bucket_arn            = module.single_account_privesc_one_hop_to_bucket_glue_updatedevendpoint[0].sensitive_bucket_arn
    attack_path                     = module.single_account_privesc_one_hop_to_bucket_glue_updatedevendpoint[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_bucket_ssm_sendcommand" {
  description = "All outputs for ssm-sendcommand one-hop to-bucket scenario"
  value = var.enable_single_account_privesc_one_hop_to_bucket_ssm_sendcommand ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_bucket_ssm_sendcommand[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_bucket_ssm_sendcommand[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_bucket_ssm_sendcommand[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_bucket_ssm_sendcommand[0].starting_user_secret_access_key
    ec2_instance_id                 = module.single_account_privesc_one_hop_to_bucket_ssm_sendcommand[0].ec2_instance_id
    ec2_instance_arn                = module.single_account_privesc_one_hop_to_bucket_ssm_sendcommand[0].ec2_instance_arn
    ec2_bucket_role_name            = module.single_account_privesc_one_hop_to_bucket_ssm_sendcommand[0].ec2_bucket_role_name
    ec2_bucket_role_arn             = module.single_account_privesc_one_hop_to_bucket_ssm_sendcommand[0].ec2_bucket_role_arn
    target_bucket_name              = module.single_account_privesc_one_hop_to_bucket_ssm_sendcommand[0].target_bucket_name
    target_bucket_arn               = module.single_account_privesc_one_hop_to_bucket_ssm_sendcommand[0].target_bucket_arn
    attack_path                     = module.single_account_privesc_one_hop_to_bucket_ssm_sendcommand[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_bucket_ssm_startsession" {
  description = "All outputs for ssm-startsession one-hop to-bucket scenario"
  value = var.enable_single_account_privesc_one_hop_to_bucket_ssm_startsession ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_bucket_ssm_startsession[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_bucket_ssm_startsession[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_bucket_ssm_startsession[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_bucket_ssm_startsession[0].starting_user_secret_access_key
    ec2_instance_id                 = module.single_account_privesc_one_hop_to_bucket_ssm_startsession[0].ec2_instance_id
    ec2_instance_arn                = module.single_account_privesc_one_hop_to_bucket_ssm_startsession[0].ec2_instance_arn
    ec2_bucket_role_name            = module.single_account_privesc_one_hop_to_bucket_ssm_startsession[0].ec2_bucket_role_name
    ec2_bucket_role_arn             = module.single_account_privesc_one_hop_to_bucket_ssm_startsession[0].ec2_bucket_role_arn
    target_bucket_name              = module.single_account_privesc_one_hop_to_bucket_ssm_startsession[0].target_bucket_name
    target_bucket_arn               = module.single_account_privesc_one_hop_to_bucket_ssm_startsession[0].target_bucket_arn
    attack_path                     = module.single_account_privesc_one_hop_to_bucket_ssm_startsession[0].attack_path
  } : null
  sensitive = true
}

output "single_account_privesc_one_hop_to_bucket_iam_passrole_glue_createdevendpoint" {
  description = "All outputs for iam-passrole+glue-createdevendpoint one-hop to-bucket scenario"
  value = var.enable_single_account_privesc_one_hop_to_bucket_iam_passrole_glue_createdevendpoint ? {
    starting_user_name              = module.single_account_privesc_one_hop_to_bucket_iam_passrole_glue_createdevendpoint[0].starting_user_name
    starting_user_arn               = module.single_account_privesc_one_hop_to_bucket_iam_passrole_glue_createdevendpoint[0].starting_user_arn
    starting_user_access_key_id     = module.single_account_privesc_one_hop_to_bucket_iam_passrole_glue_createdevendpoint[0].starting_user_access_key_id
    starting_user_secret_access_key = module.single_account_privesc_one_hop_to_bucket_iam_passrole_glue_createdevendpoint[0].starting_user_secret_access_key
    target_role_name                = module.single_account_privesc_one_hop_to_bucket_iam_passrole_glue_createdevendpoint[0].target_role_name
    target_role_arn                 = module.single_account_privesc_one_hop_to_bucket_iam_passrole_glue_createdevendpoint[0].target_role_arn
    sensitive_bucket_name           = module.single_account_privesc_one_hop_to_bucket_iam_passrole_glue_createdevendpoint[0].sensitive_bucket_name
    sensitive_bucket_arn            = module.single_account_privesc_one_hop_to_bucket_iam_passrole_glue_createdevendpoint[0].sensitive_bucket_arn
    attack_path                     = module.single_account_privesc_one_hop_to_bucket_iam_passrole_glue_createdevendpoint[0].attack_path
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
    starting_user_name                      = module.tool_testing_exclusive_resource_policy[0].starting_user_name
    starting_user_arn                       = module.tool_testing_exclusive_resource_policy[0].starting_user_arn
    starting_user_access_key_id             = module.tool_testing_exclusive_resource_policy[0].starting_user_access_key_id
    starting_user_secret_access_key         = module.tool_testing_exclusive_resource_policy[0].starting_user_secret_access_key
    exclusive_bucket_access_role_name       = module.tool_testing_exclusive_resource_policy[0].exclusive_bucket_access_role_name
    exclusive_bucket_access_role_arn        = module.tool_testing_exclusive_resource_policy[0].exclusive_bucket_access_role_arn
    exclusive_sensitive_bucket_name         = module.tool_testing_exclusive_resource_policy[0].exclusive_sensitive_bucket_name
    exclusive_sensitive_bucket_arn          = module.tool_testing_exclusive_resource_policy[0].exclusive_sensitive_bucket_arn
    exclusive_sensitive_bucket_domain_name  = module.tool_testing_exclusive_resource_policy[0].exclusive_sensitive_bucket_domain_name
    attack_path                             = module.tool_testing_exclusive_resource_policy[0].attack_path
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