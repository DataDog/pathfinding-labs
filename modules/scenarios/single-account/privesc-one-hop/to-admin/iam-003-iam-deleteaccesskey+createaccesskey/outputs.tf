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

# Admin user outputs (target)
output "admin_user_arn" {
  description = "ARN of the admin user (target)"
  value       = aws_iam_user.admin_user.arn
}

output "admin_user_name" {
  description = "Name of the admin user"
  value       = aws_iam_user.admin_user.name
}

# Existing access key IDs (for reference in demo scripts)
output "admin_user_existing_key_1_id" {
  description = "First existing access key ID for admin user (demonstrating 2-key limit)"
  value       = aws_iam_access_key.admin_user_key_1.id
  sensitive   = true
}

output "admin_user_existing_key_2_id" {
  description = "Second existing access key ID for admin user (demonstrating 2-key limit)"
  value       = aws_iam_access_key.admin_user_key_2.id
  sensitive   = true
}

# Attack path description
output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-iam-003-to-admin-starting-user) → ListAccessKeys → DeleteAccessKey → CreateAccessKey → User (pl-prod-iam-003-to-admin-target-user) → Admin Access"
}
