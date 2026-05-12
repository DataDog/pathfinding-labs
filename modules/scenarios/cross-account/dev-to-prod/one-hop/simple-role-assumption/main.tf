# Cross-Account Simple Role Assumption privilege escalation scenario
#
# This scenario demonstrates how a user in the dev account can directly assume
# an admin role in the prod account when the role's trust policy explicitly
# allows the dev user.

# Resource naming convention: pl-{environment}-xsare-to-admin-{resource-type}
# xsare = Cross-account Simple Role Assumption

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.dev, aws.prod]
    }
  }
}

# =============================================================================
# DEV ACCOUNT RESOURCES
# =============================================================================

# Scenario-specific starting user in dev account
resource "aws_iam_user" "starting_user" {
  force_destroy = true
  provider      = aws.dev
  name          = "pl-dev-xsare-to-admin-starting-user"

  tags = {
    Name        = "pl-dev-xsare-to-admin-starting-user"
    Environment = "dev"
    Scenario    = "simple-role-assumption"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.dev
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user (allows assuming the prod admin role)
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.dev
  name     = "pl-dev-xsare-to-admin-starting-user-policy"
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
        Resource = "arn:aws:iam::${var.prod_account_id}:role/pl-prod-xsare-to-admin-target-role"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "iam:ListRoles"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# PROD ACCOUNT RESOURCES
# =============================================================================

# Target admin role in prod account
resource "aws_iam_role" "target_role" {
  force_detach_policies = true
  provider              = aws.prod
  name                  = "pl-prod-xsare-to-admin-target-role"

  # Trust policy explicitly allows the dev user to assume this role
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
    Name        = "pl-prod-xsare-to-admin-target-role"
    Environment = "prod"
    Scenario    = "simple-role-assumption"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess policy to the target role
resource "aws_iam_role_policy_attachment" "target_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# CTF flag stored in prod account SSM Parameter Store
# The flag is only accessible after gaining admin access in the prod account
resource "aws_ssm_parameter" "flag" {
  provider = aws.prod
  name     = "/pathfinding-labs/flags/dev-to-prod-simple-role-assumption-to-admin"
  type     = "String"
  value    = var.flag_value

  tags = {
    Name        = "pl-prod-xsare-to-admin-ctf-flag"
    Environment = "prod"
    Scenario    = "simple-role-assumption"
    Purpose     = "ctf-flag"
  }
}
