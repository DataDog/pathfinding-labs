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
# S3 CODE BUCKET OUTPUTS
# =============================================================================

output "code_bucket_name" {
  description = "S3 bucket containing the Flink application JAR"
  value       = aws_s3_bucket.flink_code.id
}

output "code_bucket_key" {
  description = "S3 object key for the exploit JAR"
  value       = aws_s3_object.exploit_jar.key
}

# =============================================================================
# ATTACKER BUCKET OUTPUTS
# =============================================================================

output "attacker_bucket_name" {
  description = "Name of the attacker-controlled S3 bucket containing the exploit JAR"
  value       = aws_s3_bucket.flink_code.id
}

# =============================================================================
# ATTACK PATH DESCRIPTION
# =============================================================================

output "attack_path" {
  description = "Description of the attack path"
  value       = "starting_user (${aws_iam_user.starting_user.name}) -> (kinesisanalytics:CreateApplication with S3 code) -> (iam:PassRole + kinesisanalytics:StartApplication with ${aws_iam_role.admin_role.name} as service execution role) -> Flink app attaches AdministratorAccess to starting user -> admin access"
}

# =============================================================================
# CTF FLAG OUTPUTS
# =============================================================================

output "flag_ssm_parameter_name" {
  description = "Name of the SSM parameter holding the CTF flag"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM parameter holding the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}
