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
