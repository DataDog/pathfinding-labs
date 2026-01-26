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

# Target user outputs
output "target_user_arn" {
  description = "ARN of the target user with S3 bucket access"
  value       = aws_iam_user.target_user.arn
}

output "target_user_name" {
  description = "Name of the target user with S3 bucket access"
  value       = aws_iam_user.target_user.name
}

output "original_password" {
  description = "Original password for the target user (set by Terraform)"
  value       = aws_iam_user_login_profile.target_login_profile.password
  sensitive   = true
}

# S3 bucket outputs
output "sensitive_bucket_name" {
  description = "Name of the target S3 bucket containing sensitive data"
  value       = aws_s3_bucket.target_bucket.id
}

output "sensitive_bucket_arn" {
  description = "ARN of the target S3 bucket"
  value       = aws_s3_bucket.target_bucket.arn
}

# Console login URL
output "console_login_url" {
  description = "AWS Console login URL for the account"
  value       = "https://${var.account_id}.signin.aws.amazon.com/console"
}

# Attack path description
output "attack_path" {
  description = "Description of the attack path"
  value       = "pl-prod-iam-006-to-bucket-starting-user → (iam:UpdateLoginProfile) → pl-prod-iam-006-to-bucket-user → (Console Login) → S3 Bucket Access (${aws_s3_bucket.target_bucket.id})"
}

output "attack_path_summary" {
  description = "Summary of the privilege escalation path"
  value       = "User with iam:UpdateLoginProfile can change the console password of a user with S3 bucket access, then login to the console and access sensitive data"
}
