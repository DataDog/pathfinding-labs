terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.dev]
    }
  }
}

# IAM role for Lambda with AdministratorAccess
resource "aws_iam_role" "lambda_admin_role" {
  force_detach_policies = true
  provider              = aws.dev
  name                  = "pl-lambda-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationLambdaAssumeRole"
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
  provider      = aws.dev
  filename      = "${path.module}/lambda/lambda_function.zip"
  function_name = "hello-world-admin"
  role          = aws_iam_role.lambda_admin_role.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"

  source_code_hash = filebase64sha256("${path.module}/lambda/lambda_function.zip")
}

# Lambda function URL
resource "aws_lambda_function_url" "hello_world_url" {
  provider           = aws.dev
  function_name      = aws_lambda_function.hello_world.function_name
  authorization_type = "NONE" # Makes the function publicly accessible
}

# CTF flag stored in SSM Parameter Store. The attacker retrieves this after reaching
# administrator-equivalent permissions by extracting the Lambda execution role's
# temporary credentials from the function's HTTP response. The flag lives in the same
# account as the Lambda function and is readable by any principal with ssm:GetParameter
# on the parameter ARN — in practice this means any caller holding the admin execution
# role's credentials, since AdministratorAccess grants the required permission implicitly.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.dev
  name        = "/pathfinding-labs/flags/public-lambda-with-admin-to-admin"
  description = "CTF flag for the public-lambda-with-admin to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name     = "pl-public-lambda-with-admin-to-admin-flag"
    Scenario = "public-lambda-with-admin"
    Purpose  = "ctf-flag"
  }
}