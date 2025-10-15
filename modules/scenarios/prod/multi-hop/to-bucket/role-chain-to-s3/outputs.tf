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
