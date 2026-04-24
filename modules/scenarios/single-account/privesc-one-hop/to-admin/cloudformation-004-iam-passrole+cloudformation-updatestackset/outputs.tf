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

# StackSet outputs
output "stackset_name" {
  description = "Name of the vulnerable StackSet"
  value       = aws_cloudformation_stack_set.vulnerable_stackset.name
}

output "stackset_id" {
  description = "ID of the vulnerable StackSet"
  value       = aws_cloudformation_stack_set.vulnerable_stackset.stack_set_id
}

# Execution role outputs
output "execution_role_name" {
  description = "Name of the StackSet execution role (with admin permissions)"
  value       = aws_iam_role.stackset_execution_role.name
}

output "execution_role_arn" {
  description = "ARN of the StackSet execution role"
  value       = aws_iam_role.stackset_execution_role.arn
}

# Administration role outputs
output "administration_role_name" {
  description = "Name of the StackSet administration role"
  value       = aws_iam_role.stackset_admin_role.name
}

output "administration_role_arn" {
  description = "ARN of the StackSet administration role"
  value       = aws_iam_role.stackset_admin_role.arn
}

# Escalated role name (will be created by demo script)
output "escalated_role_name" {
  description = "Name of the role that will be created via StackSet update"
  value       = "pl-prod-cloudformation-004-to-admin-escalated-role"
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
  description = "Description of the attack path"
  value       = "User (pl-prod-cloudformation-004-to-admin-starting-user) → iam:PassRole + cloudformation:UpdateStackSet → StackSet (pl-prod-cloudformation-004-to-admin-stackset) with admin execution role → creates escalated admin role (pl-prod-cloudformation-004-to-admin-escalated-role) → sts:AssumeRole → admin access"
}
