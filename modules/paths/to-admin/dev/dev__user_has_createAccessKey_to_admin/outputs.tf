output "adam_user_name" {
  description = "The name of the Adam user who can create access keys for dev-admin"
  value       = aws_iam_user.adam.name
}

output "adam_user_arn" {
  description = "The ARN of the Adam user"
  value       = aws_iam_user.adam.arn
}

output "adam_policy_name" {
  description = "The name of the policy attached to Adam user"
  value       = aws_iam_user_policy.adam_create_access_key.name
}
