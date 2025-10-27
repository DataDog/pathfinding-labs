# PutUserPolicy + CreateAccessKey privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PutUserPolicy and iam:CreateAccessKey
# permissions on another user can escalate privileges by adding an admin policy to that
# user and then creating access keys to authenticate as them.

# Resource naming convention: pl-prod-pupcak-to-admin-{resource-type}

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-pupcak-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-pupcak-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-putuserpolicy+iam-createaccesskey"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user granting the exploitable permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-pupcak-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:PutUserPolicy",
          "iam:CreateAccessKey"
        ]
        Resource = aws_iam_user.target_user.arn
      },
      {
        Effect = "Allow"
        Action = [
          "iam:ListUsers",
          "iam:GetUser",
          "iam:ListUserPolicies",
          "iam:GetUserPolicy",
          "iam:ListAccessKeys"
        ]
        Resource = "*"
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

# Target user (victim user that will be escalated)
resource "aws_iam_user" "target_user" {
  provider = aws.prod
  name     = "pl-prod-pupcak-to-admin-target-user"

  tags = {
    Name        = "pl-prod-pupcak-to-admin-target-user"
    Environment = var.environment
    Scenario    = "iam-putuserpolicy+iam-createaccesskey"
    Purpose     = "target-user"
  }
}

# Initial minimal policy for target user (before escalation)
resource "aws_iam_user_policy" "target_user_initial_policy" {
  provider = aws.prod
  name     = "pl-prod-pupcak-to-admin-target-user-initial-policy"
  user     = aws_iam_user.target_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "iam:GetUser"
        ]
        Resource = "*"
      }
    ]
  })
}
