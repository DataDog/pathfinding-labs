# =============================================================================
# STARTING USER OUTPUTS (required for all scenarios)
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
  description = "Access key ID for the scenario-specific starting user"
  value       = aws_iam_access_key.starting_user_key.id
  sensitive   = true
}

output "starting_user_secret_access_key" {
  description = "Secret access key for the scenario-specific starting user"
  value       = aws_iam_access_key.starting_user_key.secret
  sensitive   = true
}

# =============================================================================
# SCENARIO RESOURCE OUTPUTS
# =============================================================================

output "rag_bucket_name" {
  description = "Name of the private RAG data S3 bucket (contains embedded credentials)"
  value       = aws_s3_bucket.rag_data.id
}

output "compromised_user_name" {
  description = "Name of the user whose credentials are embedded in the RAG bucket config"
  value       = aws_iam_user.compromised_user.name
}

output "ec2_init_function_name" {
  description = "Name of the ec2-init Lambda function (target for code injection)"
  value       = aws_lambda_function.ec2_init.function_name
}

output "frick_username" {
  description = "Name of the admin user whose access keys the attacker creates via the Lambda"
  value       = aws_iam_user.frick.name
}

# =============================================================================
# CTF FLAG OUTPUTS
# =============================================================================

output "flag_ssm_parameter_name" {
  description = "Name of the SSM parameter holding the CTF flag (requires admin access to read)"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM parameter holding the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}

# =============================================================================
# ATTACK PATH
# =============================================================================

output "attack_path" {
  description = "Human-readable description of the full attack chain"
  value       = "starting_user (pl-prod-8min-starting-user) → (s3:ListBucket + s3:GetObject) → private RAG bucket (credentials embedded in config/rag-pipeline-config.json) → compromised_user (pl-prod-8min-compromised-user) → (lambda:UpdateFunctionCode + lambda:UpdateFunctionConfiguration + lambda:InvokeFunction) → ec2-init Lambda (pl-prod-8min-ec2-init) → (iam:CreateAccessKey via ec2-init-role) → frick (pl-prod-8min-frick, admin) → (iam:CreateUser + iam:AttachUserPolicy) → backdoor-admin (AdministratorAccess)"
}
