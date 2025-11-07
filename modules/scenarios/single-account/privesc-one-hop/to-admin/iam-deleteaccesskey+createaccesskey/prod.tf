# iam-deleteaccesskey+createaccesskey privilege escalation scenario
#
# This scenario demonstrates how a user with iam:DeleteAccessKey and iam:CreateAccessKey
# can bypass AWS's 2-key limit by deleting an existing access key and creating a new one
# for an admin user to gain administrative access.
#
# Attack Path: starting_user → (iam:ListAccessKeys) → list existing keys →
#              (iam:DeleteAccessKey) → delete one key → (iam:CreateAccessKey) →
#              create new key for admin_user → admin access

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-dakcak-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-dakcak-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-deleteaccesskey+createaccesskey"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user (can delete and create access keys for admin user)
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-dakcak-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:ListAccessKeys",
          "iam:DeleteAccessKey",
          "iam:CreateAccessKey"
        ]
        Resource = aws_iam_user.admin_user.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# Admin user that will be the target of privilege escalation
resource "aws_iam_user" "admin_user" {
  provider = aws.prod
  name     = "pl-prod-dakcak-to-admin-target-user"

  tags = {
    Name        = "pl-prod-dakcak-to-admin-target-user"
    Environment = var.environment
    Scenario    = "iam-deleteaccesskey+createaccesskey"
    Purpose     = "admin-target"
  }
}

# Policy granting admin access to the target user
resource "aws_iam_user_policy_attachment" "admin_access" {
  provider   = aws.prod
  user       = aws_iam_user.admin_user.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Create two existing access keys for the admin user (demonstrating the 2-key limit)
resource "aws_iam_access_key" "admin_user_key_1" {
  provider = aws.prod
  user     = aws_iam_user.admin_user.name
}

resource "aws_iam_access_key" "admin_user_key_2" {
  provider = aws.prod
  user     = aws_iam_user.admin_user.name
}
