terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# IAM User with AttachUserPolicy permission on itself
# This user can attach any managed policy to itself, including AdministratorAccess
resource "aws_iam_user" "attachuserpolicy_user" {
  provider = aws.prod
  name     = "pl-attachuserpolicy-user"

  tags = {
    Name        = "pl-attachuserpolicy-user"
    Environment = var.environment
    Scenario    = "iam-attachuserpolicy"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "attachuserpolicy_user_key" {
  provider = aws.prod
  user     = aws_iam_user.attachuserpolicy_user.name
}

# Inline policy allowing the user to attach managed policies to itself
resource "aws_iam_user_policy" "attachuserpolicy_policy" {
  provider = aws.prod
  name     = "pl-attachuserpolicy-policy"
  user     = aws_iam_user.attachuserpolicy_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:AttachUserPolicy"
        ]
        Resource = "arn:aws:iam::${var.account_id}:user/pl-attachuserpolicy-user"
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
