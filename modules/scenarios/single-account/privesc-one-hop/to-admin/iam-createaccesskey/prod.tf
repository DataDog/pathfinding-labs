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
  name     = "pl-prod-one-hop-cak-starting-user"

  tags = {
    Name        = "pl-prod-one-hop-cak-starting-user"
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

# Minimal policy for the starting user (just enough to assume the role)
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-one-hop-cak-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = "arn:aws:iam::${var.account_id}:role/pl-prod-one-hop-cak-role"
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
  name     = "pl-prod-one-hop-cak-admin"

  tags = {
    Name        = "pl-prod-one-hop-cak-admin"
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

# Role that can create access keys for the admin user (privilege escalation vector)
resource "aws_iam_role" "privesc_role" {
  provider = aws.prod
  name     = "pl-prod-one-hop-cak-role"

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
    Name        = "pl-prod-one-hop-cak-role"
    Environment = var.environment
    Scenario    = "iam-createaccesskey"
    Purpose     = "vulnerable-role"
  }
}

# Policy that allows the role to create access keys for the admin user
resource "aws_iam_policy" "privesc_policy" {
  provider    = aws.prod
  name        = "pl-prod-one-hop-createaccesskey-policy"
  description = "Allows creating access keys for the admin user"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreateAccessKey"
        ]
        Resource = aws_iam_user.admin_user.arn
      }
    ]
  })
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "privesc_policy_attachment" {
  provider   = aws.prod
  role       = aws_iam_role.privesc_role.name
  policy_arn = aws_iam_policy.privesc_policy.arn
}

