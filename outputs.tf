# Outputs for pathfinder starting users
output "dev_pathfinder_starting_user_access_key_id" {
  description = "Access key ID for the pathfinder starting user in dev environment"
  value       = module.dev_resources.pathfinder_starting_user_access_key_id
  sensitive   = true
}

output "dev_pathfinder_starting_user_secret_access_key" {
  description = "Secret access key for the pathfinder starting user in dev environment"
  value       = module.dev_resources.pathfinder_starting_user_secret_access_key
  sensitive   = true
}

output "prod_pathfinder_starting_user_access_key_id" {
  description = "Access key ID for the pathfinder starting user in prod environment"
  value       = module.prod_resources.pathfinder_starting_user_access_key_id
  sensitive   = true
}

output "prod_pathfinder_starting_user_secret_access_key" {
  description = "Secret access key for the pathfinder starting user in prod environment"
  value       = module.prod_resources.pathfinder_starting_user_secret_access_key
  sensitive   = true
}

output "operations_pathfinder_starting_user_access_key_id" {
  description = "Access key ID for the pathfinder starting user in operations environment"
  value       = module.operations_resources.pathfinder_starting_user_access_key_id
  sensitive   = true
}

output "operations_pathfinder_starting_user_secret_access_key" {
  description = "Secret access key for the pathfinder starting user in operations environment"
  value       = module.operations_resources.pathfinder_starting_user_secret_access_key
  sensitive   = true
}

# Resource suffix for globally unique resources
output "resource_suffix" {
  description = "Random suffix used for globally unique resources"
  value       = random_string.resource_suffix.result
}

# S3 bucket names for demo scripts
output "prod_role_has_putrolepolicy_admin_bucket_name" {
  description = "Name of the admin demo S3 bucket in prod_role_has_putrolepolicy module"
  value       = module.prod_role_has_putrolepolicy_on_non_admin_role.admin_bucket_name
}

output "prod_simple_explicit_role_assumption_chain_s3_bucket_name" {
  description = "Name of the S3 bucket in prod_simple_explicit_role_assumption_chain module"
  value       = module.prod_simple_explicit_role_assumption_chain.s3_bucket_name
}

output "x_account_from_dev_to_prod_s3_bucket_name" {
  description = "Name of the S3 bucket in x-account-from-dev-to-prod-role-assumption-s3-access module"
  value       = module.x_account_from_dev_to_prod_role_assumption_s3_access.s3_bucket_name
}

# Admin cleanup user outputs
output "dev_admin_user_for_cleanup_access_key_id" {
  description = "Access key ID for the admin cleanup user in dev environment"
  value       = module.dev_resources.admin_user_for_cleanup_access_key_id
  sensitive   = true
}

output "dev_admin_user_for_cleanup_secret_access_key" {
  description = "Secret access key for the admin cleanup user in dev environment"
  value       = module.dev_resources.admin_user_for_cleanup_secret_access_key
  sensitive   = true
}

output "prod_admin_user_for_cleanup_access_key_id" {
  description = "Access key ID for the admin cleanup user in prod environment"
  value       = module.prod_resources.admin_user_for_cleanup_access_key_id
  sensitive   = true
}

output "prod_admin_user_for_cleanup_secret_access_key" {
  description = "Secret access key for the admin cleanup user in prod environment"
  value       = module.prod_resources.admin_user_for_cleanup_secret_access_key
  sensitive   = true
}

output "operations_admin_user_for_cleanup_access_key_id" {
  description = "Access key ID for the admin cleanup user in operations environment"
  value       = module.operations_resources.admin_user_for_cleanup_access_key_id
  sensitive   = true
}

output "operations_admin_user_for_cleanup_secret_access_key" {
  description = "Secret access key for the admin cleanup user in operations environment"
  value       = module.operations_resources.admin_user_for_cleanup_secret_access_key
  sensitive   = true
}