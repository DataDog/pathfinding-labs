output "starting_user_arn" {
  description = "ARN of the scenario-specific starting user"
  value       = aws_iam_user.starting_user.arn
}

output "starting_user_name" {
  description = "Name of the scenario-specific starting user"
  value       = aws_iam_user.starting_user.name
}

output "starting_user_access_key_id" {
  description = "Access key ID for the scenario-specific starting user"
  value       = aws_iam_access_key.starting_user_key.id
  sensitive   = true
}

output "starting_user_secret_access_key" {
  description = "Secret access key for the scenario-specific starting user"
  value       = aws_iam_access_key.starting_user_key.secret
  sensitive   = true
}

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
  value       = "User (pl-prod-one-hop-cak-starting-user) → AssumeRole → Role (pl-prod-one-hop-cak-role) → CreateAccessKey → User (pl-prod-one-hop-cak-admin) → Admin Access"
}

