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

# Passable role outputs
output "passable_role_arn" {
  description = "ARN of the passable admin role"
  value       = aws_iam_role.passable_role.arn
}

output "passable_role_name" {
  description = "Name of the passable admin role"
  value       = aws_iam_role.passable_role.name
}

output "flag_ssm_parameter_name" {
  description = "Name of the SSM parameter containing the CTF flag"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM parameter containing the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}

# Attack path description
output "attack_path" {
  description = "Description of the attack path"
  value       = "starting_user → (iam:PassRole + sagemaker:CreateNotebookInstance) → notebook with admin role → (sagemaker:CreatePresignedNotebookInstanceUrl) → access Jupyter terminal → (aws iam list-users) → admin access"
}
