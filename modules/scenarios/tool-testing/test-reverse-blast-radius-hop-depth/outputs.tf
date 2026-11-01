# =============================================================================
# USER-A OUTPUTS (DEPTH 0, DIRECT S3)
# =============================================================================

output "user_a_name" {
  description = "Name of user-a (depth 0, direct S3 access)"
  value       = aws_iam_user.user_a.name
}

output "user_a_arn" {
  description = "ARN of user-a (depth 0, direct S3 access)"
  value       = aws_iam_user.user_a.arn
}

output "user_a_access_key_id" {
  description = "Access key ID for user-a"
  value       = aws_iam_access_key.user_a_key.id
  sensitive   = true
}

output "user_a_secret_access_key" {
  description = "Secret access key for user-a"
  value       = aws_iam_access_key.user_a_key.secret
  sensitive   = true
}

# =============================================================================
# USER-B OUTPUTS (DEPTH 1, ASSUMES ROLE-R1)
# =============================================================================

output "user_b_name" {
  description = "Name of user-b (depth 1, assumes role-r1)"
  value       = aws_iam_user.user_b.name
}

output "user_b_arn" {
  description = "ARN of user-b (depth 1, assumes role-r1)"
  value       = aws_iam_user.user_b.arn
}

output "user_b_access_key_id" {
  description = "Access key ID for user-b"
  value       = aws_iam_access_key.user_b_key.id
  sensitive   = true
}

output "user_b_secret_access_key" {
  description = "Secret access key for user-b"
  value       = aws_iam_access_key.user_b_key.secret
  sensitive   = true
}

# =============================================================================
# USER-C OUTPUTS (DEPTH 2, ASSUMES ROLE-R2 -> ROLE-R1)
# =============================================================================

output "user_c_name" {
  description = "Name of user-c (depth 2, assumes role-r2 then role-r1)"
  value       = aws_iam_user.user_c.name
}

output "user_c_arn" {
  description = "ARN of user-c (depth 2, assumes role-r2 then role-r1)"
  value       = aws_iam_user.user_c.arn
}

output "user_c_access_key_id" {
  description = "Access key ID for user-c"
  value       = aws_iam_access_key.user_c_key.id
  sensitive   = true
}

output "user_c_secret_access_key" {
  description = "Secret access key for user-c"
  value       = aws_iam_access_key.user_c_key.secret
  sensitive   = true
}

# =============================================================================
# ROLE OUTPUTS
# =============================================================================

output "role_r1_name" {
  description = "Name of role-r1 (depth 0, direct S3 access)"
  value       = aws_iam_role.role_r1.name
}

output "role_r1_arn" {
  description = "ARN of role-r1 (depth 0, direct S3 access)"
  value       = aws_iam_role.role_r1.arn
}

output "role_r2_name" {
  description = "Name of role-r2 (depth 1, assumes role-r1)"
  value       = aws_iam_role.role_r2.name
}

output "role_r2_arn" {
  description = "ARN of role-r2 (depth 1, assumes role-r1)"
  value       = aws_iam_role.role_r2.arn
}

# =============================================================================
# BUCKET OUTPUTS
# =============================================================================

output "bucket_name" {
  description = "Name of the target S3 bucket"
  value       = aws_s3_bucket.target_bucket.id
}

output "bucket_arn" {
  description = "ARN of the target S3 bucket"
  value       = aws_s3_bucket.target_bucket.arn
}

# =============================================================================
# ATTACK PATH DESCRIPTION
# =============================================================================

output "attack_path" {
  description = "Description of the access paths by hop depth"
  value       = "Depth 0: user-a (${aws_iam_user.user_a.name}) and role-r1 (${aws_iam_role.role_r1.name}) have direct S3 access to bucket (${aws_s3_bucket.target_bucket.id}) | Depth 1: user-b (${aws_iam_user.user_b.name}) → sts:AssumeRole → role-r1, and role-r2 (${aws_iam_role.role_r2.name}) → sts:AssumeRole → role-r1 | Depth 2: user-c (${aws_iam_user.user_c.name}) → sts:AssumeRole → role-r2 → sts:AssumeRole → role-r1 → bucket"
}
