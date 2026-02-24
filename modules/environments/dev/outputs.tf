output "pathfinding_starting_user_name" {
  description = "Name of the pathfinding starting user for dev environment"
  value       = aws_iam_user.pathfinding_starting_user.name
}

output "pathfinding_starting_user_arn" {
  description = "ARN of the pathfinding starting user for dev environment"
  value       = aws_iam_user.pathfinding_starting_user.arn
}

output "pathfinding_starting_user_access_key_id" {
  description = "Access key ID for the pathfinding starting user in dev environment"
  value       = aws_iam_access_key.pathfinding_starting_user.id
  sensitive   = true
}

output "pathfinding_starting_user_secret_access_key" {
  description = "Secret access key for the pathfinding starting user in dev environment"
  value       = aws_iam_access_key.pathfinding_starting_user.secret
  sensitive   = true
}

output "admin_user_for_cleanup_name" {
  description = "Name of the admin user for cleanup scripts in dev environment"
  value       = aws_iam_user.admin_user_for_cleanup.name
}

output "admin_user_for_cleanup_arn" {
  description = "ARN of the admin user for cleanup scripts in dev environment"
  value       = aws_iam_user.admin_user_for_cleanup.arn
}

output "admin_user_for_cleanup_access_key_id" {
  description = "Access key ID for the admin user for cleanup scripts in dev environment"
  value       = aws_iam_access_key.admin_user_for_cleanup.id
  sensitive   = true
}

output "admin_user_for_cleanup_secret_access_key" {
  description = "Secret access key for the admin user for cleanup scripts in dev environment"
  value       = aws_iam_access_key.admin_user_for_cleanup.secret
  sensitive   = true
}
