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

output "starting_role_arn" {
  description = "ARN of the starting role (privilege escalation target)"
  value       = aws_iam_role.starting_role.arn
}

output "starting_role_name" {
  description = "Name of the starting role"
  value       = aws_iam_role.starting_role.name
}

output "policy_arn" {
  description = "ARN of the privilege escalation policy"
  value       = aws_iam_policy.privesc_policy.arn
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-iam-009-to-admin-starting-user) → AssumeRole → Role (pl-prod-iam-009-to-admin-starting-role) → AttachRolePolicy (self) → Admin Access → ssm:GetParameter → CTF flag"
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
