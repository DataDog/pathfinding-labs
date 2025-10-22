output "role_arn" {
  description = "ARN of the privilege escalation role"
  value       = aws_iam_role.privesc_role.arn
}

output "role_name" {
  description = "Name of the privilege escalation role"
  value       = aws_iam_role.privesc_role.name
}

output "user_name" {
  description = "Name of the privilege escalation user"
  value       = aws_iam_user.privesc_user.name
}

output "user_arn" {
  description = "ARN of the privilege escalation user"
  value       = aws_iam_user.privesc_user.arn
}

output "user_access_key_id" {
  description = "Access key ID for the privilege escalation user (for demo purposes)"
  value       = aws_iam_access_key.privesc_user_key.id
}

output "user_secret_access_key" {
  description = "Secret access key for the privilege escalation user (for demo purposes)"
  value       = aws_iam_access_key.privesc_user_key.secret
  sensitive   = true
}

output "policy_arn" {
  description = "ARN of the PutUserPolicy policy"
  value       = aws_iam_policy.putuserpolicy_policy.arn
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User/Role → PutUserPolicy → Attach inline admin policy to self → Admin Access"
}