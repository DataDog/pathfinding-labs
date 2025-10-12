
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
      configuration_aliases = [aws.dev]
    }
  }
}

resource "aws_iam_user" "dev-admin" {
  provider = aws.dev
  name     = "pl-dev-admin"
}

resource "aws_iam_user_policy" "dev-admin" {
  provider = aws.dev
  name     = "pl-dev-admin"
  user     = aws_iam_user.dev-admin.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = "*",
        Resource = "*"
      }
    ]
  })
}

# Adam user who can create access keys for the dev-admin user
resource "aws_iam_user" "adam" {
  provider = aws.dev
  name     = "pl-Adam"
}

# Policy that allows Adam to create access keys for pl-dev-admin specifically
resource "aws_iam_user_policy" "adam_create_access_key" {
  provider = aws.dev
  name     = "pl-Adam-createAccessKey"
  user     = aws_iam_user.adam.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "iam:CreateAccessKey"
        Resource = "arn:aws:iam::${var.dev_account_id}:user/pl-dev-admin"
      }
    ]
  })
}

