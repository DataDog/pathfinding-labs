# =============================================================================
# STARTING USER OUTPUTS (Required for all scenarios)
# =============================================================================

output "starting_user_name" {
  description = "Name of the starting IAM user"
  value       = aws_iam_user.starting_user.name
}

output "starting_user_arn" {
  description = "ARN of the starting IAM user"
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

# =============================================================================
# ADMIN ROLE OUTPUTS (Privilege Escalation Target)
# =============================================================================

output "admin_role_arn" {
  description = "ARN of the admin role (target)"
  value       = aws_iam_role.admin_role.arn
}

output "admin_role_name" {
  description = "Name of the admin role"
  value       = aws_iam_role.admin_role.name
}

# =============================================================================
# EXECUTION ROLE OUTPUTS
# =============================================================================

output "execution_role_arn" {
  description = "ARN of the ECS task execution role used by Batch Fargate tasks"
  value       = aws_iam_role.execution_role.arn
}

# =============================================================================
# BATCH INFRASTRUCTURE OUTPUTS
# =============================================================================

output "job_queue_arn" {
  description = "ARN of the Batch job queue"
  value       = aws_batch_job_queue.queue.arn
}

output "job_queue_name" {
  description = "Name of the Batch job queue"
  value       = aws_batch_job_queue.queue.name
}

output "compute_environment_arn" {
  description = "ARN of the Batch Fargate compute environment"
  value       = aws_batch_compute_environment.fargate.arn
}

# =============================================================================
# ATTACK PATH DESCRIPTION
# =============================================================================

output "attack_path" {
  description = "Description of the attack path"
  value       = "starting_user (${aws_iam_user.starting_user.name}) -> (batch:RegisterJobDefinition with admin role as jobRoleArn) -> (batch:SubmitJob to ${aws_batch_job_queue.queue.name}) -> Batch job container (${aws_iam_role.admin_role.name}) attaches admin policy to starting user -> admin access"
}
