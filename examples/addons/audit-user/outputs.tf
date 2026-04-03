output "audit_user_arn" {
  description = "ARN of the read-only audit IAM user"
  value       = aws_iam_user.audit_user.arn
}

output "audit_user_name" {
  description = "Name of the read-only audit IAM user"
  value       = aws_iam_user.audit_user.name
}

output "audit_user_access_key_id" {
  description = "Access key ID for the read-only audit user"
  value       = aws_iam_access_key.audit_user.id
  sensitive   = true
}

output "audit_user_secret_access_key" {
  description = "Secret access key for the read-only audit user"
  value       = aws_iam_access_key.audit_user.secret
  sensitive   = true
}
