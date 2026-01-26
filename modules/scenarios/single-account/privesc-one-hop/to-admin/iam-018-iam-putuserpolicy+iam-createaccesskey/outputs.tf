# Scenario-specific starting user outputs (REQUIRED FOR ALL SCENARIOS)
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

# Target user outputs
output "target_user_arn" {
  description = "ARN of the target user"
  value       = aws_iam_user.target_user.arn
}

output "target_user_name" {
  description = "Name of the target user"
  value       = aws_iam_user.target_user.name
}

# Attack path description
output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-iam-018-to-admin-starting-user) → PutUserPolicy on target_user → CreateAccessKey for target_user → Authenticate as target_user → Admin access"
}
