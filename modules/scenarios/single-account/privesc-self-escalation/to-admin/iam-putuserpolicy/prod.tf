terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Scenario-specific starting user with PutUserPolicy permission on itself
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-pup-to-admin-starting-user"
}

# Create access key for the user
resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Inline policy allowing the user to put inline policies on itself
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-pup-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:PutUserPolicy"
        ]
        Resource = aws_iam_user.starting_user.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "iam:GetUser",
          "iam:ListUserPolicies"
        ]
        Resource = "*"
      }
    ]
  })
}