# Scenario-specific starting user outputs (REQUIRED)
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
  value       = aws_iam_access_key.starting_user_key.id
  sensitive   = true
}

output "starting_user_secret_access_key" {
  description = "Secret access key for the starting user"
  value       = aws_iam_access_key.starting_user_key.secret
  sensitive   = true
}

# Project role outputs
output "project_role_name" {
  description = "Name of the CodeBuild project's admin role"
  value       = aws_iam_role.project_role.name
}

output "project_role_arn" {
  description = "ARN of the CodeBuild project's admin role"
  value       = aws_iam_role.project_role.arn
}

# CodeBuild project outputs
output "codebuild_project_name" {
  description = "Name of the existing CodeBuild project"
  value       = aws_codebuild_project.existing_project.name
}

output "codebuild_project_arn" {
  description = "ARN of the existing CodeBuild project"
  value       = aws_codebuild_project.existing_project.arn
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
  value       = "User (pl-prod-codebuild-002-to-admin-starting-user) → codebuild:StartBuild with buildspec-override → ${aws_codebuild_project.existing_project.name} → Buildspec grants admin to starting user → Admin Access → ssm:GetParameter → CTF flag"
}
