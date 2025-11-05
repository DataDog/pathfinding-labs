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
  description = "ARN of the target role attached to the Glue dev endpoint"
  value       = aws_iam_role.target_role.arn
}

output "target_role_name" {
  description = "Name of the target role"
  value       = aws_iam_role.target_role.name
}

# Dev endpoint outputs
output "dev_endpoint_name" {
  description = "Name of the Glue dev endpoint"
  value       = aws_glue_dev_endpoint.target_endpoint.name
}

output "dev_endpoint_arn" {
  description = "ARN of the Glue dev endpoint"
  value       = aws_glue_dev_endpoint.target_endpoint.arn
}

output "dev_endpoint_address" {
  description = "SSH address of the Glue dev endpoint"
  value       = aws_glue_dev_endpoint.target_endpoint.public_address
}

# S3 bucket outputs
output "sensitive_bucket_name" {
  description = "Name of the sensitive S3 bucket"
  value       = aws_s3_bucket.sensitive_bucket.id
}

output "sensitive_bucket_arn" {
  description = "ARN of the sensitive S3 bucket"
  value       = aws_s3_bucket.sensitive_bucket.arn
}

# Attack path description
output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-gud-to-bucket-starting-user) → glue:UpdateDevEndpoint (add SSH key to ${aws_glue_dev_endpoint.target_endpoint.name}) → SSH access to endpoint → Role (${aws_iam_role.target_role.name}) → Sensitive bucket (${aws_s3_bucket.sensitive_bucket.id})"
}
