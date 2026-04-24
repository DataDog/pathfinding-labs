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

# Lambda function outputs
output "target_lambda_function_name" {
  description = "Name of the target Lambda function"
  value       = aws_lambda_function.target_lambda.function_name
}

output "target_lambda_function_arn" {
  description = "ARN of the target Lambda function"
  value       = aws_lambda_function.target_lambda.arn
}

output "lambda_exec_role_arn" {
  description = "ARN of the Lambda execution role with admin access"
  value       = aws_iam_role.lambda_exec_role.arn
}

output "lambda_exec_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_exec_role.name
}

# Aliases for consistency with root outputs.tf
output "target_role_arn" {
  description = "ARN of the target role (alias for lambda_exec_role_arn)"
  value       = aws_iam_role.lambda_exec_role.arn
}

output "target_role_name" {
  description = "Name of the target role (alias for lambda_exec_role_name)"
  value       = aws_iam_role.lambda_exec_role.name
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-lambda-005-to-admin-starting-user) → lambda:UpdateFunctionCode → target Lambda → lambda:AddPermission → allow self invoke → lambda:InvokeFunction → execute as lambda-exec-role (AdministratorAccess) → admin access"
}

output "flag_ssm_parameter_name" {
  description = "Name of the SSM parameter containing the CTF flag"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM parameter containing the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}
