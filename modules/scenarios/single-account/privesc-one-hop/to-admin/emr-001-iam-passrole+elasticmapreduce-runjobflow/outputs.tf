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

# Admin role outputs (JobFlowRole / instance profile role)
output "admin_role_arn" {
  description = "ARN of the admin role (JobFlowRole passed to EMR)"
  value       = aws_iam_role.admin_role.arn
}

output "admin_role_name" {
  description = "Name of the admin role"
  value       = aws_iam_role.admin_role.name
}

# Instance profile outputs (needed for --ec2-attributes InstanceProfile=)
output "admin_instance_profile_name" {
  description = "Name of the admin instance profile (used in EMR ec2-attributes)"
  value       = aws_iam_instance_profile.admin_instance_profile.name
}

output "admin_instance_profile_arn" {
  description = "ARN of the admin instance profile"
  value       = aws_iam_instance_profile.admin_instance_profile.arn
}

# Service role outputs
output "service_role_arn" {
  description = "ARN of the EMR service role"
  value       = aws_iam_role.service_role.arn
}

output "service_role_name" {
  description = "Name of the EMR service role"
  value       = aws_iam_role.service_role.name
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-emr-001-to-admin-starting-user) -> [iam:PassRole + elasticmapreduce:RunJobFlow] -> EMR cluster with admin instance profile + service role -> [step via command-runner.jar calls iam:attach-user-policy] -> AdministratorAccess attached to starting user -> Admin access"
}
