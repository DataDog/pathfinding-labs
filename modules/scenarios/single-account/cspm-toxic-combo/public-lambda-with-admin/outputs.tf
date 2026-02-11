output "lambda_function_name" {
  description = "The name of the Lambda function"
  value       = aws_lambda_function.hello_world.function_name
}

output "lambda_function_arn" {
  description = "The ARN of the Lambda function"
  value       = aws_lambda_function.hello_world.arn
}

output "lambda_role_arn" {
  description = "The ARN of the Lambda function's IAM role"
  value       = aws_iam_role.lambda_admin_role.arn
}

output "lambda_function_url" {
  description = "The URL of the Lambda function"
  value       = aws_lambda_function_url.hello_world_url.function_url
} 