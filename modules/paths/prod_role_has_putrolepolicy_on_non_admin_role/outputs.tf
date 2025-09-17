output "role_a_arn" {
  description = "ARN of RoleA (non-admin role with PutRolePolicy permission)"
  value       = aws_iam_role.prod_role_a.arn
}

output "role_b_arn" {
  description = "ARN of RoleB (admin role that trusts RoleA)"
  value       = aws_iam_role.prod_role_b.arn
}

output "admin_bucket_name" {
  description = "Name of the admin demo S3 bucket"
  value       = aws_s3_bucket.prod_admin_demo_bucket.bucket
}

output "admin_bucket_arn" {
  description = "ARN of the admin demo S3 bucket"
  value       = aws_s3_bucket.prod_admin_demo_bucket.arn
}

output "role_a_policy_arn" {
  description = "ARN of the policy that allows RoleA to modify RoleB's policies"
  value       = aws_iam_policy.prod_role_a_policy.arn
}
