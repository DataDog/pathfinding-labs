# =============================================================================
# STARTING USER OUTPUTS (Required for all scenarios)
# =============================================================================

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

# =============================================================================
# ADMIN ROLE OUTPUTS (Privilege Escalation Target)
# =============================================================================

output "admin_role_arn" {
  description = "ARN of the admin role (jobRoleArn in the pre-existing job definition)"
  value       = aws_iam_role.admin_role.arn
}

output "admin_role_name" {
  description = "Name of the admin role"
  value       = aws_iam_role.admin_role.name
}

# =============================================================================
# BATCH INFRASTRUCTURE OUTPUTS
# =============================================================================

output "job_definition_name" {
  description = "Name of the pre-existing Batch job definition with privileged jobRoleArn"
  value       = aws_batch_job_definition.jd.name
}

output "job_definition_arn" {
  description = "ARN of the pre-existing Batch job definition"
  value       = aws_batch_job_definition.jd.arn
}

output "job_queue_name" {
  description = "Name of the Batch job queue"
  value       = aws_batch_job_queue.queue.name
}

output "job_queue_arn" {
  description = "ARN of the Batch job queue"
  value       = aws_batch_job_queue.queue.arn
}

output "compute_environment_arn" {
  description = "ARN of the Batch Fargate compute environment"
  value       = aws_batch_compute_environment.ce.arn
}

# =============================================================================
# CTF FLAG OUTPUTS
# =============================================================================

output "flag_ssm_parameter_name" {
  description = "Name of the SSM parameter holding the CTF flag"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM parameter holding the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}

# =============================================================================
# ATTACK PATH DESCRIPTION
# =============================================================================

output "attack_path" {
  description = "Description of the attack path"
  value       = "starting_user (${aws_iam_user.starting_user.name}) -> batch:SubmitJob with ContainerOverrides.Command on pre-existing job definition (${aws_batch_job_definition.jd.name}) that carries admin jobRoleArn (${aws_iam_role.admin_role.name}) -> Batch container runs as admin role -> iam:AttachUserPolicy attaches AdministratorAccess to starting_user -> ssm:GetParameter /pathfinding-labs/flags/batch-002-to-admin -> CTF flag"
}
