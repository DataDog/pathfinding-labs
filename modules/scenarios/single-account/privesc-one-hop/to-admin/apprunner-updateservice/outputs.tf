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

output "target_service_name" {
  description = "Name of the target App Runner service"
  value       = aws_apprunner_service.target_service.service_name
}

output "target_service_arn" {
  description = "ARN of the target App Runner service"
  value       = aws_apprunner_service.target_service.arn
}

output "target_role_name" {
  description = "Name of the admin target role"
  value       = aws_iam_role.target_role.name
}

output "target_role_arn" {
  description = "ARN of the admin target role"
  value       = aws_iam_role.target_role.arn
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-aus-to-admin-starting-user) → UpdateService → App Runner Service (pl-prod-aus-to-admin-target-service) → Updates Image + StartCommand → Executes with Admin Role (pl-prod-aus-to-admin-target-role) → Admin Access"
}
