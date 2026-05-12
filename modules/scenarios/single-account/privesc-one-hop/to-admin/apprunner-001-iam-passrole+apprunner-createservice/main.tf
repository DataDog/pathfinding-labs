terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# iam:PassRole + apprunner:CreateService privilege escalation scenario
#
# This scenario demonstrates how an attacker with apprunner:CreateService and iam:PassRole
# permissions can escalate privileges to administrator by creating an App Runner service with
# a privileged role and using StartCommand override to grant themselves admin access.

# Resource naming convention: pl-prod-apprunner-001-to-admin-{resource-type}
# Provider: aws.prod (single account scenario)

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-prod-apprunner-001-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-apprunner-001-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+apprunner-createservice"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user (PassRole + App Runner permissions)
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-apprunner-001-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.target_role.arn
      },
      {
        Sid    = "RequiredForExploitationAppRunner"
        Effect = "Allow"
        Action = [
          "apprunner:CreateService"
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "apprunner:ListServices",
          "apprunner:DescribeService"
        ]
        Resource = "*"
      }
    ]
  })
}

# Target role with admin permissions that will be passed to App Runner
resource "aws_iam_role" "target_role" {
  force_detach_policies = true
  provider              = aws.prod
  name                  = "pl-prod-apprunner-001-to-admin-target-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "tasks.apprunner.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-apprunner-001-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-passrole+apprunner-createservice"
    Purpose     = "target-role-for-apprunner"
  }
}

# Policy allowing the target role to grant admin access to the starting user
resource "aws_iam_role_policy" "target_role_policy" {
  provider = aws.prod
  name     = "pl-prod-apprunner-001-to-admin-target-role-policy"
  role     = aws_iam_role.target_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      }
    ]
  })
}

# CTF flag stored in SSM Parameter Store. The attacker retrieves this after reaching
# administrator-equivalent permissions in the account. The flag lives in the victim
# (prod) account and is readable by any principal with ssm:GetParameter on the
# parameter ARN — in practice this means any admin-equivalent principal, since
# AdministratorAccess grants the required permission implicitly.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/apprunner-001-to-admin"
  description = "CTF flag for the apprunner-001 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-apprunner-001-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-passrole+apprunner-createservice"
    Purpose     = "ctf-flag"
  }
}
