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
  name     = "pl-prod-one-hop-agp-starting-user"

  tags = {
    Name        = "pl-prod-one-hop-agp-starting-user"
    Environment = var.environment
    Scenario    = "iam-attachgrouppolicy"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# IAM Group that the starting user will be a member of
resource "aws_iam_group" "vulnerable_group" {
  provider = aws.prod
  name     = "pl-prod-one-hop-agp-group"
}

# Add the starting user to the group
resource "aws_iam_user_group_membership" "starting_user_membership" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name

  groups = [
    aws_iam_group.vulnerable_group.name
  ]
}

# Policy that allows the user to attach policies to their own group (privilege escalation vector)
resource "aws_iam_user_policy" "attach_group_policy" {
  provider = aws.prod
  name     = "pl-prod-one-hop-attachgrouppolicy-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:AttachGroupPolicy"
        ]
        Resource = aws_iam_group.vulnerable_group.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "iam:ListGroupsForUser"
        ]
        Resource = "*"
      }
    ]
  })
}
