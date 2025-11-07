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

# Target user's existing access keys (for reference - these are already at the 2-key limit)
output "target_user_key_1_id" {
  description = "Access key ID 1 for target user (existing key at AWS limit)"
  value       = aws_iam_access_key.target_user_key_1.id
  sensitive   = true
}

output "target_user_key_2_id" {
  description = "Access key ID 2 for target user (existing key at AWS limit)"
  value       = aws_iam_access_key.target_user_key_2.id
  sensitive   = true
}

# Target bucket outputs
output "target_bucket_name" {
  description = "Name of the target S3 bucket"
  value       = aws_s3_bucket.target_bucket.id
}

output "target_bucket_arn" {
  description = "ARN of the target S3 bucket"
  value       = aws_s3_bucket.target_bucket.arn
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-dakcak-to-bucket-starting-user) → list access keys (iam:ListAccessKeys) → delete existing key (iam:DeleteAccessKey) → create new key (iam:CreateAccessKey) → target user (pl-prod-dakcak-to-bucket-target-user) → S3 bucket access"
}
