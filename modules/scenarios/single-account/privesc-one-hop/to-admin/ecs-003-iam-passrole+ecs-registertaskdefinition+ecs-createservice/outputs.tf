# =============================================================================
# STARTING USER OUTPUTS (Required for all scenarios)
# =============================================================================

output "starting_user_name" {
  description = "Name of the starting IAM user"
  value       = aws_iam_user.starting_user.name
}

output "starting_user_arn" {
  description = "ARN of the starting IAM user"
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

# =============================================================================
# TARGET ROLE OUTPUTS
# =============================================================================

output "target_role_arn" {
  description = "ARN of the target admin role"
  value       = aws_iam_role.target_role.arn
}

output "target_role_name" {
  description = "Name of the target admin role"
  value       = aws_iam_role.target_role.name
}

# =============================================================================
# ECS CLUSTER OUTPUTS
# =============================================================================

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.cluster.name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.cluster.arn
}

# =============================================================================
# CTF FLAG OUTPUTS
# =============================================================================

output "flag_ssm_parameter_name" {
  description = "Name of the SSM parameter holding the CTF flag"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM parameter holding the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}

# =============================================================================
# ATTACK PATH DESCRIPTION
# =============================================================================

output "attack_path" {
  description = "Description of the attack path"
  value       = "starting_user (${aws_iam_user.starting_user.name}) → (ecs:RegisterTaskDefinition with ${aws_iam_role.target_role.name}) → (ecs:CreateService) → ECS service launches task → task attaches admin policy to starting user → admin access → ssm:GetParameter → CTF flag"
}
