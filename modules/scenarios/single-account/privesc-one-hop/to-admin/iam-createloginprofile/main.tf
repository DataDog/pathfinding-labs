# IAM CreateLoginProfile privilege escalation to admin scenario
#
# This scenario demonstrates how a role with iam:CreateLoginProfile permission
# can escalate to administrative privileges by creating a console password
# for an existing admin user without a login profile.

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Admin user that will be the target of privilege escalation
# This user has AdministratorAccess but no console password (login profile)
resource "aws_iam_user" "admin_user" {
  provider = aws.prod
  name     = "pl-clp-admin"

  tags = {
    Name        = "pl-clp-admin"
    Environment = var.environment
    Scenario    = "iam-createloginprofile"
    Purpose     = "target-admin-user"
  }
}

# Attach AdministratorAccess to the admin user
resource "aws_iam_user_policy_attachment" "admin_access" {
  provider   = aws.prod
  user       = aws_iam_user.admin_user.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Role that can create login profiles (privilege escalation vector)
resource "aws_iam_role" "privesc_role" {
  provider = aws.prod
  name     = "pl-clp-clifford"

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

  tags = {
    Name        = "pl-clp-clifford"
    Environment = var.environment
    Scenario    = "iam-createloginprofile"
    Purpose     = "starting-role"
  }
}

# Policy that allows creating login profiles for the admin user
resource "aws_iam_policy" "privesc_policy" {
  provider    = aws.prod
  name        = "pl-prod-one-hop-createloginprofile-policy"
  description = "Allows creating login profiles for the admin user"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreateLoginProfile",
          "iam:GetLoginProfile" # To check if login profile exists
        ]
        Resource = aws_iam_user.admin_user.arn
      },
      {
        Effect = "Allow"
        Action = [
          "iam:GetUser",          # To get user details
          "sts:GetCallerIdentity" # For identity verification
        ]
        Resource = "*"
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

# Create an access key for the admin user (for cleanup demonstration)
# This shows that even with API access, the user didn't have console access
resource "aws_iam_access_key" "admin_access_key" {
  provider = aws.prod
  user     = aws_iam_user.admin_user.name
}