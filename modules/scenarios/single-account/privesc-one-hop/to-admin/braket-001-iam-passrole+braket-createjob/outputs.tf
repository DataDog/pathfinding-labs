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

output "admin_role_arn" {
  description = "ARN of the admin role (target)"
  value       = aws_iam_role.admin_role.arn
}

output "admin_role_name" {
  description = "Name of the admin role"
  value       = aws_iam_role.admin_role.name
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for Braket job scripts and output"
  value       = aws_s3_bucket.braket_bucket.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for Braket job scripts and output"
  value       = aws_s3_bucket.braket_bucket.arn
}

output "attacker_bucket_name" {
  description = "Name of the attacker-controlled S3 bucket"
  value       = aws_s3_bucket.braket_bucket.id
}

output "flag_ssm_parameter_name" {
  description = "Name of the SSM parameter holding the CTF flag"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM parameter holding the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-braket-001-to-admin-starting-user) -> PassRole + CreateJob -> Braket Hybrid Job runs with Admin Role (pl-prod-braket-001-to-admin-admin-role) -> Malicious script attaches AdministratorAccess to starting user -> Admin Access -> ssm:GetParameter -> CTF flag"
}
