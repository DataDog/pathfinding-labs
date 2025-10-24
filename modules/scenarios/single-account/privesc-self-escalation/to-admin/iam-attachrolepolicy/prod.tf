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
  name     = "pl-prod-arp-to-admin-starting-user"
}

# Access key for the starting user
resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Basic policy for starting user (minimal permissions)
resource "aws_iam_user_policy" "starting_user_basic" {
  provider = aws.prod
  name     = "pl-prod-arp-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

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
      },
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = "arn:aws:iam::${var.prod_account_id}:role/pl-prod-arp-to-admin-starting-role"
      }
    ]
  })
}

# Role that can escalate its own privileges by attaching policies to itself
resource "aws_iam_role" "starting_role" {
  provider = aws.prod
  name     = "pl-prod-arp-to-admin-starting-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_user.starting_user.arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Policy that allows the role to attach policies to itself (self-privilege escalation)
resource "aws_iam_policy" "privesc_policy" {
  provider    = aws.prod
  name        = "pl-prod-arp-to-admin-policy"
  description = "Allows the role to attach policies to itself for privilege escalation"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:AttachRolePolicy"
        ]
        Resource = aws_iam_role.starting_role.arn
      }
    ]
  })
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "privesc_policy_attachment" {
  provider   = aws.prod
  role       = aws_iam_role.starting_role.name
  policy_arn = aws_iam_policy.privesc_policy.arn
}
