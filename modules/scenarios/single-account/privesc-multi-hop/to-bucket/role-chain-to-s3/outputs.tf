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

output "s3_bucket_name" {
  description = "Name of the S3 bucket destination"
  value       = aws_s3_bucket.prod_role_chain_destination.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket destination"
  value       = aws_s3_bucket.prod_role_chain_destination.arn
}

output "initial_role_arn" {
  description = "ARN of the initial role (can be assumed by operations account)"
  value       = aws_iam_role.prod_initial_role.arn
}

output "intermediate_role_arn" {
  description = "ARN of the intermediate role (can be assumed by initial role and IAM user)"
  value       = aws_iam_role.prod_intermediate_role.arn
}

output "s3_access_role_arn" {
  description = "ARN of the S3 access role (final role in the chain)"
  value       = aws_iam_role.prod_s3_access_role.arn
}

output "chain_user_name" {
  description = "Name of the IAM user that can assume the intermediate role"
  value       = aws_iam_user.prod_chain_user.name
}

output "initial_role_name" {
  description = "Name of the initial role"
  value       = aws_iam_role.prod_initial_role.name
}

output "intermediate_role_name" {
  description = "Name of the intermediate role"
  value       = aws_iam_role.prod_intermediate_role.name
}

output "s3_access_role_name" {
  description = "Name of the S3 access role"
  value       = aws_iam_role.prod_s3_access_role.name
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-rcs-to-bucket-starting-user) → AssumeRole → pl-prod-initial-role → AssumeRole → pl-prod-intermediate-role → AssumeRole → pl-prod-s3-access-role → S3 Bucket Access"
}

output "flag_s3_uri" {
  description = "S3 URI of the CTF flag object"
  value       = "s3://${aws_s3_bucket.prod_role_chain_destination.id}/flag.txt"
}
