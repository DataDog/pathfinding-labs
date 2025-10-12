output "exclusive_bucket_access_role_name" {
  description = "The name of the exclusive bucket access role"
  value       = aws_iam_role.exclusive_bucket_access_role.name
}

output "exclusive_bucket_access_role_arn" {
  description = "The ARN of the exclusive bucket access role"
  value       = aws_iam_role.exclusive_bucket_access_role.arn
}

output "exclusive_sensitive_bucket_name" {
  description = "The name of the exclusive sensitive S3 bucket"
  value       = aws_s3_bucket.exclusive_sensitive_bucket.bucket
}

output "exclusive_sensitive_bucket_arn" {
  description = "The ARN of the exclusive sensitive S3 bucket"
  value       = aws_s3_bucket.exclusive_sensitive_bucket.arn
}

output "exclusive_sensitive_bucket_domain_name" {
  description = "The domain name of the exclusive sensitive S3 bucket"
  value       = aws_s3_bucket.exclusive_sensitive_bucket.bucket_domain_name
}
