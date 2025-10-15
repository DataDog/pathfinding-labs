terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Admin user that will be the target of privilege escalation
resource "aws_iam_user" "admin_user" {
  provider = aws.prod
  name     = "pl-cak-admin"
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
  name     = "pl-cak-adam"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:user/pl-pathfinder-starting-user-prod"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
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

