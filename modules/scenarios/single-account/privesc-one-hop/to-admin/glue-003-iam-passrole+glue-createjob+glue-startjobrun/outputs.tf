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

# Target admin role outputs
output "target_role_arn" {
  description = "ARN of the target admin role"
  value       = aws_iam_role.target_role.arn
}

output "target_role_name" {
  description = "Name of the target admin role"
  value       = aws_iam_role.target_role.name
}

# S3 bucket and script outputs
output "script_bucket_name" {
  description = "Name of the S3 bucket containing the Glue job script"
  value       = aws_s3_bucket.script_bucket.id
}

output "script_s3_path" {
  description = "S3 path to the escalation script"
  value       = "s3://${aws_s3_bucket.script_bucket.id}/${aws_s3_object.attack_script.key}"
}

# CTF flag outputs
output "flag_ssm_parameter_name" {
  description = "Name of the SSM parameter holding the CTF flag"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM parameter holding the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}

# Attack path description
output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-glue-003-to-admin-starting-user) → iam:PassRole + glue:CreateJob → Create Glue Job with admin role → glue:StartJobRun → Job executes Python script to attach AdministratorAccess policy to starting user → admin access → ssm:GetParameter → CTF flag"
}
