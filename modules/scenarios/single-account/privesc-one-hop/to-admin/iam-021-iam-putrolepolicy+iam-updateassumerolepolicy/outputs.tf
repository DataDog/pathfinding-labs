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
  description = "ARN of the target role that will be modified"
  value       = aws_iam_role.target_role.arn
}

output "target_role_name" {
  description = "Name of the target role"
  value       = aws_iam_role.target_role.name
}

# Attack path description
output "attack_path" {
  description = "Description of the attack path"
  value       = "User (${aws_iam_user.starting_user.name}) → iam:PutRolePolicy → ${aws_iam_role.target_role.name} (add admin inline policy) → iam:UpdateAssumeRolePolicy → ${aws_iam_role.target_role.name} trust policy (add starting_user) → sts:AssumeRole → admin access"
}

# Additional context for demo scripts
output "scenario_notes" {
  description = "Important notes about this scenario"
  value       = "CRITICAL: The starting user does NOT have sts:AssumeRole permission. When the trust policy is updated to explicitly name the user ARN, that user can assume the role WITHOUT needing sts:AssumeRole in their IAM policy."
}

output "flag_ssm_parameter_name" {
  description = "Name of the SSM parameter containing the CTF flag"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM parameter containing the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}
