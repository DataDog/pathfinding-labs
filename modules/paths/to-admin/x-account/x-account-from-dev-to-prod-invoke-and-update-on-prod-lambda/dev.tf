terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
      configuration_aliases = [aws.dev]
    }
  }
}

# Dev role that can invoke and update the prod Lambda function
resource "aws_iam_role" "dev_lambda_invoke_role" {
  provider = aws.dev
  name     = "pl-dev-lambda-invoke-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.dev_account_id}:user/pl-pathfinder-starting-user-dev"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Policy that allows invoking and updating Lambda functions in prod
resource "aws_iam_policy" "dev_lambda_invoke_policy" {
  provider = aws.dev
  name     = "pl-dev-lambda-invoke-policy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction",
          "lambda:UpdateFunctionCode"
        ]
        Resource = "arn:aws:lambda:us-west-2:${var.prod_account_id}:function:pl-prod-hello-world-*"
      }
    ]
  })
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "dev_lambda_invoke_role" {
  provider = aws.dev
  role     = aws_iam_role.dev_lambda_invoke_role.name
  policy_arn = aws_iam_policy.dev_lambda_invoke_policy.arn
}
