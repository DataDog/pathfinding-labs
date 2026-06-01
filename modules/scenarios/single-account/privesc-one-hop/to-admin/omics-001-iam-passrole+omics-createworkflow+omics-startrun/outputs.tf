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
# S3 BUCKET OUTPUTS (Attacker exfiltration bucket)
# =============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket for workflow output and credential exfiltration"
  value       = aws_s3_bucket.output.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for workflow output and credential exfiltration"
  value       = aws_s3_bucket.output.arn
}

output "attacker_bucket_name" {
  description = "Name of the attacker-controlled exfiltration bucket"
  value       = aws_s3_bucket.output.id
}

# =============================================================================
# ECR IMAGE URI (Private ECR URI for HealthOmics Workflow)
# =============================================================================

output "ecr_image_uri" {
  description = "Private ECR image URI for the HealthOmics workflow container"
  value       = "${aws_ecr_repository.workflow_image.repository_url}:latest"
}

output "ecr_registry" {
  description = "ECR registry URL (account.dkr.ecr.region.amazonaws.com)"
  value       = split("/", aws_ecr_repository.workflow_image.repository_url)[0]
}

# =============================================================================
# ATTACK PATH DESCRIPTION
# =============================================================================

output "attack_path" {
  description = "Description of the attack path"
  value       = "starting_user (${aws_iam_user.starting_user.name}) -> (omics:CreateWorkflow to create WDL workflow) -> (iam:PassRole + omics:StartRun with ${aws_iam_role.admin_role.name} as run role) -> workflow task exfiltrates admin credentials to S3 (${aws_s3_bucket.output.id}) -> attacker retrieves credentials from S3 -> admin access"
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
