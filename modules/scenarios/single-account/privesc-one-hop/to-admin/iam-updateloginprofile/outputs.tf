# Scenario-specific starting user outputs (REQUIRED FOR ALL SCENARIOS)
output "starting_user_name" {
  description = "Name of the scenario-specific starting user"
  value       = aws_iam_user.starting_user.name
}

output "starting_user_arn" {
  description = "ARN of the scenario-specific starting user"
  value       = aws_iam_user.starting_user.arn
}

output "starting_user_access_key_id" {
  description = "Access key ID for the starting user"
  value       = aws_iam_access_key.starting_user.id
  sensitive   = true
}

output "starting_user_secret_access_key" {
  description = "Secret access key for the starting user"
  value       = aws_iam_access_key.starting_user.secret
  sensitive   = true
}

# Target admin user outputs
output "admin_user_arn" {
  description = "ARN of the admin user (target)"
  value       = aws_iam_user.admin_user.arn
}

output "admin_user_name" {
  description = "Name of the admin user"
  value       = aws_iam_user.admin_user.name
}

output "original_password" {
  description = "Original password for the admin user (set by Terraform)"
  value       = aws_iam_user_login_profile.admin_login_profile.password
  sensitive   = true
}

output "console_login_url" {
  description = "AWS Console login URL for the account"
  value       = "https://${var.account_id}.signin.aws.amazon.com/console"
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-ulp-to-admin-starting-user) → iam:UpdateLoginProfile → Admin User (pl-prod-ulp-to-admin-target-user) → Console Access with Admin Privileges"
}
