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

# Passable admin role outputs
output "passable_role_arn" {
  description = "ARN of the passable admin role"
  value       = aws_iam_role.passable_admin_role.arn
}

output "passable_role_name" {
  description = "Name of the passable admin role"
  value       = aws_iam_role.passable_admin_role.name
}

# S3 bucket outputs
output "bucket_name" {
  description = "Name of the S3 bucket for training scripts"
  value       = aws_s3_bucket.training_bucket.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket for training scripts"
  value       = aws_s3_bucket.training_bucket.arn
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-sagemaker-002-to-admin-starting-user) → Upload malicious script to S3 → PassRole + CreateTrainingJob → Training job executes with admin role → Script grants admin access to starting user"
}
