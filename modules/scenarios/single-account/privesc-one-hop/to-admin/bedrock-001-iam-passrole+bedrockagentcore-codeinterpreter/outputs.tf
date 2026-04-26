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
  value       = aws_iam_access_key.starting_user_key.id
  sensitive   = true
}

output "starting_user_secret_access_key" {
  description = "Secret access key for the starting user"
  value       = aws_iam_access_key.starting_user_key.secret
  sensitive   = true
}

output "target_role_name" {
  description = "Name of the target admin role"
  value       = aws_iam_role.target_role.name
}

output "target_role_arn" {
  description = "ARN of the target admin role"
  value       = aws_iam_role.target_role.arn
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "starting_user (${aws_iam_user.starting_user.name}) → PassRole + CreateCodeInterpreter → code interpreter with admin role (${aws_iam_role.target_role.name}) → StartSession + InvokeCodeInterpreter → extract credentials from MMDS → admin access"
}

output "flag_ssm_parameter_name" {
  description = "SSM Parameter Store path where the CTF flag is stored"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM Parameter Store parameter containing the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}
