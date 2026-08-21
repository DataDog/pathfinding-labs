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
# NETWORKING OUTPUTS (Needed by demo script to create compute environment)
# =============================================================================

output "security_group_id" {
  description = "Security group ID for Batch Fargate tasks"
  value       = aws_security_group.batch.id
}

output "subnet_id" {
  description = "Subnet ID for Batch compute environment"
  value       = var.subnet_id
}

output "vpc_id" {
  description = "VPC ID for Batch compute environment"
  value       = var.vpc_id
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
  value       = "starting_user (${aws_iam_user.starting_user.name}) -> (batch:CreateComputeEnvironment + iam:PassRole) -> (batch:CreateJobQueue) -> (batch:RegisterJobDefinition with ${aws_iam_role.admin_role.name} as jobRoleArn) -> (batch:SubmitJob) -> Batch job container attaches admin policy to starting user -> admin access -> ssm:GetParameter -> CTF flag"
}
