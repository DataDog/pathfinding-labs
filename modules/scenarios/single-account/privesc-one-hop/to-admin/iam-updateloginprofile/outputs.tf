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

output "original_password" {
  description = "Original password for the admin user (set by Terraform)"
  value       = aws_iam_user_login_profile.admin_login_profile.password

  sensitive = true
}

output "console_login_url" {
  description = "AWS Console login URL for the account"
  value       = "https://${var.account_id}.signin.aws.amazon.com/console"
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "pl-pathfinder-starting-user-prod → pl-ulp-ursula → (iam:UpdateLoginProfile) → pl-ulp-admin → Administrator (Console Access)"
}