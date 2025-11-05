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
  description = "ARN of the target role with S3 access"
  value       = aws_iam_role.target_role.arn
}

output "target_role_name" {
  description = "Name of the target role"
  value       = aws_iam_role.target_role.name
}

# Target bucket outputs
output "sensitive_bucket_name" {
  description = "Name of the target S3 bucket"
  value       = aws_s3_bucket.sensitive_bucket.id
}

output "sensitive_bucket_arn" {
  description = "ARN of the target S3 bucket"
  value       = aws_s3_bucket.sensitive_bucket.arn
}

# Attack path description
output "attack_path" {
  description = "Description of the attack path"
  value       = "starting_user → (iam:PassRole + glue:CreateDevEndpoint) → Glue dev endpoint with S3 role → SSH access → (aws s3 cp) → sensitive bucket access"
}
