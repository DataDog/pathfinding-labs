output "attacker_account_id" {
  description = "The account ID of the attacker account"
  value       = var.attacker_account_id
}

output "admin_user_access_key_id" {
  description = "Access key ID for the attacker admin user"
  value       = aws_iam_access_key.admin_user.id
  sensitive   = true
}

output "admin_user_secret_access_key" {
  description = "Secret access key for the attacker admin user"
  value       = aws_iam_access_key.admin_user.secret
  sensitive   = true
}
