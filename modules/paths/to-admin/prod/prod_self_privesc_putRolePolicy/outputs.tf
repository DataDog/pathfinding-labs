output "role_arn" {
  description = "ARN of the self-privilege escalation role"
  value       = aws_iam_role.prod_self_privesc_putRolePolicy_role.arn
}

output "role_name" {
  description = "Name of the self-privilege escalation role"
  value       = aws_iam_role.prod_self_privesc_putRolePolicy_role.name
}

output "policy_arn" {
  description = "ARN of the self-privilege escalation policy"
  value       = aws_iam_policy.prod_self_privesc_putRolePolicy_policy.arn
}
