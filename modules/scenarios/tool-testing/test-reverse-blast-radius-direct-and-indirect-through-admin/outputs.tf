# =============================================================================
# USER 1 OUTPUTS (Direct S3 Access)
# =============================================================================

output "user1_name" {
  description = "Name of user1 (direct S3 access)"
  value       = aws_iam_user.user1.name
}

output "user1_arn" {
  description = "ARN of user1 (direct S3 access)"
  value       = aws_iam_user.user1.arn
}

output "user1_access_key_id" {
  description = "Access key ID for user1"
  value       = aws_iam_access_key.user1_key.id
  sensitive   = true
}

output "user1_secret_access_key" {
  description = "Secret access key for user1"
  value       = aws_iam_access_key.user1_key.secret
  sensitive   = true
}

# =============================================================================
# USER 2 OUTPUTS (Indirect Access Via Admin Role)
# =============================================================================

output "user2_name" {
  description = "Name of user2 (indirect access via admin role)"
  value       = aws_iam_user.user2.name
}

output "user2_arn" {
  description = "ARN of user2 (indirect access via admin role)"
  value       = aws_iam_user.user2.arn
}

output "user2_access_key_id" {
  description = "Access key ID for user2"
  value       = aws_iam_access_key.user2_key.id
  sensitive   = true
}

output "user2_secret_access_key" {
  description = "Secret access key for user2"
  value       = aws_iam_access_key.user2_key.secret
  sensitive   = true
}

# =============================================================================
# ROLE 3 OUTPUTS (Admin Role)
# =============================================================================

output "role3_name" {
  description = "Name of role3 (admin role)"
  value       = aws_iam_role.role3.name
}

output "role3_arn" {
  description = "ARN of role3 (admin role)"
  value       = aws_iam_role.role3.arn
}

# =============================================================================
# TARGET BUCKET OUTPUTS
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
  description = "Description of both attack paths to the bucket"
  value       = "Path 1 (Direct): user1 (${aws_iam_user.user1.name}) → (s3:GetObject, s3:ListBucket) → bucket (${aws_s3_bucket.target_bucket.id}) | Path 2 (Indirect): user2 (${aws_iam_user.user2.name}) → (sts:AssumeRole) → role3 (${aws_iam_role.role3.name}) → (AdministratorAccess) → bucket (${aws_s3_bucket.target_bucket.id})"
}
