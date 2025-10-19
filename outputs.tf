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

output "prod_pathfinder_starting_user_access_key_id" {
  description = "Access key ID for the pathfinder starting user in prod environment"
  value       = module.prod_environment.pathfinder_starting_user_access_key_id
  sensitive   = true
}

output "prod_pathfinder_starting_user_secret_access_key" {
  description = "Secret access key for the pathfinder starting user in prod environment"
  value       = module.prod_environment.pathfinder_starting_user_secret_access_key
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

# Prod one-hop to-admin scenario outputs
output "prod_one_hop_to_admin_iam_createloginprofile" {
  description = "Outputs from the prod one-hop-to-admin iam-createloginprofile scenario"
  value = var.enable_prod_one_hop_to_admin_iam_createloginprofile ? [
    {
      starting_role_arn   = module.prod_one_hop_to_admin_iam_createloginprofile[0].starting_role_arn
      admin_user_name     = module.prod_one_hop_to_admin_iam_createloginprofile[0].admin_user_name
      admin_user_arn      = module.prod_one_hop_to_admin_iam_createloginprofile[0].admin_user_arn
      admin_access_key_id = module.prod_one_hop_to_admin_iam_createloginprofile[0].admin_access_key_id
    }
  ][0] : null
}

output "prod_one_hop_to_admin_iam_putgrouppolicy_privesc_user_access_key_id" {
  description = "Access key ID for the privilege escalation user in iam-putgrouppolicy scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_putgrouppolicy ? module.prod_one_hop_to_admin_iam_putgrouppolicy[0].privesc_user_access_key_id : null
  sensitive   = true
}

output "prod_one_hop_to_admin_iam_putgrouppolicy_privesc_user_secret_access_key" {
  description = "Secret access key for the privilege escalation user in iam-putgrouppolicy scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_putgrouppolicy ? module.prod_one_hop_to_admin_iam_putgrouppolicy[0].privesc_user_secret_access_key : null
  sensitive   = true
}

output "prod_one_hop_to_admin_iam_addusertogroup_start_user_access_key_id" {
  description = "Access key ID for the start user in iam-addusertogroup scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_addusertogroup ? module.prod_one_hop_to_admin_iam_addusertogroup[0].start_user_access_key_id : null
  sensitive   = true
}

output "prod_one_hop_to_admin_iam_addusertogroup_start_user_secret_access_key" {
  description = "Secret access key for the start user in iam-addusertogroup scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_addusertogroup ? module.prod_one_hop_to_admin_iam_addusertogroup[0].start_user_secret_access_key : null
  sensitive   = true
}

output "prod_one_hop_to_admin_iam_attachuserpolicy_starting_user_access_key_id" {
  description = "Access key ID for the starting user in iam-attachuserpolicy scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_attachuserpolicy ? module.prod_one_hop_to_admin_iam_attachuserpolicy[0].starting_user_access_key_id : null
  sensitive   = true
}

output "prod_one_hop_to_admin_iam_attachuserpolicy_starting_user_secret_access_key" {
  description = "Secret access key for the starting user in iam-attachuserpolicy scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_attachuserpolicy ? module.prod_one_hop_to_admin_iam_attachuserpolicy[0].starting_user_secret_access_key : null
  sensitive   = true
}

output "prod_one_hop_to_admin_iam_attachgrouppolicy_starting_user_access_key_id" {
  description = "Access key ID for the starting user in iam-attachgrouppolicy scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_attachgrouppolicy ? module.prod_one_hop_to_admin_iam_attachgrouppolicy[0].starting_user_access_key_id : null
  sensitive   = true
}

output "prod_one_hop_to_admin_iam_attachgrouppolicy_starting_user_secret_access_key" {
  description = "Secret access key for the starting user in iam-attachgrouppolicy scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_attachgrouppolicy ? module.prod_one_hop_to_admin_iam_attachgrouppolicy[0].starting_user_secret_access_key : null
  sensitive   = true
}

output "prod_one_hop_to_admin_iam_attachgrouppolicy_group_name" {
  description = "Group name for the iam-attachgrouppolicy scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_attachgrouppolicy ? module.prod_one_hop_to_admin_iam_attachgrouppolicy[0].group_name : null
}

output "prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction_starting_user_name" {
  description = "Starting user name for iam-passrole+lambda-createfunction+lambda-invokefunction scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction ? module.prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction[0].starting_user_name : null
}

output "prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction_starting_user_arn" {
  description = "Starting user ARN for iam-passrole+lambda-createfunction+lambda-invokefunction scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction ? module.prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction[0].starting_user_arn : null
}

output "prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction_starting_user_access_key_id" {
  description = "Starting user access key ID for iam-passrole+lambda-createfunction+lambda-invokefunction scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction ? module.prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction[0].starting_user_access_key_id : null
  sensitive   = true
}

output "prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction_starting_user_secret_access_key" {
  description = "Starting user secret access key for iam-passrole+lambda-createfunction+lambda-invokefunction scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction ? module.prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction[0].starting_user_secret_access_key : null
  sensitive   = true
}

output "prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction_starting_role_name" {
  description = "Starting role name for iam-passrole+lambda-createfunction+lambda-invokefunction scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction ? module.prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction[0].starting_role_name : null
}

output "prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction_starting_role_arn" {
  description = "Starting role ARN for iam-passrole+lambda-createfunction+lambda-invokefunction scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction ? module.prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction[0].starting_role_arn : null
}

output "prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction_admin_role_name" {
  description = "Admin role name for iam-passrole+lambda-createfunction+lambda-invokefunction scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction ? module.prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction[0].admin_role_name : null
}

output "prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction_admin_role_arn" {
  description = "Admin role ARN for iam-passrole+lambda-createfunction+lambda-invokefunction scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction ? module.prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction[0].admin_role_arn : null
}

output "prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction_attack_path" {
  description = "Attack path description for iam-passrole+lambda-createfunction+lambda-invokefunction scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction ? module.prod_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction[0].attack_path_description : null
}

output "prod_one_hop_to_admin_iam_passrole_cloudformation_starting_user_name" {
  description = "Starting user name for iam-passrole-cloudformation scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_passrole_cloudformation ? module.prod_one_hop_to_admin_iam_passrole_cloudformation[0].starting_user_name : null
}

output "prod_one_hop_to_admin_iam_passrole_cloudformation_starting_user_arn" {
  description = "Starting user ARN for iam-passrole-cloudformation scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_passrole_cloudformation ? module.prod_one_hop_to_admin_iam_passrole_cloudformation[0].starting_user_arn : null
}

output "prod_one_hop_to_admin_iam_passrole_cloudformation_starting_user_access_key_id" {
  description = "Starting user access key ID for iam-passrole-cloudformation scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_passrole_cloudformation ? module.prod_one_hop_to_admin_iam_passrole_cloudformation[0].starting_user_access_key_id : null
  sensitive   = true
}

output "prod_one_hop_to_admin_iam_passrole_cloudformation_starting_user_secret_access_key" {
  description = "Starting user secret access key for iam-passrole-cloudformation scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_passrole_cloudformation ? module.prod_one_hop_to_admin_iam_passrole_cloudformation[0].starting_user_secret_access_key : null
  sensitive   = true
}

output "prod_one_hop_to_admin_iam_passrole_cloudformation_admin_role_name" {
  description = "Admin role name for iam-passrole-cloudformation scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_passrole_cloudformation ? module.prod_one_hop_to_admin_iam_passrole_cloudformation[0].admin_role_name : null
}

output "prod_one_hop_to_admin_iam_passrole_cloudformation_admin_role_arn" {
  description = "Admin role ARN for iam-passrole-cloudformation scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_passrole_cloudformation ? module.prod_one_hop_to_admin_iam_passrole_cloudformation[0].admin_role_arn : null
}

output "prod_one_hop_to_admin_iam_passrole_cloudformation_attack_path" {
  description = "Attack path description for iam-passrole-cloudformation scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_passrole_cloudformation ? module.prod_one_hop_to_admin_iam_passrole_cloudformation[0].attack_path : null
}

output "prod_one_hop_to_admin_iam_createaccesskey_starting_user_access_key_id" {
  description = "Access key ID for the starting user in iam-createaccesskey scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_createaccesskey ? module.prod_one_hop_to_admin_iam_createaccesskey[0].starting_user_access_key_id : null
  sensitive   = true
}

output "prod_one_hop_to_admin_iam_createaccesskey_starting_user_secret_access_key" {
  description = "Secret access key for the starting user in iam-createaccesskey scenario"
  value       = var.enable_prod_one_hop_to_admin_iam_createaccesskey ? module.prod_one_hop_to_admin_iam_createaccesskey[0].starting_user_secret_access_key : null
  sensitive   = true
}

output "prod_one_hop_to_admin_iam_passrole_ec2_runinstances_starting_user_access_key_id" {
  description = "Access key ID for pl-prod-one-hop-prec-starting-user"
  value       = try(module.prod_one_hop_to_admin_iam_passrole_ec2_runinstances[0].starting_user_access_key_id, "not_enabled")
  sensitive   = true
}

output "prod_one_hop_to_admin_iam_passrole_ec2_runinstances_starting_user_secret_access_key" {
  description = "Secret access key for pl-prod-one-hop-prec-starting-user"
  value       = try(module.prod_one_hop_to_admin_iam_passrole_ec2_runinstances[0].starting_user_secret_access_key, "not_enabled")
  sensitive   = true
}

# Prod one-hop to-bucket scenario outputs
output "prod_one_hop_to_bucket_iam_updateloginprofile_starting_user_name" {
  description = "Starting user name for iam-updateloginprofile to-bucket scenario"
  value       = var.enable_prod_one_hop_to_bucket_iam_updateloginprofile ? module.prod_one_hop_to_bucket_iam_updateloginprofile[0].starting_user_name : null
}

output "prod_one_hop_to_bucket_iam_updateloginprofile_starting_user_arn" {
  description = "Starting user ARN for iam-updateloginprofile to-bucket scenario"
  value       = var.enable_prod_one_hop_to_bucket_iam_updateloginprofile ? module.prod_one_hop_to_bucket_iam_updateloginprofile[0].starting_user_arn : null
}

output "prod_one_hop_to_bucket_iam_updateloginprofile_starting_user_access_key_id" {
  description = "Starting user access key ID for iam-updateloginprofile to-bucket scenario"
  value       = var.enable_prod_one_hop_to_bucket_iam_updateloginprofile ? module.prod_one_hop_to_bucket_iam_updateloginprofile[0].starting_user_access_key_id : null
  sensitive   = true
}

output "prod_one_hop_to_bucket_iam_updateloginprofile_starting_user_secret_access_key" {
  description = "Starting user secret access key for iam-updateloginprofile to-bucket scenario"
  value       = var.enable_prod_one_hop_to_bucket_iam_updateloginprofile ? module.prod_one_hop_to_bucket_iam_updateloginprofile[0].starting_user_secret_access_key : null
  sensitive   = true
}

output "prod_one_hop_to_bucket_iam_updateloginprofile_target_user_name" {
  description = "Target user name for iam-updateloginprofile to-bucket scenario"
  value       = var.enable_prod_one_hop_to_bucket_iam_updateloginprofile ? module.prod_one_hop_to_bucket_iam_updateloginprofile[0].target_user_name : null
}

output "prod_one_hop_to_bucket_iam_updateloginprofile_target_user_arn" {
  description = "Target user ARN for iam-updateloginprofile to-bucket scenario"
  value       = var.enable_prod_one_hop_to_bucket_iam_updateloginprofile ? module.prod_one_hop_to_bucket_iam_updateloginprofile[0].target_user_arn : null
}

output "prod_one_hop_to_bucket_iam_updateloginprofile_original_password" {
  description = "Original password for target user in iam-updateloginprofile to-bucket scenario"
  value       = var.enable_prod_one_hop_to_bucket_iam_updateloginprofile ? module.prod_one_hop_to_bucket_iam_updateloginprofile[0].original_password : null
  sensitive   = true
}

output "prod_one_hop_to_bucket_iam_updateloginprofile_sensitive_bucket_name" {
  description = "Sensitive bucket name for iam-updateloginprofile to-bucket scenario"
  value       = var.enable_prod_one_hop_to_bucket_iam_updateloginprofile ? module.prod_one_hop_to_bucket_iam_updateloginprofile[0].sensitive_bucket_name : null
}

output "prod_one_hop_to_bucket_iam_updateloginprofile_sensitive_bucket_arn" {
  description = "Sensitive bucket ARN for iam-updateloginprofile to-bucket scenario"
  value       = var.enable_prod_one_hop_to_bucket_iam_updateloginprofile ? module.prod_one_hop_to_bucket_iam_updateloginprofile[0].sensitive_bucket_arn : null
}

output "prod_one_hop_to_bucket_iam_updateloginprofile_console_login_url" {
  description = "Console login URL for iam-updateloginprofile to-bucket scenario"
  value       = var.enable_prod_one_hop_to_bucket_iam_updateloginprofile ? module.prod_one_hop_to_bucket_iam_updateloginprofile[0].console_login_url : null
}

output "prod_one_hop_to_bucket_iam_updateloginprofile_attack_path" {
  description = "Attack path for iam-updateloginprofile to-bucket scenario"
  value       = var.enable_prod_one_hop_to_bucket_iam_updateloginprofile ? module.prod_one_hop_to_bucket_iam_updateloginprofile[0].attack_path : null
}

# Prod one-hop to-bucket iam-createloginprofile scenario outputs
output "prod_one_hop_to_bucket_iam_createloginprofile_starting_user_name" {
  description = "Starting user name for iam-createloginprofile to-bucket scenario"
  value       = var.enable_prod_one_hop_to_bucket_iam_createloginprofile ? module.prod_one_hop_to_bucket_iam_createloginprofile[0].starting_user_name : null
}

output "prod_one_hop_to_bucket_iam_createloginprofile_starting_user_arn" {
  description = "Starting user ARN for iam-createloginprofile to-bucket scenario"
  value       = var.enable_prod_one_hop_to_bucket_iam_createloginprofile ? module.prod_one_hop_to_bucket_iam_createloginprofile[0].starting_user_arn : null
}

output "prod_one_hop_to_bucket_iam_createloginprofile_starting_user_access_key_id" {
  description = "Starting user access key ID for iam-createloginprofile to-bucket scenario"
  value       = var.enable_prod_one_hop_to_bucket_iam_createloginprofile ? module.prod_one_hop_to_bucket_iam_createloginprofile[0].starting_user_access_key_id : null
  sensitive   = true
}

output "prod_one_hop_to_bucket_iam_createloginprofile_starting_user_secret_access_key" {
  description = "Starting user secret access key for iam-createloginprofile to-bucket scenario"
  value       = var.enable_prod_one_hop_to_bucket_iam_createloginprofile ? module.prod_one_hop_to_bucket_iam_createloginprofile[0].starting_user_secret_access_key : null
  sensitive   = true
}

output "prod_one_hop_to_bucket_iam_createloginprofile_hop1_user_name" {
  description = "Target user name for iam-createloginprofile to-bucket scenario"
  value       = var.enable_prod_one_hop_to_bucket_iam_createloginprofile ? module.prod_one_hop_to_bucket_iam_createloginprofile[0].hop1_user_name : null
}

output "prod_one_hop_to_bucket_iam_createloginprofile_hop1_user_arn" {
  description = "Target user ARN for iam-createloginprofile to-bucket scenario"
  value       = var.enable_prod_one_hop_to_bucket_iam_createloginprofile ? module.prod_one_hop_to_bucket_iam_createloginprofile[0].hop1_user_arn : null
}

output "prod_one_hop_to_bucket_iam_createloginprofile_sensitive_bucket_name" {
  description = "Sensitive bucket name for iam-createloginprofile to-bucket scenario"
  value       = var.enable_prod_one_hop_to_bucket_iam_createloginprofile ? module.prod_one_hop_to_bucket_iam_createloginprofile[0].sensitive_bucket_name : null
}

output "prod_one_hop_to_bucket_iam_createloginprofile_sensitive_bucket_arn" {
  description = "Sensitive bucket ARN for iam-createloginprofile to-bucket scenario"
  value       = var.enable_prod_one_hop_to_bucket_iam_createloginprofile ? module.prod_one_hop_to_bucket_iam_createloginprofile[0].sensitive_bucket_arn : null
}

output "prod_one_hop_to_bucket_iam_createloginprofile_console_login_url" {
  description = "Console login URL for iam-createloginprofile to-bucket scenario"
  value       = var.enable_prod_one_hop_to_bucket_iam_createloginprofile ? module.prod_one_hop_to_bucket_iam_createloginprofile[0].console_login_url : null
}

output "prod_one_hop_to_bucket_iam_createloginprofile_attack_path_description" {
  description = "Attack path description for iam-createloginprofile to-bucket scenario"
  value       = var.enable_prod_one_hop_to_bucket_iam_createloginprofile ? module.prod_one_hop_to_bucket_iam_createloginprofile[0].attack_path_description : null
}

# S3 bucket names for enabled scenarios
output "prod_multi_hop_to_admin_putrolepolicy_admin_bucket_name" {
  description = "Name of the admin demo S3 bucket in prod multi-hop putrolepolicy-on-other scenario"
  value       = var.enable_prod_multi_hop_to_admin_putrolepolicy_on_other ? module.prod_multi_hop_to_admin_putrolepolicy_on_other[0].admin_bucket_name : null
}

output "prod_multi_hop_to_bucket_role_chain_s3_bucket_name" {
  description = "Name of the S3 bucket in prod multi-hop role-chain-to-s3 scenario"
  value       = var.enable_prod_multi_hop_to_bucket_role_chain_to_s3 ? module.prod_multi_hop_to_bucket_role_chain_to_s3[0].s3_bucket_name : null
}

output "cross_account_dev_to_prod_s3_bucket_name" {
  description = "Name of the S3 bucket in cross-account dev-to-prod one-hop simple-role-assumption scenario"
  value       = var.enable_cross_account_dev_to_prod_one_hop_simple_role_assumption ? module.cross_account_dev_to_prod_one_hop_simple_role_assumption[0].s3_bucket_name : null
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