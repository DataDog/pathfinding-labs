# =============================================================================
# USER1 OUTPUTS (DIRECT ACCESS PATH)
# =============================================================================

output "user1_name" {
  description = "Name of user1 (direct access)"
  value       = aws_iam_user.user1.name
}

output "user1_arn" {
  description = "ARN of user1 (direct access)"
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
# USER2 OUTPUTS (INDIRECT ACCESS PATH)
# =============================================================================

output "user2_name" {
  description = "Name of user2 (indirect access via role3)"
  value       = aws_iam_user.user2.name
}

output "user2_arn" {
  description = "ARN of user2 (indirect access via role3)"
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
# ROLE3 OUTPUTS (INDIRECT ACCESS PATH)
# =============================================================================

output "role3_name" {
  description = "Name of role3 (provides indirect bucket access)"
  value       = aws_iam_role.role3.name
}

output "role3_arn" {
  description = "ARN of role3 (provides indirect bucket access)"
  value       = aws_iam_role.role3.arn
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
  description = "Description of both attack paths"
  value       = "Path 1 (Direct): user1 (${aws_iam_user.user1.name}) → direct S3 access → bucket (${aws_s3_bucket.target_bucket.id}) | Path 2 (Indirect): user2 (${aws_iam_user.user2.name}) → sts:AssumeRole → role3 (${aws_iam_role.role3.name}) → S3 access → bucket (${aws_s3_bucket.target_bucket.id})"
}
