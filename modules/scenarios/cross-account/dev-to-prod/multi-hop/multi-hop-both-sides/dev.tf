terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.dev, aws.prod]
    }
  }
}

# Josh user in dev environment (admin user)
resource "aws_iam_user" "josh" {
  provider = aws.dev
  name     = "pl-Josh"
}

# Admin policy for Josh user
resource "aws_iam_user_policy" "josh_admin" {
  provider = aws.dev
  name     = "pl-Josh-admin"
  user     = aws_iam_user.josh.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      }
    ]
  })
}

# Helpdesk role in dev environment
resource "aws_iam_role" "helpdesk" {
  provider = aws.dev
  name     = "pl-helpdesk"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.dev_account_id}:user/pl-pathfinding-starting-user-dev"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Helpdesk policy with CreateLoginProfile permission
resource "aws_iam_policy" "helpdesk" {
  provider = aws.dev
  name     = "pl-helpdesk"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreateLoginProfile",
          "iam:GetLoginProfile",
          "iam:UpdateLoginProfile",
          "iam:DeleteLoginProfile",
          "iam:ListUsers",
          "iam:GetUser"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach helpdesk policy to helpdesk role
resource "aws_iam_role_policy_attachment" "helpdesk" {
  provider   = aws.dev
  role       = aws_iam_role.helpdesk.name
  policy_arn = aws_iam_policy.helpdesk.arn
}
