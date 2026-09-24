# =============================================================================
# STARTING USER OUTPUTS
# =============================================================================

output "starting_user_name" {
  description = "Name of the starting user (assumes the two role-based test principals)"
  value       = aws_iam_user.starting_user.name
}

output "starting_user_arn" {
  description = "ARN of the starting user"
  value       = aws_iam_user.starting_user.arn
}

output "starting_user_access_key_id" {
  description = "Access key ID for the starting user"
  value       = aws_iam_access_key.starting_user.id
  sensitive   = true
}

output "starting_user_secret_access_key" {
  description = "Secret access key for the starting user"
  value       = aws_iam_access_key.starting_user.secret
  sensitive   = true
}

# =============================================================================
# IAM USER - INLINE POLICY OUTPUTS
# =============================================================================

output "user_inline_name" {
  description = "Name of the IAM user with an inline S3 access policy"
  value       = aws_iam_user.user_inline.name
}

output "user_inline_arn" {
  description = "ARN of the IAM user with an inline S3 access policy"
  value       = aws_iam_user.user_inline.arn
}

output "user_inline_access_key_id" {
  description = "Access key ID for the inline-policy IAM user"
  value       = aws_iam_access_key.user_inline.id
  sensitive   = true
}

output "user_inline_secret_access_key" {
  description = "Secret access key for the inline-policy IAM user"
  value       = aws_iam_access_key.user_inline.secret
  sensitive   = true
}

# =============================================================================
# IAM USER - MANAGED POLICY OUTPUTS
# =============================================================================

output "user_managed_name" {
  description = "Name of the IAM user with a customer-managed S3 access policy attached"
  value       = aws_iam_user.user_managed.name
}

output "user_managed_arn" {
  description = "ARN of the IAM user with a customer-managed S3 access policy attached"
  value       = aws_iam_user.user_managed.arn
}

output "user_managed_access_key_id" {
  description = "Access key ID for the managed-policy IAM user"
  value       = aws_iam_access_key.user_managed.id
  sensitive   = true
}

output "user_managed_secret_access_key" {
  description = "Secret access key for the managed-policy IAM user"
  value       = aws_iam_access_key.user_managed.secret
  sensitive   = true
}

# =============================================================================
# IAM ROLE - INLINE POLICY OUTPUTS
# =============================================================================

output "role_inline_name" {
  description = "Name of the IAM role with an inline S3 access policy"
  value       = aws_iam_role.role_inline.name
}

output "role_inline_arn" {
  description = "ARN of the IAM role with an inline S3 access policy"
  value       = aws_iam_role.role_inline.arn
}

# =============================================================================
# IAM ROLE - MANAGED POLICY OUTPUTS
# =============================================================================

output "role_managed_name" {
  description = "Name of the IAM role with a customer-managed S3 access policy attached"
  value       = aws_iam_role.role_managed.name
}

output "role_managed_arn" {
  description = "ARN of the IAM role with a customer-managed S3 access policy attached"
  value       = aws_iam_role.role_managed.arn
}

# =============================================================================
# BUCKET OUTPUTS
# =============================================================================

output "target_bucket_name" {
  description = "Name of the target S3 bucket"
  value       = aws_s3_bucket.target_bucket.bucket
}

output "target_bucket_arn" {
  description = "ARN of the target S3 bucket"
  value       = aws_s3_bucket.target_bucket.arn
}

# =============================================================================
# ATTACK PATH / SCENARIO SUMMARY
# =============================================================================

output "attack_path" {
  description = "Description of the attack path"
  value       = "4 independent principals (pl-prod-patn-user-inline, pl-prod-patn-user-managed, pl-prod-patn-role-inline via pl-prod-patn-starting-user assumption, pl-prod-patn-role-managed via pl-prod-patn-starting-user assumption) each already have s3:GetObject/s3:PutObject/s3:ListBucket on the same bucket (pl-patn-bucket-{account_id}-{suffix}) - granted via inline user/role policies for two principals and via a shared customer-managed policy attachment for the other two - to test that a graph/CSPM tool infers identical bucket-access edges regardless of IAM attachment mechanism."
}

output "scenario_summary" {
  description = "Summary of the test scenario"
  value = {
    total_test_principals = 4
    users                 = 2
    roles                 = 2
    categories = {
      inline_policy  = "pl-prod-patn-user-inline, pl-prod-patn-role-inline"
      managed_policy = "pl-prod-patn-user-managed, pl-prod-patn-role-managed"
    }
    purpose = "Test CSPM/graph tools' ability to detect equivalent S3 bucket access regardless of the IAM attachment mechanism (inline vs. customer-managed policy) used to grant it"
  }
}
