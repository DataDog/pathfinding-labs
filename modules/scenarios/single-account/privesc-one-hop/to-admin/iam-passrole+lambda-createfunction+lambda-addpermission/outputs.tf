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
  description = "ARN of the target admin role"
  value       = aws_iam_role.target_role.arn
}

output "target_role_name" {
  description = "Name of the target admin role"
  value       = aws_iam_role.target_role.name
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-iprlcflap-to-admin-starting-user) → lambda:CreateFunction with admin role → malicious Lambda → lambda:AddPermission to allow self invoke → lambda:InvokeFunction → execute as admin role → admin access"
}
