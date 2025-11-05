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

# Pipeline role outputs
output "pipeline_role_arn" {
  description = "ARN of the pipeline role (passed to Data Pipeline)"
  value       = aws_iam_role.pipeline_role.arn
}

output "pipeline_role_name" {
  description = "Name of the pipeline role"
  value       = aws_iam_role.pipeline_role.name
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-datapipeline-001-to-admin-starting-user) → [iam:PassRole + datapipeline:CreatePipeline + datapipeline:PutPipelineDefinition + datapipeline:ActivatePipeline] → Data Pipeline spawns EC2 with admin role → [Execute: aws iam attach-user-policy AdministratorAccess] → Admin access"
}
