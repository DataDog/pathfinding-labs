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
  value       = aws_iam_access_key.starting_user_key.id
  sensitive   = true
}

output "starting_user_secret_access_key" {
  description = "Secret access key for the scenario-specific starting user"
  value       = aws_iam_access_key.starting_user_key.secret
  sensitive   = true
}

# Target role outputs
output "target_role_arn" {
  description = "ARN of the target role (admin role to be passed to ECS)"
  value       = aws_iam_role.target_role.arn
}

output "target_role_name" {
  description = "Name of the target role"
  value       = aws_iam_role.target_role.name
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-ecs-001-to-admin-starting-user) → ecs:CreateCluster → ecs:RegisterTaskDefinition (with ${aws_iam_role.target_role.name}) → ecs:CreateService (on Fargate) → ECS task launches container that attaches AdministratorAccess to starting user → admin access"
}

output "flag_ssm_parameter_name" {
  description = "SSM parameter name containing the CTF flag (readable after reaching admin)"
  value       = aws_ssm_parameter.flag.name
}
