output "role_arn" {
  description = "ARN of the privilege escalation role"
  value       = aws_iam_role.privesc_role.arn
}

output "role_name" {
  description = "Name of the privilege escalation role"
  value       = aws_iam_role.privesc_role.name
}

output "admin_user_name" {
  description = "Name of the admin user target"
  value       = aws_iam_user.admin_user.name
}

output "admin_user_arn" {
  description = "ARN of the admin user target"
  value       = aws_iam_user.admin_user.arn
}

output "policy_arn" {
  description = "ARN of the privilege escalation policy"
  value       = aws_iam_policy.privesc_policy.arn
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-pathfinder-starting-user-prod) → AssumeRole → Role (pl-cak-adam) → CreateAccessKey → User (pl-cak-admin) → Admin Access"
}

