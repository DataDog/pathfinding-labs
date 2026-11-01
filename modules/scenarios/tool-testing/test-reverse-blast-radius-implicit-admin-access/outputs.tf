# =============================================================================
# READER USER OUTPUTS (explicit read-only)
# =============================================================================

output "reader_user_name" {
  description = "Name of the reader user (explicit read-only access)"
  value       = aws_iam_user.reader_user.name
}

output "reader_user_arn" {
  description = "ARN of the reader user (explicit read-only access)"
  value       = aws_iam_user.reader_user.arn
}

output "reader_user_access_key_id" {
  description = "Access key ID for the reader user"
  value       = aws_iam_access_key.reader_user_key.id
  sensitive   = true
}

output "reader_user_secret_access_key" {
  description = "Secret access key for the reader user"
  value       = aws_iam_access_key.reader_user_key.secret
  sensitive   = true
}

# =============================================================================
# WRITER USER OUTPUTS (explicit write-only)
# =============================================================================

output "writer_user_name" {
  description = "Name of the writer user (explicit write-only access)"
  value       = aws_iam_user.writer_user.name
}

output "writer_user_arn" {
  description = "ARN of the writer user (explicit write-only access)"
  value       = aws_iam_user.writer_user.arn
}

output "writer_user_access_key_id" {
  description = "Access key ID for the writer user"
  value       = aws_iam_access_key.writer_user_key.id
  sensitive   = true
}

output "writer_user_secret_access_key" {
  description = "Secret access key for the writer user"
  value       = aws_iam_access_key.writer_user_key.secret
  sensitive   = true
}

# =============================================================================
# ADMIN USER OUTPUTS (AdministratorAccess managed policy)
# =============================================================================

output "admin_user_name" {
  description = "Name of the admin user (AdministratorAccess, implicit bucket access)"
  value       = aws_iam_user.admin_user.name
}

output "admin_user_arn" {
  description = "ARN of the admin user (AdministratorAccess, implicit bucket access)"
  value       = aws_iam_user.admin_user.arn
}

output "admin_user_access_key_id" {
  description = "Access key ID for the admin user"
  value       = aws_iam_access_key.admin_user_key.id
  sensitive   = true
}

output "admin_user_secret_access_key" {
  description = "Secret access key for the admin user"
  value       = aws_iam_access_key.admin_user_key.secret
  sensitive   = true
}

# =============================================================================
# ADMIN ROLE OUTPUTS (inline Action * Resource *)
# =============================================================================

output "admin_role_name" {
  description = "Name of the admin role (inline wildcard policy, trusts only ec2.amazonaws.com)"
  value       = aws_iam_role.admin_role.name
}

output "admin_role_arn" {
  description = "ARN of the admin role (inline wildcard policy, trusts only ec2.amazonaws.com)"
  value       = aws_iam_role.admin_role.arn
}

# =============================================================================
# NO-ACCESS USER OUTPUTS (negative control)
# =============================================================================

output "no_access_user_name" {
  description = "Name of the no-access user (negative control)"
  value       = aws_iam_user.no_access_user.name
}

output "no_access_user_arn" {
  description = "ARN of the no-access user (negative control)"
  value       = aws_iam_user.no_access_user.arn
}

output "no_access_user_access_key_id" {
  description = "Access key ID for the no-access user"
  value       = aws_iam_access_key.no_access_user_key.id
  sensitive   = true
}

output "no_access_user_secret_access_key" {
  description = "Secret access key for the no-access user"
  value       = aws_iam_access_key.no_access_user_key.secret
  sensitive   = true
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
  description = "Description of the explicit and implicit access paths to the bucket"
  value       = "Explicit: reader-user (${aws_iam_user.reader_user.name}) → (s3:GetObject, s3:ListBucket) and writer-user (${aws_iam_user.writer_user.name}) → (s3:PutObject) → bucket (${aws_s3_bucket.target_bucket.id}) | Implicit: admin-user (${aws_iam_user.admin_user.name}) → (AdministratorAccess) and admin-role (${aws_iam_role.admin_role.name}) → (inline Action * Resource *) → bucket (${aws_s3_bucket.target_bucket.id}) | Negative control: no-access-user (${aws_iam_user.no_access_user.name}) has no access | can_read = reader, admin-user, admin-role | can_write = writer, admin-user, admin-role"
}
