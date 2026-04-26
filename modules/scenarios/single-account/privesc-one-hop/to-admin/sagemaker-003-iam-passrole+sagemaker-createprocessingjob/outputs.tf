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

# Passable role outputs
output "passable_role_arn" {
  description = "ARN of the passable admin role"
  value       = aws_iam_role.passable_role.arn
}

output "passable_role_name" {
  description = "Name of the passable admin role"
  value       = aws_iam_role.passable_role.name
}

# S3 bucket outputs
output "bucket_name" {
  description = "Name of the S3 bucket for processing scripts"
  value       = aws_s3_bucket.processing_bucket.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket for processing scripts"
  value       = aws_s3_bucket.processing_bucket.arn
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-sagemaker-003-to-admin-starting-user) → Upload malicious script to S3 → CreateProcessingJob with admin role (pl-prod-sagemaker-003-to-admin-passable-role) → Processing job executes script with admin privileges → Script grants admin access to starting user"
}

output "flag_ssm_parameter_name" {
  description = "Name of the SSM parameter containing the CTF flag"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM parameter containing the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}
