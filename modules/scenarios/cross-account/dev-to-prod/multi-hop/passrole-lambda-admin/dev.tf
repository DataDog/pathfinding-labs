terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.dev, aws.prod]
    }
  }
}

# Lambda prod updater role in dev environment that starting user can assume
resource "aws_iam_role" "lambda_prod_updater" {
  provider = aws.dev
  name     = "pl-lambda-prod-updater"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowStartingUserToAssume"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.dev_account_id}:user/pl-pathfinding-starting-user-dev"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Policy that allows the role to assume the prod lambda updater role
resource "aws_iam_role_policy" "lambda_prod_updater" {
  provider = aws.dev
  name     = "pl-lambda-prod-updater"
  role     = aws_iam_role.lambda_prod_updater.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RequiredForExploitationAssumeRole"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = "arn:aws:iam::${var.prod_account_id}:role/pl-lambda-updater"
      }
    ]
  })
}
