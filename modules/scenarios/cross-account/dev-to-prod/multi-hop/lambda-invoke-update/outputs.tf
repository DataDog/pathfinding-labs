output "dev_lambda_invoke_role_name" {
  description = "The name of the dev Lambda invoke role"
  value       = aws_iam_role.dev_lambda_invoke_role.name
}

output "dev_lambda_invoke_role_arn" {
  description = "The ARN of the dev Lambda invoke role"
  value       = aws_iam_role.dev_lambda_invoke_role.arn
}

output "prod_lambda_function_name" {
  description = "The name of the prod Lambda function"
  value       = aws_lambda_function.prod_hello_world.function_name
}

output "prod_lambda_function_arn" {
  description = "The ARN of the prod Lambda function"
  value       = aws_lambda_function.prod_hello_world.arn
}

output "prod_lambda_execution_role_name" {
  description = "The name of the prod Lambda execution role"
  value       = aws_iam_role.prod_lambda_execution_role.name
}

output "prod_lambda_execution_role_arn" {
  description = "The ARN of the prod Lambda execution role"
  value       = aws_iam_role.prod_lambda_execution_role.arn
}
