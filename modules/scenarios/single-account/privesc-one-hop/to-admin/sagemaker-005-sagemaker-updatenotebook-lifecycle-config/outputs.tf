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

# Notebook instance outputs
output "notebook_instance_name" {
  description = "Name of the SageMaker notebook instance"
  value       = aws_sagemaker_notebook_instance.target_notebook.name
}

output "notebook_instance_arn" {
  description = "ARN of the SageMaker notebook instance"
  value       = aws_sagemaker_notebook_instance.target_notebook.arn
}

# Notebook execution role outputs
output "notebook_execution_role_arn" {
  description = "ARN of the notebook execution role (admin target)"
  value       = aws_iam_role.notebook_execution_role.arn
}

output "notebook_execution_role_name" {
  description = "Name of the notebook execution role"
  value       = aws_iam_role.notebook_execution_role.name
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-sagemaker-005-to-admin-starting-user) → StopNotebookInstance → CreateLifecycleConfig → UpdateNotebookInstance → StartNotebookInstance → lifecycle script executes with notebook's admin role (pl-prod-sagemaker-005-to-admin-notebook-role) → admin access"
}
