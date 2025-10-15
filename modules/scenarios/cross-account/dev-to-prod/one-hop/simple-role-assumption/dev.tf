terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
      configuration_aliases = [aws.dev, aws.prod]
    }
  }
}

# IAM role in dev account that can assume the prod role
resource "aws_iam_role" "s3_access_role_dev" {
  provider = aws.dev
  name     = "pl-x-account-dev-s3-sensitive-data-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.dev_account_id}:user/pl-pathfinder-starting-user-dev"
        }
      }
    ]
  })
}

# IAM policy for the dev role to assume the prod role
resource "aws_iam_role_policy" "assume_role_policy" {
  provider = aws.dev
  name     = "pl-x-account-dev-assume-prod-s3-role-policy"
  role     = aws_iam_role.s3_access_role_dev.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = aws_iam_role.s3_access_role.arn
      }
    ]
  })
}

# IAM user in dev account that can assume the prod role
resource "aws_iam_user" "s3_access_user" {
  provider = aws.dev
  name     = "pl-x-account-dev-s3-sensitive-data-access-user"
}

# IAM policy for the dev user to assume the prod role
resource "aws_iam_user_policy" "user_assume_role_policy" {
  provider = aws.dev
  name     = "pl-x-account-dev-user-assume-prod-s3-role-policy"
  user     = aws_iam_user.s3_access_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = aws_iam_role.s3_access_role.arn
      }
    ]
  })
} 