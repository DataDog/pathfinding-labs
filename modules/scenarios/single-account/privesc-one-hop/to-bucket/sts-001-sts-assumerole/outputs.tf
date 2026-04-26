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

output "bucket_access_role_arn" {
  value = aws_iam_role.bucket_access_role.arn
}

output "target_bucket_name" {
  value = aws_s3_bucket.target_bucket.id
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-sts-001-to-bucket-starting-user) → AssumeRole → pl-prod-sts-001-to-bucket-access-role → S3 Bucket Access"
}

output "flag_s3_uri" {
  description = "S3 URI of the CTF flag object"
  value       = "s3://${aws_s3_bucket.target_bucket.id}/flag.txt"
}

