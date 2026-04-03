# iam-createaccesskey privilege escalation scenario
#
# This scenario demonstrates how a user with iam:CreateAccessKey permission
# can create access keys for an admin user to gain administrative access.
#
# Attack Path: starting_user → (iam:CreateAccessKey) → admin_user credentials → admin access

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
  name     = "pl-prod-iam-002-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-iam-002-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-createaccesskey"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user (can create access keys for admin user)
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-iam-002-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationCreateAccessKey"
        Effect = "Allow"
        Action = [
          "iam:CreateAccessKey"
        ]
        Resource = aws_iam_user.admin_user.arn
      },
      {
        Sid    = "HelpfulForExploitation"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "iam:ListUsers",
          "iam:GetUser",
          "iam:ListAttachedUserPolicies"
        ]
        Resource = "*"
      }
    ]
  })
}

# Admin user that will be the target of privilege escalation
resource "aws_iam_user" "admin_user" {
  provider = aws.prod
  name     = "pl-prod-iam-002-to-admin-target-user"

  tags = {
    Name        = "pl-prod-iam-002-to-admin-target-user"
    Environment = var.environment
    Scenario    = "iam-createaccesskey"
    Purpose     = "admin-target"
  }
}

# Policy granting admin access to the target user
resource "aws_iam_user_policy_attachment" "admin_access" {
  provider   = aws.prod
  user       = aws_iam_user.admin_user.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
