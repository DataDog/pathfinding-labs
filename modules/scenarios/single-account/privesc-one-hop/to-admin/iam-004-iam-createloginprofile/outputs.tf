# Scenario-specific starting user outputs (REQUIRED FOR ALL SCENARIOS)
output "starting_user_arn" {
  description = "ARN of the scenario-specific starting user"
  value       = aws_iam_user.starting_user.arn
}

output "starting_user_name" {
  description = "Name of the scenario-specific starting user"
  value       = aws_iam_user.starting_user.name
}

output "starting_user_access_key_id" {
  description = "Access key ID for the scenario-specific starting user"
  value       = aws_iam_access_key.starting_user.id
  sensitive   = true
}

output "starting_user_secret_access_key" {
  description = "Secret access key for the scenario-specific starting user"
  value       = aws_iam_access_key.starting_user.secret
  sensitive   = true
}

# Starting role outputs (for role-based escalation)
output "starting_role_arn" {
  description = "ARN of the starting role"
  value       = aws_iam_role.starting_role.arn
}

output "starting_role_name" {
  description = "Name of the starting role"
  value       = aws_iam_role.starting_role.name
}

# Admin user outputs (target of privilege escalation)
output "admin_user_arn" {
  description = "ARN of the admin user (target)"
  value       = aws_iam_user.admin_user.arn
}

output "admin_user_name" {
  description = "Name of the admin user"
  value       = aws_iam_user.admin_user.name
}

# Admin user access key outputs (for verification)
output "admin_access_key_id" {
  description = "Access key ID for the admin user"
  value       = aws_iam_access_key.admin_access_key.id
  sensitive   = true
}

output "admin_secret_access_key" {
  description = "Secret access key for the admin user"
  value       = aws_iam_access_key.admin_access_key.secret
  sensitive   = true
}

# Console login information
output "console_login_url" {
  description = "AWS Console login URL for the account"
  value       = "https://${var.account_id}.signin.aws.amazon.com/console"
}

# Attack path description
output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-iam-004-to-admin-starting-user) → Role (pl-prod-iam-004-to-admin-starting-role) → CreateLoginProfile → Admin User (pl-prod-iam-004-to-admin-target-user) → Console Access with Admin Privileges"
}

# CTF flag outputs
output "flag_ssm_parameter_name" {
  description = "Name of the SSM parameter containing the CTF flag"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM parameter containing the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}
