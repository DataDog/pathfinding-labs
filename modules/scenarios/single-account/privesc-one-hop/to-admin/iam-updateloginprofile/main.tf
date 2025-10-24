# IAM UpdateLoginProfile privilege escalation to admin scenario
#
# This scenario demonstrates how a role with iam:UpdateLoginProfile permission
# can escalate to administrative privileges by changing the console password
# of an existing admin user who already has a login profile.

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
  name     = "pl-prod-ulp-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-ulp-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-updateloginprofile"
    Purpose     = "starting-user"
  }
}

# Access key for the starting user
resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Basic policy for starting user
resource "aws_iam_user_policy" "starting_user_basic" {
  provider = aws.prod
  name     = "pl-prod-ulp-to-admin-starting-user-policy"
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
        Resource = "arn:aws:iam::${var.account_id}:role/pl-prod-ulp-to-admin-starting-role"
      }
    ]
  })
}

# Admin user that will be the target of privilege escalation
# This user has AdministratorAccess AND an existing console password (login profile)
resource "aws_iam_user" "admin_user" {
  provider = aws.prod
  name     = "pl-prod-ulp-to-admin-target-user"

  tags = {
    Name        = "pl-prod-ulp-to-admin-target-user"
    Environment = var.environment
    Scenario    = "iam-updateloginprofile"
    Purpose     = "target-admin-user"
  }
}

# Attach AdministratorAccess to the admin user
resource "aws_iam_user_policy_attachment" "admin_access" {
  provider   = aws.prod
  user       = aws_iam_user.admin_user.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Create an existing login profile for the admin user
# This represents a pre-existing console password that the attacker will update
resource "aws_iam_user_login_profile" "admin_login_profile" {
  provider                = aws.prod
  user                    = aws_iam_user.admin_user.name
  password_reset_required = false

  lifecycle {
    ignore_changes = [
      password_length,
      password_reset_required,
      pgp_key
    ]
  }
}

# Starting role that can update login profiles (privilege escalation vector)
resource "aws_iam_role" "starting_role" {
  provider = aws.prod
  name     = "pl-prod-ulp-to-admin-starting-role"

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
    Name        = "pl-prod-ulp-to-admin-starting-role"
    Environment = var.environment
    Scenario    = "iam-updateloginprofile"
    Purpose     = "starting-role"
  }
}

# Policy that allows updating login profiles for the admin user
resource "aws_iam_role_policy" "starting_role_policy" {
  provider = aws.prod
  name     = "UpdateLoginProfilePermission"
  role     = aws_iam_role.starting_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowUpdateLoginProfile"
        Effect = "Allow"
        Action = [
          "iam:UpdateLoginProfile",
          "iam:GetLoginProfile" # To check if login profile exists
        ]
        Resource = aws_iam_user.admin_user.arn
      },
      {
        Sid    = "AllowSelfIdentification"
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
