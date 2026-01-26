output "scenario_name" {
  description = "The name of this scenario"
  value       = "iam-011-iam-putgrouppolicy"
}

output "privesc_user_name" {
  description = "Name of the user that performs self-escalation"
  value       = aws_iam_user.privesc_user.name
}

output "privesc_user_arn" {
  description = "ARN of the user that performs self-escalation"
  value       = aws_iam_user.privesc_user.arn
}

output "privesc_user_access_key_id" {
  description = "Access key ID for the privilege escalation user"
  value       = aws_iam_access_key.privesc_user_key.id
  sensitive   = true
}

output "privesc_user_secret_access_key" {
  description = "Secret access key for the privilege escalation user"
  value       = aws_iam_access_key.privesc_user_key.secret
  sensitive   = true
}

output "target_group_name" {
  description = "Name of the group that will be escalated"
  value       = aws_iam_group.target_group.name
}

output "target_group_arn" {
  description = "ARN of the group that will be escalated"
  value       = aws_iam_group.target_group.arn
}

output "attack_path" {
  description = "Description of the privilege escalation path"
  value       = "pl-prod-iam-011-to-admin-paul (member of pl-prod-iam-011-to-admin-escalation-group) uses iam:PutGroupPolicy to add admin policy to their own group, escalating themselves to admin"
}