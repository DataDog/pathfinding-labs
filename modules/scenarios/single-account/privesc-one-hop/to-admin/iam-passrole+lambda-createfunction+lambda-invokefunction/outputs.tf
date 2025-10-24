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

output "starting_role_arn" {
  description = "ARN of the privilege escalation role"
  value       = aws_iam_role.privesc_role.arn
}

output "starting_role_name" {
  description = "Name of the privilege escalation role"
  value       = aws_iam_role.privesc_role.name
}

output "admin_role_arn" {
  description = "ARN of the admin role target"
  value       = aws_iam_role.admin_role.arn
}

output "admin_role_name" {
  description = "Name of the admin role"
  value       = aws_iam_role.admin_role.name
}

output "policy_arn" {
  description = "ARN of the privilege escalation policy"
  value       = aws_iam_policy.privesc_policy.arn
}

output "attack_path_description" {
  description = "Description of the attack path"
  value       = "User (pl-prod-one-hop-plcflif-starting-user) → AssumeRole → Role (pl-prod-one-hop-plcflif-role) → PassRole + CreateFunction + InvokeFunction → Role (pl-prod-one-hop-plcflif-admin-role) → Admin Access"
}
