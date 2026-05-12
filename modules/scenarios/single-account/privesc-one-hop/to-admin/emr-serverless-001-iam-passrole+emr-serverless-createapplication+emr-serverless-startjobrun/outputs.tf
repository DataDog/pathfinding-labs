# =============================================================================
# STARTING USER OUTPUTS (Required for all scenarios)
# =============================================================================

output "starting_user_name" {
  description = "Name of the starting IAM user"
  value       = aws_iam_user.starting_user.name
}

output "starting_user_arn" {
  description = "ARN of the starting IAM user"
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

# =============================================================================
# ADMIN ROLE OUTPUTS (Privilege Escalation Target)
# =============================================================================

output "admin_role_arn" {
  description = "ARN of the admin role (target)"
  value       = aws_iam_role.admin_role.arn
}

output "admin_role_name" {
  description = "Name of the admin role"
  value       = aws_iam_role.admin_role.name
}

# =============================================================================
# S3 BUCKET OUTPUTS (Attacker-Controlled Exploit Script Staging)
# =============================================================================

output "attacker_bucket_name" {
  description = "Name of the attacker-controlled S3 bucket for exploit script staging"
  value       = aws_s3_bucket.scripts.id
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for exploit script staging"
  value       = aws_s3_bucket.scripts.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for exploit script staging"
  value       = aws_s3_bucket.scripts.arn
}

# =============================================================================
# ATTACK PATH DESCRIPTION
# =============================================================================

output "attack_path" {
  description = "Description of the attack path"
  value       = "starting_user (${aws_iam_user.starting_user.name}) -> (emr-serverless:CreateApplication) -> (iam:PassRole + emr-serverless:StartJobRun with ${aws_iam_role.admin_role.name} as execution role, referencing pre-staged exploit script in attacker bucket ${aws_s3_bucket.scripts.id}) -> Spark job exfiltrates admin creds to S3 -> attacker retrieves creds -> attaches AdministratorAccess to starting user -> admin access"
}
