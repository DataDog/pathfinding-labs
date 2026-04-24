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

output "privesc_role_arn" {
  description = "ARN of the role with multiple privilege escalation paths"
  value       = aws_iam_role.prod_role_with_multiple_privesc_paths.arn
}

output "privesc_role_name" {
  description = "Name of the role with multiple privilege escalation paths"
  value       = aws_iam_role.prod_role_with_multiple_privesc_paths.name
}

output "ec2_admin_role_arn" {
  description = "ARN of the EC2 admin role"
  value       = aws_iam_role.prod_ec2_admin_role.arn
}

output "lambda_admin_role_arn" {
  description = "ARN of the Lambda admin role"
  value       = aws_iam_role.prod_lambda_admin_role.arn
}

output "cloudformation_admin_role_arn" {
  description = "ARN of the CloudFormation admin role"
  value       = aws_iam_role.prod_cloudformation_admin_role.arn
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-mpc-to-admin-starting-user) → AssumeRole → pl-prod-role-with-multiple-privesc-paths → [PassRole+EC2/Lambda/CloudFormation] → Admin Access"
}

output "flag_ssm_parameter_name" {
  description = "Name of the SSM parameter containing the CTF flag"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM parameter containing the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}
