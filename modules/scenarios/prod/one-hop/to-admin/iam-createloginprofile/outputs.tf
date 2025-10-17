output "starting_role_arn" {
  description = "ARN of the starting role for this attack path"
  value       = aws_iam_role.privesc_role.arn
}

output "admin_user_arn" {
  description = "ARN of the admin user"
  value       = aws_iam_user.admin_user.arn
}

output "admin_user_name" {
  description = "Name of the admin user"
  value       = aws_iam_user.admin_user.name
}

output "admin_access_key_id" {
  description = "Access key ID for the admin user (for verification)"
  value       = aws_iam_access_key.admin_access_key.id
  sensitive   = true
}

output "admin_secret_access_key" {
  description = "Secret access key for the admin user (for verification)"
  value       = aws_iam_access_key.admin_access_key.secret
  sensitive   = true
}

output "console_login_url" {
  description = "AWS Console login URL for the account"
  value       = "https://${var.account_id}.signin.aws.amazon.com/console"
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "pl-pathfinder-starting-user-prod → pl-clp-clifford → (iam:CreateLoginProfile) → pl-clp-admin → Administrator (Console Access)"
}