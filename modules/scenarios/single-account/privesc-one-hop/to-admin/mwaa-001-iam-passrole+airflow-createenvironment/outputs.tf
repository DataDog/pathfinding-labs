# =============================================================================
# STARTING USER OUTPUTS (REQUIRED FOR ALL SCENARIOS)
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
# ADMIN ROLE OUTPUTS
# =============================================================================

output "admin_role_name" {
  description = "Name of the admin role (MWAA execution role)"
  value       = aws_iam_role.admin_role.name
}

output "admin_role_arn" {
  description = "ARN of the admin role (MWAA execution role)"
  value       = aws_iam_role.admin_role.arn
}

# =============================================================================
# VPC INFRASTRUCTURE OUTPUTS
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC created for MWAA"
  value       = aws_vpc.mwaa_vpc.id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs for MWAA"
  value       = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
}

output "security_group_id" {
  description = "ID of the security group for MWAA"
  value       = aws_security_group.mwaa_sg.id
}

# =============================================================================
# S3 BUCKET OUTPUTS
# =============================================================================

output "attacker_bucket_name" {
  description = "Name of the attacker's S3 bucket (for DAGs and startup script)"
  value       = aws_s3_bucket.attacker_bucket.id
}

output "attacker_bucket_arn" {
  description = "ARN of the attacker's S3 bucket"
  value       = aws_s3_bucket.attacker_bucket.arn
}

output "startup_script_s3_path" {
  description = "S3 path to the malicious startup script"
  value       = "s3://${aws_s3_bucket.attacker_bucket.id}/${aws_s3_object.startup_script.key}"
}

output "dags_s3_path" {
  description = "S3 path to the DAGs folder"
  value       = "s3://${aws_s3_bucket.attacker_bucket.id}/dags/"
}

# =============================================================================
# ATTACK PATH DESCRIPTION
# =============================================================================

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-mwaa-001-to-admin-starting-user) -> iam:PassRole + airflow:CreateEnvironment -> MWAA environment with ${aws_iam_role.admin_role.name} -> startup script executes with admin credentials -> attaches AdministratorAccess to starting user -> admin access"
}

output "flag_ssm_parameter_name" {
  description = "Name of the SSM parameter containing the CTF flag"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM parameter containing the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}
