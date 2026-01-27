terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Scenario-specific starting user with AttachUserPolicy permission on itself
# This user can attach any managed policy to itself, including AdministratorAccess
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-iam-008-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-iam-008-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-attachuserpolicy"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Inline policy allowing the user to attach managed policies to itself
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-iam-008-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:AttachUserPolicy"
        ]
        Resource = aws_iam_user.starting_user.arn
      },
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
