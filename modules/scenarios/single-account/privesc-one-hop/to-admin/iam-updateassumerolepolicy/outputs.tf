output "starting_user_name" {
  description = "Name of the scenario-specific starting user"
  value       = aws_iam_user.starting_user.name
}

output "starting_user_arn" {
  description = "ARN of the scenario-specific starting user"
  value       = aws_iam_user.starting_user.arn
}

output "starting_user_access_key_id" {
  description = "Access key ID for the starting user"
  value       = aws_iam_access_key.starting_user.id
  sensitive   = true
}

output "starting_user_secret_access_key" {
  description = "Secret access key for the starting user"
  value       = aws_iam_access_key.starting_user.secret
  sensitive   = true
}

output "starting_role_arn" {
  description = "ARN of the starting role for this attack path"
  value       = aws_iam_role.starting_role.arn
}

output "starting_role_name" {
  description = "Name of the starting role"
  value       = aws_iam_role.starting_role.name
}

output "target_role_arn" {
  description = "ARN of the target admin role whose trust policy will be modified"
  value       = aws_iam_role.target_role.arn
}

output "target_role_name" {
  description = "Name of the target admin role"
  value       = aws_iam_role.target_role.name
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "pl-prod-uar-to-admin-starting-user → (AssumeRole) → pl-prod-uar-to-admin-starting-role → (iam:UpdateAssumeRolePolicy) → pl-prod-uar-to-admin-target-role → Administrator"
}