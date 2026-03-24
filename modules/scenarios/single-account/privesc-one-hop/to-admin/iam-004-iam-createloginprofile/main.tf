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

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-iam-004-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-iam-004-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-createloginprofile"
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
  name     = "pl-prod-iam-004-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationAssumeRole"
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = "arn:aws:iam::${var.account_id}:role/pl-prod-iam-004-to-admin-starting-role"
      }
    ]
  })
}

# Admin user that will be the target of privilege escalation
# This user has AdministratorAccess but no console password (login profile)
resource "aws_iam_user" "admin_user" {
  provider = aws.prod
  name     = "pl-prod-iam-004-to-admin-target-user"

  tags = {
    Name        = "pl-prod-iam-004-to-admin-target-user"
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

# Starting role that can create login profiles (privilege escalation vector)
resource "aws_iam_role" "starting_role" {
  provider = aws.prod
  name     = "pl-prod-iam-004-to-admin-starting-role"

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
    Name        = "pl-prod-iam-004-to-admin-starting-role"
    Environment = var.environment
    Scenario    = "iam-createloginprofile"
    Purpose     = "starting-role"
  }
}

# Policy that allows creating login profiles for the admin user
resource "aws_iam_role_policy" "starting_role_policy" {
  provider = aws.prod
  name     = "CreateLoginProfilePermission"
  role     = aws_iam_role.starting_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationCreateLoginProfile"
        Effect = "Allow"
        Action = [
          "iam:CreateLoginProfile"
        ]
        Resource = aws_iam_user.admin_user.arn
      }
    ]
  })
}

# Create an access key for the admin user (for cleanup demonstration)
# This shows that even with API access, the user didn't have console access
resource "aws_iam_access_key" "admin_access_key" {
  provider = aws.prod
  user     = aws_iam_user.admin_user.name
}