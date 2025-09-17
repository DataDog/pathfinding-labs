output "pathfinder_starting_user_name" {
  description = "Name of the pathfinder starting user for operations environment"
  value       = aws_iam_user.pathfinder_starting_user.name
}

output "pathfinder_starting_user_arn" {
  description = "ARN of the pathfinder starting user for operations environment"
  value       = aws_iam_user.pathfinder_starting_user.arn
}

output "pathfinder_starting_user_access_key_id" {
  description = "Access key ID for the pathfinder starting user in operations environment"
  value       = aws_iam_access_key.pathfinder_starting_user.id
  sensitive   = true
}

output "pathfinder_starting_user_secret_access_key" {
  description = "Secret access key for the pathfinder starting user in operations environment"
  value       = aws_iam_access_key.pathfinder_starting_user.secret
  sensitive   = true
}

output "admin_user_for_cleanup_name" {
  description = "Name of the admin user for cleanup scripts in operations environment"
  value       = aws_iam_user.admin_user_for_cleanup.name
}

output "admin_user_for_cleanup_arn" {
  description = "ARN of the admin user for cleanup scripts in operations environment"
  value       = aws_iam_user.admin_user_for_cleanup.arn
}

output "admin_user_for_cleanup_access_key_id" {
  description = "Access key ID for the admin user for cleanup scripts in operations environment"
  value       = aws_iam_access_key.admin_user_for_cleanup.id
  sensitive   = true
}

output "admin_user_for_cleanup_secret_access_key" {
  description = "Secret access key for the admin user for cleanup scripts in operations environment"
  value       = aws_iam_access_key.admin_user_for_cleanup.secret
  sensitive   = true
}

# Conditional outputs for ops-infra-deployer role (only when github_repo is provided)
output "ops_infra_deployer_role_arn" {
  description = "ARN of the ops-infra-deployer role (only created when github_repo is provided)"
  value       = var.github_repo != null ? aws_iam_role.ops-infra-deployer[0].arn : null
}

output "ops_infra_deployer_role_name" {
  description = "Name of the ops-infra-deployer role (only created when github_repo is provided)"
  value       = var.github_repo != null ? aws_iam_role.ops-infra-deployer[0].name : null
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider (only created when github_repo is provided)"
  value       = var.github_repo != null ? aws_iam_openid_connect_provider.github[0].arn : null
}
