# =============================================================================
# USER-DIRECT OUTPUTS (DIRECT ACCESS PATH)
# =============================================================================

output "user_direct_name" {
  description = "Name of pl-prod-dimp-user-direct (direct bucket access)"
  value       = aws_iam_user.user_direct.name
}

output "user_direct_arn" {
  description = "ARN of pl-prod-dimp-user-direct (direct bucket access)"
  value       = aws_iam_user.user_direct.arn
}

output "user_direct_access_key_id" {
  description = "Access key ID for pl-prod-dimp-user-direct"
  value       = aws_iam_access_key.user_direct.id
  sensitive   = true
}

output "user_direct_secret_access_key" {
  description = "Secret access key for pl-prod-dimp-user-direct"
  value       = aws_iam_access_key.user_direct.secret
  sensitive   = true
}

# =============================================================================
# USER-ASSUMER OUTPUTS (INDIRECT ACCESS VIA STS:ASSUMEROLE)
# =============================================================================

output "user_assumer_name" {
  description = "Name of pl-prod-dimp-user-assumer (indirect access via pl-prod-dimp-role-trusted)"
  value       = aws_iam_user.user_assumer.name
}

output "user_assumer_arn" {
  description = "ARN of pl-prod-dimp-user-assumer (indirect access via pl-prod-dimp-role-trusted)"
  value       = aws_iam_user.user_assumer.arn
}

output "user_assumer_access_key_id" {
  description = "Access key ID for pl-prod-dimp-user-assumer"
  value       = aws_iam_access_key.user_assumer.id
  sensitive   = true
}

output "user_assumer_secret_access_key" {
  description = "Secret access key for pl-prod-dimp-user-assumer"
  value       = aws_iam_access_key.user_assumer.secret
  sensitive   = true
}

# =============================================================================
# ROLE-TRUSTED OUTPUTS (INDIRECT ACCESS VIA STS:ASSUMEROLE)
# =============================================================================

output "role_trusted_name" {
  description = "Name of pl-prod-dimp-role-trusted (already trusts pl-prod-dimp-user-assumer, provides bucket access)"
  value       = aws_iam_role.role_trusted.name
}

output "role_trusted_arn" {
  description = "ARN of pl-prod-dimp-role-trusted (already trusts pl-prod-dimp-user-assumer, provides bucket access)"
  value       = aws_iam_role.role_trusted.arn
}

# =============================================================================
# USER-TRUSTBYPASS OUTPUTS (INDIRECT ACCESS VIA IAM:UPDATEASSUMEROLEPOLICY BYPASS)
# =============================================================================

output "user_trustbypass_name" {
  description = "Name of pl-prod-dimp-user-trustbypass (indirect access via trust-policy bypass on pl-prod-dimp-role-untrusted)"
  value       = aws_iam_user.user_trustbypass.name
}

output "user_trustbypass_arn" {
  description = "ARN of pl-prod-dimp-user-trustbypass (indirect access via trust-policy bypass on pl-prod-dimp-role-untrusted)"
  value       = aws_iam_user.user_trustbypass.arn
}

output "user_trustbypass_access_key_id" {
  description = "Access key ID for pl-prod-dimp-user-trustbypass"
  value       = aws_iam_access_key.user_trustbypass.id
  sensitive   = true
}

output "user_trustbypass_secret_access_key" {
  description = "Secret access key for pl-prod-dimp-user-trustbypass"
  value       = aws_iam_access_key.user_trustbypass.secret
  sensitive   = true
}

# =============================================================================
# ROLE-UNTRUSTED OUTPUTS (INDIRECT ACCESS VIA IAM:UPDATEASSUMEROLEPOLICY BYPASS)
# =============================================================================

output "role_untrusted_name" {
  description = "Name of pl-prod-dimp-role-untrusted (initially trusts only ec2.amazonaws.com, provides bucket access)"
  value       = aws_iam_role.role_untrusted.name
}

output "role_untrusted_arn" {
  description = "ARN of pl-prod-dimp-role-untrusted (initially trusts only ec2.amazonaws.com, provides bucket access)"
  value       = aws_iam_role.role_untrusted.arn
}

# =============================================================================
# BUCKET OUTPUTS
# =============================================================================

output "target_bucket_name" {
  description = "Name of the target S3 bucket"
  value       = aws_s3_bucket.target_bucket.id
}

output "target_bucket_arn" {
  description = "ARN of the target S3 bucket"
  value       = aws_s3_bucket.target_bucket.arn
}

# =============================================================================
# ATTACK PATH DESCRIPTION
# =============================================================================

output "attack_path" {
  description = "Description of all three reachability paths to the target bucket"
  value       = "Path 1 (Direct): ${aws_iam_user.user_direct.name} -> direct S3 access -> bucket (${aws_s3_bucket.target_bucket.id}) | Path 2 (Indirect via sts:AssumeRole): ${aws_iam_user.user_assumer.name} -> sts:AssumeRole -> ${aws_iam_role.role_trusted.name} (already trusted) -> S3 access -> bucket (${aws_s3_bucket.target_bucket.id}) | Path 3 (Indirect via iam:UpdateAssumeRolePolicy trust-policy bypass): ${aws_iam_user.user_trustbypass.name} -> iam:UpdateAssumeRolePolicy on ${aws_iam_role.role_untrusted.name} (initially trusts only ec2.amazonaws.com) -> sts:AssumeRole -> S3 access -> bucket (${aws_s3_bucket.target_bucket.id})"
}
