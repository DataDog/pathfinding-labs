output "admin_role_arn" {
  description = "ARN of the admin role that can be assumed"
  value       = aws_iam_role.admin_role.arn
}

output "admin_role_name" {
  description = "Name of the admin role"
  value       = aws_iam_role.admin_role.name
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "pl-pathfinder-starting-user-prod → (sts:AssumeRole) → pl-prod-one-hop-assumerole-admin-role → Administrator Access"
}