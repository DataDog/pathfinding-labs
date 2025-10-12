output "s3_bucket_name" {
  description = "The name of the created S3 bucket"
  value       = aws_s3_bucket.sensitive_data.bucket
}

output "s3_bucket_arn" {
  description = "The ARN of the created S3 bucket"
  value       = aws_s3_bucket.sensitive_data.arn
}

output "prod_role_arn" {
  description = "The ARN of the IAM role in prod that can access the S3 bucket"
  value       = aws_iam_role.s3_access_role.arn
}

output "dev_role_arn" {
  description = "The ARN of the IAM role in dev that can assume the prod role"
  value       = aws_iam_role.s3_access_role_dev.arn
}

output "dev_user_name" {
  description = "The name of the IAM user in dev that can assume the prod role"
  value       = aws_iam_user.s3_access_user.name
}

output "dev_user_arn" {
  description = "The ARN of the IAM user in dev that can assume the prod role"
  value       = aws_iam_user.s3_access_user.arn
} 