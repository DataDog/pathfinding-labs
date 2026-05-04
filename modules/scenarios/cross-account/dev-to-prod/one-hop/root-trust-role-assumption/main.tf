# Cross-Account Root Trust Role Assumption privilege escalation scenario
#
# This scenario demonstrates how a user in the dev account can assume an admin role
# in the prod account when that role trusts the entire dev account via :root principal.
# This is a common misconfiguration where trust policies are overly permissive.

# Resource naming convention: pl-{environment}-xsarrt-to-admin-{resource-type}
# Shorthand: xsarrt = cross-account assume-role root-trust

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
  provider = aws.dev
  name     = "pl-dev-xsarrt-to-admin-starting-user"

  tags = {
    Name        = "pl-dev-xsarrt-to-admin-starting-user"
    Environment = "dev"
    Scenario    = "root-trust-role-assumption"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.dev
  user     = aws_iam_user.starting_user.name
}

# Policy allowing the starting user to assume the prod target role
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.dev
  name     = "pl-dev-xsarrt-to-admin-starting-user-policy"
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
        Resource = "arn:aws:iam::${var.prod_account_id}:role/pl-prod-xsarrt-to-admin-target-role"
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

# Target admin role in prod account with root trust
# CRITICAL: This role trusts the entire dev account via :root principal
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-xsarrt-to-admin-target-role"

  # MISCONFIGURATION: Trusts the entire dev account (:root)
  # This allows ANY principal in the dev account to assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.dev_account_id}:root"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-xsarrt-to-admin-target-role"
    Environment = "prod"
    Scenario    = "root-trust-role-assumption"
    Purpose     = "target-role"
  }
}

# Attach AdministratorAccess to the target role
resource "aws_iam_role_policy_attachment" "target_role_admin" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_ssm_parameter" "flag" {
  provider = aws.prod
  name     = "/pathfinding-labs/flags/root-trust-role-assumption-to-admin"
  type     = "String"
  value    = var.flag_value

  tags = {
    Name     = "pl-prod-root-trust-role-assumption-to-admin-flag"
    Scenario = "root-trust-role-assumption"
    Purpose  = "ctf-flag"
  }
}
