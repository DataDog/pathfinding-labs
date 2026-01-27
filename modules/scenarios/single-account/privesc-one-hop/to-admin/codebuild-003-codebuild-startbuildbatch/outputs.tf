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
  description = "ARN of the target role used by CodeBuild project"
  value       = aws_iam_role.target_role.arn
}

output "target_role_name" {
  description = "Name of the target role"
  value       = aws_iam_role.target_role.name
}

# CodeBuild project outputs
output "codebuild_project_name" {
  description = "Name of the existing CodeBuild project to exploit"
  value       = aws_codebuild_project.target_project.name
}

output "codebuild_project_arn" {
  description = "ARN of the existing CodeBuild project"
  value       = aws_codebuild_project.target_project.arn
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-codebuild-003-to-admin-starting-user) → codebuild:StartBuildBatch with buildspec-override → existing CodeBuild project (pl-prod-codebuild-003-to-admin-target-project) → buildspec executes with admin role → grants admin to starting_user → admin access"
}
