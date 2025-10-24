
output "admin_user_for_cleanup_name" {
  description = "Name of the admin user for cleanup scripts in prod environment"
  value       = aws_iam_user.admin_user_for_cleanup.name
}

output "admin_user_for_cleanup_arn" {
  description = "ARN of the admin user for cleanup scripts in prod environment"
  value       = aws_iam_user.admin_user_for_cleanup.arn
}

output "admin_user_for_cleanup_access_key_id" {
  description = "Access key ID for the admin user for cleanup scripts in prod environment"
  value       = aws_iam_access_key.admin_user_for_cleanup.id
  sensitive   = true
}

output "admin_user_for_cleanup_secret_access_key" {
  description = "Secret access key for the admin user for cleanup scripts in prod environment"
  value       = aws_iam_access_key.admin_user_for_cleanup.secret
  sensitive   = true
}
