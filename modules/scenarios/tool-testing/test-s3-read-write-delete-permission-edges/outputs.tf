# =============================================================================
# STARTING USER OUTPUTS
# =============================================================================

output "starting_user_name" {
  description = "Name of the starting user (assumes the four role-based test principals)"
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
# READ-ONLY TIER OUTPUTS
# =============================================================================

output "user_read_only_name" {
  description = "Name of the IAM user with s3:GetObject + s3:ListBucket only"
  value       = aws_iam_user.user_read_only.name
}

output "user_read_only_arn" {
  description = "ARN of the IAM user with s3:GetObject + s3:ListBucket only"
  value       = aws_iam_user.user_read_only.arn
}

output "user_read_only_access_key_id" {
  description = "Access key ID for the read-only IAM user"
  value       = aws_iam_access_key.user_read_only.id
  sensitive   = true
}

output "user_read_only_secret_access_key" {
  description = "Secret access key for the read-only IAM user"
  value       = aws_iam_access_key.user_read_only.secret
  sensitive   = true
}

output "role_read_only_name" {
  description = "Name of the IAM role with s3:GetObject + s3:ListBucket only"
  value       = aws_iam_role.role_read_only.name
}

output "role_read_only_arn" {
  description = "ARN of the IAM role with s3:GetObject + s3:ListBucket only"
  value       = aws_iam_role.role_read_only.arn
}

# =============================================================================
# WRITE-ONLY TIER OUTPUTS
# =============================================================================

output "user_write_only_name" {
  description = "Name of the IAM user with s3:PutObject only"
  value       = aws_iam_user.user_write_only.name
}

output "user_write_only_arn" {
  description = "ARN of the IAM user with s3:PutObject only"
  value       = aws_iam_user.user_write_only.arn
}

output "user_write_only_access_key_id" {
  description = "Access key ID for the write-only IAM user"
  value       = aws_iam_access_key.user_write_only.id
  sensitive   = true
}

output "user_write_only_secret_access_key" {
  description = "Secret access key for the write-only IAM user"
  value       = aws_iam_access_key.user_write_only.secret
  sensitive   = true
}

output "role_write_only_name" {
  description = "Name of the IAM role with s3:PutObject only"
  value       = aws_iam_role.role_write_only.name
}

output "role_write_only_arn" {
  description = "ARN of the IAM role with s3:PutObject only"
  value       = aws_iam_role.role_write_only.arn
}

# =============================================================================
# DELETE-ONLY TIER OUTPUTS
# =============================================================================

output "user_delete_only_name" {
  description = "Name of the IAM user with s3:DeleteObject only"
  value       = aws_iam_user.user_delete_only.name
}

output "user_delete_only_arn" {
  description = "ARN of the IAM user with s3:DeleteObject only"
  value       = aws_iam_user.user_delete_only.arn
}

output "user_delete_only_access_key_id" {
  description = "Access key ID for the delete-only IAM user"
  value       = aws_iam_access_key.user_delete_only.id
  sensitive   = true
}

output "user_delete_only_secret_access_key" {
  description = "Secret access key for the delete-only IAM user"
  value       = aws_iam_access_key.user_delete_only.secret
  sensitive   = true
}

output "role_delete_only_name" {
  description = "Name of the IAM role with s3:DeleteObject only"
  value       = aws_iam_role.role_delete_only.name
}

output "role_delete_only_arn" {
  description = "ARN of the IAM role with s3:DeleteObject only"
  value       = aws_iam_role.role_delete_only.arn
}

# =============================================================================
# READ+WRITE+DELETE TIER OUTPUTS
# =============================================================================

output "user_read_write_delete_name" {
  description = "Name of the IAM user with full s3:GetObject/PutObject/DeleteObject/ListBucket access"
  value       = aws_iam_user.user_read_write_delete.name
}

output "user_read_write_delete_arn" {
  description = "ARN of the IAM user with full s3:GetObject/PutObject/DeleteObject/ListBucket access"
  value       = aws_iam_user.user_read_write_delete.arn
}

output "user_read_write_delete_access_key_id" {
  description = "Access key ID for the full-access IAM user"
  value       = aws_iam_access_key.user_read_write_delete.id
  sensitive   = true
}

output "user_read_write_delete_secret_access_key" {
  description = "Secret access key for the full-access IAM user"
  value       = aws_iam_access_key.user_read_write_delete.secret
  sensitive   = true
}

output "role_read_write_delete_name" {
  description = "Name of the IAM role with full s3:GetObject/PutObject/DeleteObject/ListBucket access"
  value       = aws_iam_role.role_read_write_delete.name
}

output "role_read_write_delete_arn" {
  description = "ARN of the IAM role with full s3:GetObject/PutObject/DeleteObject/ListBucket access"
  value       = aws_iam_role.role_read_write_delete.arn
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

output "seed_object_key" {
  description = "Key of the pre-existing seed object in the target bucket, used by read-only/delete-only principals to test access without needing write permission"
  value       = aws_s3_object.seed_object.key
}

# =============================================================================
# ATTACK PATH / SCENARIO SUMMARY
# =============================================================================

output "attack_path" {
  description = "Description of the attack path"
  value       = "8 independent test principals (pl-prod-rwd-user-read-only, pl-prod-rwd-role-read-only via pl-prod-rwd-starting-user assumption, pl-prod-rwd-user-write-only, pl-prod-rwd-role-write-only via assumption, pl-prod-rwd-user-delete-only, pl-prod-rwd-role-delete-only via assumption, pl-prod-rwd-user-read-write-delete, pl-prod-rwd-role-read-write-delete via assumption) each hold a precise non-overlapping subset of s3:GetObject/s3:PutObject/s3:DeleteObject/s3:ListBucket on the same bucket (pl-rwd-bucket-{account_id}-{suffix}) - to test that a graph/CSPM tool's can_read/can_write/can_delete edges are set exactly per principal with no over- or under-inference."
}

output "scenario_summary" {
  description = "Summary of the test scenario"
  value = {
    total_test_principals = 8
    users                 = 4
    roles                 = 4
    categories = {
      read_only         = "pl-prod-rwd-user-read-only, pl-prod-rwd-role-read-only"
      write_only        = "pl-prod-rwd-user-write-only, pl-prod-rwd-role-write-only"
      delete_only       = "pl-prod-rwd-user-delete-only, pl-prod-rwd-role-delete-only"
      read_write_delete = "pl-prod-rwd-user-read-write-delete, pl-prod-rwd-role-read-write-delete"
    }
    purpose = "Test CSPM/graph tools' ability to generate can_read/can_write/can_delete edges with exact granularity and no over- or under-inference"
  }
}
