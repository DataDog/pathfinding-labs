output "scenario_name" {
  description = "The name of this scenario"
  value       = "iam-addusertogroup"
}

output "start_user_name" {
  description = "Name of the user that performs self-escalation"
  value       = aws_iam_user.start_user.name
}

output "start_user_arn" {
  description = "ARN of the user that performs self-escalation"
  value       = aws_iam_user.start_user.arn
}

output "start_user_access_key_id" {
  description = "Access key ID for the start user"
  value       = aws_iam_access_key.start_user_key.id
  sensitive   = true
}

output "start_user_secret_access_key" {
  description = "Secret access key for the start user"
  value       = aws_iam_access_key.start_user_key.secret
  sensitive   = true
}

output "admin_group_name" {
  description = "Name of the admin group"
  value       = aws_iam_group.admin_group.name
}

output "admin_group_arn" {
  description = "ARN of the admin group"
  value       = aws_iam_group.admin_group.arn
}

output "attack_path" {
  description = "Description of the privilege escalation path"
  value       = "pl-aug-start-user uses iam:AddUserToGroup to add themselves to pl-aug-admin-group, gaining AdministratorAccess"
}
