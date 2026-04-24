output "lambda_prod_updater_role_name" {
  description = "The name of the lambda prod updater role in dev"
  value       = aws_iam_role.lambda_prod_updater.name
}

output "lambda_prod_updater_role_arn" {
  description = "The ARN of the lambda prod updater role"
  value       = aws_iam_role.lambda_prod_updater.arn
}

output "lambda_updater_role_name" {
  description = "The name of the lambda updater role in prod"
  value       = aws_iam_role.lambda_updater.name
}

output "lambda_updater_role_arn" {
  description = "The ARN of the lambda updater role in prod"
  value       = aws_iam_role.lambda_updater.arn
}

output "lambda_admin_role_name" {
  description = "The name of the lambda admin role in prod"
  value       = aws_iam_role.lambda_admin.name
}

output "lambda_admin_role_arn" {
  description = "The ARN of the lambda admin role in prod"
  value       = aws_iam_role.lambda_admin.arn
}

output "flag_ssm_parameter_name" {
  description = "Name of the SSM parameter containing the CTF flag"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM parameter containing the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}
