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
