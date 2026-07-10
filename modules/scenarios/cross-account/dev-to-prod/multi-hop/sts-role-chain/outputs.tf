# Starting user outputs (required by plabs TUI and demo scripts)
output "starting_user_name" {
  description = "Name of the scenario-specific starting user in the dev account"
  value       = aws_iam_user.starting_user.name
}

output "starting_user_arn" {
  description = "ARN of the scenario-specific starting user in the dev account"
  value       = aws_iam_user.starting_user.arn
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

# Dev account role outputs
output "dev_role_name" {
  description = "Name of the dev-account hop role"
  value       = aws_iam_role.dev_role.name
}

output "dev_role_arn" {
  description = "ARN of the dev-account hop role"
  value       = aws_iam_role.dev_role.arn
}

# Prod non-admin role outputs
output "prod_non_admin_role_name" {
  description = "Name of the prod non-admin hop role"
  value       = aws_iam_role.prod_non_admin_role.name
}

output "prod_non_admin_role_arn" {
  description = "ARN of the prod non-admin hop role"
  value       = aws_iam_role.prod_non_admin_role.arn
}

# Prod admin role outputs (attack target)
output "prod_admin_role_name" {
  description = "Name of the prod admin role (attack target)"
  value       = aws_iam_role.prod_admin_role.name
}

output "prod_admin_role_arn" {
  description = "ARN of the prod admin role (attack target)"
  value       = aws_iam_role.prod_admin_role.arn
}

# CTF flag outputs
output "flag_ssm_parameter_name" {
  description = "Name of the SSM parameter holding the CTF flag"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM parameter holding the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}

# Attack path description
output "attack_path" {
  description = "Human-readable description of the attack path"
  value       = "User (pl-dev-sts-role-chain-starting-user) → sts:AssumeRole → Role (pl-dev-sts-role-chain-dev-role) → sts:AssumeRole cross-account → Role (pl-prod-sts-role-chain-prod-non-admin-role) → sts:AssumeRole → Role (pl-prod-sts-role-chain-prod-admin-role) [AdministratorAccess] → ssm:GetParameter /pathfinding-labs/flags/sts-role-chain-to-admin → CTF flag"
}
