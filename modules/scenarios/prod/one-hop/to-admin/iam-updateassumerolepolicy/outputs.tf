output "starting_role_arn" {
  description = "ARN of the starting role for this attack path"
  value       = aws_iam_role.starting_role.arn
}

output "admin_role_arn" {
  description = "ARN of the admin role whose trust policy will be modified"
  value       = aws_iam_role.admin_role.arn
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "pl-pathfinder-starting-user-prod → pl-prod-one-hop-updateassumerolepolicy-role → (iam:UpdateAssumeRolePolicy) → pl-prod-one-hop-updateassumerolepolicy-admin-role → Administrator"
}