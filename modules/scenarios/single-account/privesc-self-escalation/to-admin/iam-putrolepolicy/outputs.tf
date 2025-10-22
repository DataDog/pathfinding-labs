output "role_arn" {
  description = "ARN of the privilege escalation role"
  value       = aws_iam_role.privesc_role.arn
}

output "role_name" {
  description = "Name of the privilege escalation role"
  value       = aws_iam_role.privesc_role.name
}

output "policy_arn" {
  description = "ARN of the privilege escalation policy"
  value       = aws_iam_policy.privesc_policy.arn
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-pathfinder-starting-user-prod) → AssumeRole → Role (pl-prod-one-hop-putrolepolicy-role) → PutRolePolicy (self) → Admin Access"
}

