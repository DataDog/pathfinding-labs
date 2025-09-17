terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
      configuration_aliases = [aws.dev, aws.prod]
    }
  }
}

# Lambda prod updater user in dev environment
resource "aws_iam_user" "lambda_prod_updater" {
  provider = aws.dev
  name     = "pl-lambda-prod-updater"
}

# Policy that allows the user to assume roles
resource "aws_iam_user_policy" "lambda_prod_updater" {
  provider = aws.dev
  name     = "pl-lambda-prod-updater"
  user     = aws_iam_user.lambda_prod_updater.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = "arn:aws:iam::${var.prod_account_id}:role/pl-lambda-updater"
      }
    ]
  })
}
