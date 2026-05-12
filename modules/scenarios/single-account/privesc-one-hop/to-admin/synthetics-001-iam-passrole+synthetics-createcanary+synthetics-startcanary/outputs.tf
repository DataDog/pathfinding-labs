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

# Admin role outputs
output "admin_role_arn" {
  description = "ARN of the admin role (target)"
  value       = aws_iam_role.admin_role.arn
}

output "admin_role_name" {
  description = "Name of the admin role"
  value       = aws_iam_role.admin_role.name
}

# S3 bucket outputs
output "s3_bucket_name" {
  description = "Name of the canary artifacts S3 bucket"
  value       = aws_s3_bucket.canary_artifacts.id
}

output "s3_bucket_arn" {
  description = "ARN of the canary artifacts S3 bucket"
  value       = aws_s3_bucket.canary_artifacts.arn
}

# Attacker bucket outputs
output "attacker_bucket_name" {
  description = "Name of the attacker S3 bucket containing exploit canary code"
  value       = aws_s3_bucket.exploit_code.id
}

# Attack path description
output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-synthetics-001-to-admin-starting-user) -> PassRole + synthetics:CreateCanary (with malicious code from attacker bucket and admin execution role) -> synthetics:StartCanary -> canary Lambda attaches AdministratorAccess to starting user -> Admin Access"
}
