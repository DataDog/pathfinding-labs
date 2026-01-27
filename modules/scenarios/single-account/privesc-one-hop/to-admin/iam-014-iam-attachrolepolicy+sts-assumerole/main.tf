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
  name     = "pl-prod-iam-014-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-iam-014-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-attachrolepolicy+sts-assumerole"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user with privilege escalation permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-iam-014-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:AttachRolePolicy"
        ]
        Resource = "arn:aws:iam::${var.account_id}:role/pl-prod-iam-014-to-admin-target-role"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = "arn:aws:iam::${var.account_id}:role/pl-prod-iam-014-to-admin-target-role"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "iam:ListRoles",
          "iam:GetRole",
          "iam:ListAttachedRolePolicies"
        ]
        Resource = "*"
      }
    ]
  })
}

# Target role that will be escalated to admin
# Initially has minimal permissions (or none) - admin access will be attached during the attack
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-iam-014-to-admin-target-role"

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

  tags = {
    Name        = "pl-prod-iam-014-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-attachrolepolicy+sts-assumerole"
    Purpose     = "target-role"
  }
}

# Minimal initial policy for the target role (read-only)
# This demonstrates that the role starts with minimal permissions
resource "aws_iam_role_policy" "target_role_minimal_policy" {
  provider = aws.prod
  name     = "pl-prod-iam-014-to-admin-minimal-policy"
  role     = aws_iam_role.target_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
