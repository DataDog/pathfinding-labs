output "chatbot_function_url" {
  description = "Public URL of the AcmeBot chatbot (serves HTML UI on GET, chat API on POST)"
  value       = aws_lambda_function_url.chatbot_url.function_url
}

output "chatbot_function_name" {
  description = "Name of the chatbot Lambda function"
  value       = aws_lambda_function.chatbot.function_name
}

output "chatbot_function_arn" {
  description = "ARN of the chatbot Lambda function"
  value       = aws_lambda_function.chatbot.arn
}

output "chatbot_role_arn" {
  description = "ARN of the chatbot execution role (limited Lambda permissions)"
  value       = aws_iam_role.chatbot_role.arn
}

output "chatbot_role_name" {
  description = "Name of the chatbot execution role"
  value       = aws_iam_role.chatbot_role.name
}

output "target_function_name" {
  description = "Name of the privileged target Lambda function"
  value       = aws_lambda_function.target.function_name
}

output "target_function_arn" {
  description = "ARN of the privileged target Lambda function"
  value       = aws_lambda_function.target.arn
}

output "target_role_arn" {
  description = "ARN of the target Lambda execution role (AdministratorAccess)"
  value       = aws_iam_role.target_role.arn
}

output "target_role_name" {
  description = "Name of the target Lambda execution role"
  value       = aws_iam_role.target_role.name
}

output "flag_ssm_parameter_name" {
  description = "SSM Parameter Store path of the CTF flag (admin-only read)"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM Parameter Store parameter containing the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}

output "starting_user_name" {
  description = "Name of the starting user"
  value       = aws_iam_user.starting_user.name
}

output "starting_user_arn" {
  description = "ARN of the starting user"
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

output "attack_path" {
  description = "Description of the attack path"
  value       = "Browser → AcmeBot chatbot (public URL) → prompt injection → run_command → env vars → chatbot role (limited Lambda perms) → lambda:ListFunctions → find pl-prod-ctf-002-acme-data-processor (admin role) → lambda:UpdateFunctionCode → malicious code → lambda:InvokeFunction → admin creds → ssm:GetParameter → FLAG"
}
