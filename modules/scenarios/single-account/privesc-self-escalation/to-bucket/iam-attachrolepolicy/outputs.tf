output "starting_user_name" {
  description = "Name of the scenario-specific starting user"
  value       = aws_iam_user.starting_user.name
}

output "starting_user_arn" {
  description = "ARN of the scenario-specific starting user"
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

output "starting_role_arn" {
  description = "ARN of the starting role"
  value       = aws_iam_role.starting_role.arn
}

output "starting_role_name" {
  description = "Name of the starting role"
  value       = aws_iam_role.starting_role.name
}

output "bucket_name" {
  description = "Name of the target S3 bucket"
  value       = aws_s3_bucket.target_bucket.id
}

output "bucket_arn" {
  description = "ARN of the target S3 bucket"
  value       = aws_s3_bucket.target_bucket.arn
}

output "bucket_access_policy_arn" {
  description = "ARN of the policy that grants bucket access"
  value       = aws_iam_policy.bucket_access_policy.arn
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-arp-to-bucket-starting-user) → AssumeRole → Role (pl-prod-arp-to-bucket-starting-role) → AttachRolePolicy (self) → S3 Bucket Access"
}
