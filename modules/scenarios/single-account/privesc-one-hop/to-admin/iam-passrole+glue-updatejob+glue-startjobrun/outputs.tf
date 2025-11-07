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

# Initial role outputs
output "initial_role_arn" {
  description = "ARN of the initial non-privileged role"
  value       = aws_iam_role.initial_role.arn
}

output "initial_role_name" {
  description = "Name of the initial non-privileged role"
  value       = aws_iam_role.initial_role.name
}

# Target admin role outputs
output "target_role_arn" {
  description = "ARN of the target admin role"
  value       = aws_iam_role.target_role.arn
}

output "target_role_name" {
  description = "Name of the target admin role"
  value       = aws_iam_role.target_role.name
}

# Pre-created Glue job output
output "glue_job_name" {
  description = "Name of the pre-created Glue job"
  value       = aws_glue_job.initial_job.name
}

# S3 bucket and script outputs
output "script_bucket_name" {
  description = "Name of the S3 bucket containing the Glue job scripts"
  value       = aws_s3_bucket.script_bucket.id
}

output "benign_script_s3_path" {
  description = "S3 path to the benign script"
  value       = "s3://${aws_s3_bucket.script_bucket.id}/${aws_s3_object.benign_script.key}"
}

output "malicious_script_s3_path" {
  description = "S3 path to the malicious escalation script"
  value       = "s3://${aws_s3_bucket.script_bucket.id}/${aws_s3_object.malicious_script.key}"
}

# Attack path description
output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-guj-sjr-to-admin-starting-user) → glue:UpdateJob → Update existing job to use admin role and malicious script → glue:StartJobRun → Job executes Python script to attach AdministratorAccess policy to starting user → admin access"
}
