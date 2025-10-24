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

output "bucket_access_role_name" {
  description = "The name of the bucket access role"
  value       = aws_iam_role.bucket_access_role.name
}

output "bucket_access_role_arn" {
  description = "The ARN of the bucket access role"
  value       = aws_iam_role.bucket_access_role.arn
}

output "sensitive_bucket_name" {
  description = "The name of the sensitive S3 bucket"
  value       = aws_s3_bucket.sensitive_bucket.bucket
}

output "sensitive_bucket_arn" {
  description = "The ARN of the sensitive S3 bucket"
  value       = aws_s3_bucket.sensitive_bucket.arn
}

output "sensitive_bucket_domain_name" {
  description = "The domain name of the sensitive S3 bucket"
  value       = aws_s3_bucket.sensitive_bucket.bucket_domain_name
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-rpb-to-bucket-starting-user) → AssumeRole → pl-bucket-access-role → S3 Bucket Access (via resource policy bypass)"
}
