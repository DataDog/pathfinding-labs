output "bucket_access_role_arn" {
  value = aws_iam_role.bucket_access_role.arn
}

output "target_bucket_name" {
  value = aws_s3_bucket.target_bucket.id
}

