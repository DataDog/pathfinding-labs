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

# Admin role outputs
output "admin_role_arn" {
  description = "ARN of the admin role (passed to CloudFormation)"
  value       = aws_iam_role.admin_role.arn
}

output "admin_role_name" {
  description = "Name of the admin role"
  value       = aws_iam_role.admin_role.name
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-cloudformation-001-to-admin-starting-user) → [iam:PassRole + cloudformation:CreateStack] → CloudFormation creates pl-prod-cloudformation-001-to-admin-escalated-role (with admin permissions trusting starting user) → [sts:AssumeRole] → Admin access"
}

output "escalated_role_name" {
  description = "Name of the role that will be created during the attack demonstration"
  value       = "pl-prod-cloudformation-001-to-admin-escalated-role"
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
