terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# iam-passrole+glue-createsession+glue-runstatement privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole, glue:CreateSession, and glue:RunStatement
# can pass a privileged role to an AWS Glue Interactive Session and run code that grants the starting
# user admin access by attaching AdministratorAccess policy.

# Resource naming convention: pl-prod-glue-007-to-admin-{resource-type}
# Provider: aws.prod

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-prod-glue-007-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-glue-007-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+glue-createsession+glue-runstatement"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user with required permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-glue-007-to-admin-starting-user-policy"
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
        Resource = aws_iam_role.admin_role.arn
      },
      {
        Sid    = "RequiredForExploitationGlue"
        Effect = "Allow"
        Action = [
          "glue:CreateSession",
          "glue:RunStatement"
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "glue:GetSession",
          "glue:GetStatement",
          "glue:DeleteSession"
        ]
        Resource = "*"
      }
    ]
  })
}

# Admin role (passed to Glue Interactive Session)
resource "aws_iam_role" "admin_role" {
  force_detach_policies = true
  provider              = aws.prod
  name                  = "pl-prod-glue-007-to-admin-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-glue-007-to-admin-admin-role"
    Environment = var.environment
    Scenario    = "iam-passrole+glue-createsession+glue-runstatement"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess to the admin role
resource "aws_iam_role_policy_attachment" "admin_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Attach AWS Glue Service Role for Glue operations
resource "aws_iam_role_policy_attachment" "admin_role_glue_service" {
  provider   = aws.prod
  role       = aws_iam_role.admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# CTF flag stored in SSM Parameter Store. The attacker retrieves this after reaching
# administrator-equivalent permissions in the account. The flag lives in the victim
# (prod) account and is readable by any principal with ssm:GetParameter on the
# parameter ARN — in practice this means any admin-equivalent principal, since
# AdministratorAccess grants the required permission implicitly.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/glue-007-to-admin"
  description = "CTF flag for the glue-007 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-glue-007-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-passrole+glue-createsession+glue-runstatement"
    Purpose     = "ctf-flag"
  }
}
