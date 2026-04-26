# =============================================================================
# STARTING USER OUTPUTS (Required for demo scripts)
# =============================================================================

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
  value       = aws_iam_access_key.starting_user_key.id
  sensitive   = true
}

output "starting_user_secret_access_key" {
  description = "Secret access key for the scenario-specific starting user"
  value       = aws_iam_access_key.starting_user_key.secret
  sensitive   = true
}

# =============================================================================
# INTERMEDIATE ROLE OUTPUTS
# =============================================================================

output "intermediate_role_arn" {
  description = "ARN of the intermediate role (has ECS permissions)"
  value       = aws_iam_role.intermediate_role.arn
}

output "intermediate_role_name" {
  description = "Name of the intermediate role"
  value       = aws_iam_role.intermediate_role.name
}

# =============================================================================
# ADMIN ROLE OUTPUTS (Target of the attack)
# =============================================================================

output "admin_role_arn" {
  description = "ARN of the admin role (target of privilege escalation via ECS task)"
  value       = aws_iam_role.admin_role.arn
}

output "admin_role_name" {
  description = "Name of the admin role"
  value       = aws_iam_role.admin_role.name
}

# =============================================================================
# ATTACK PATH DESCRIPTION
# =============================================================================

output "attack_path" {
  description = "Description of the multi-hop attack path"
  value       = "User (pl-prod-sts001-ecs002-starting-user) -> AssumeRole -> Intermediate Role (pl-prod-sts001-ecs002-intermediate-role) -> PassRole + ECS CreateCluster + RegisterTaskDefinition + RunTask -> Admin Role (pl-prod-sts001-ecs002-admin-role) via ECS task -> Admin Access"
}

output "flag_ssm_parameter_name" {
  description = "Name of the SSM parameter containing the CTF flag"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM parameter containing the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}
