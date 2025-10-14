output "privesc_role_arn" {
  description = "ARN of the starting privilege escalation role"
  value       = aws_iam_role.privesc_role.arn
}

output "bucket_access_role_arn" {
  description = "ARN of the role with S3 bucket access"
  value       = aws_iam_role.bucket_access_role.arn
}

output "target_bucket_name" {
  description = "Name of the target S3 bucket"
  value       = aws_s3_bucket.target_bucket.id
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User → AssumeRole → privesc-role → AttachRolePolicy (bucket-access-role) → AssumeRole → bucket-access-role → S3 Bucket Access"
}

