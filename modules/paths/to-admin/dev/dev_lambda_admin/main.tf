terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
      configuration_aliases = [aws.dev]
    }
  }
}

# IAM role for Lambda with AdministratorAccess
resource "aws_iam_role" "lambda_admin_role" {
  provider = aws.dev
  name     = "pl-lambda-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Attach AdministratorAccess policy to the role
resource "aws_iam_role_policy_attachment" "lambda_admin_policy" {
  provider   = aws.dev
  role       = aws_iam_role.lambda_admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Lambda function
resource "aws_lambda_function" "hello_world" {
  provider         = aws.dev
  filename         = "${path.module}/lambda/lambda_function.zip"
  function_name    = "hello-world-admin"
  role            = aws_iam_role.lambda_admin_role.arn
  handler         = "index.handler"
  runtime         = "nodejs18.x"

  source_code_hash = filebase64sha256("${path.module}/lambda/lambda_function.zip")
}

# Lambda function URL
resource "aws_lambda_function_url" "hello_world_url" {
  provider           = aws.dev
  function_name      = aws_lambda_function.hello_world.function_name
  authorization_type = "NONE"  # Makes the function publicly accessible
} 