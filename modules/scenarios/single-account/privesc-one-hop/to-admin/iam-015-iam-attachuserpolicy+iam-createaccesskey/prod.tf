terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# AttachUserPolicy + CreateAccessKey privilege escalation scenario
#
# This scenario demonstrates how a user with iam:AttachUserPolicy and iam:CreateAccessKey
# permissions on a target user can attach AWS-managed AdministratorAccess policy to that user,
# create access keys for them, and gain admin access.

# Resource naming convention: pl-prod-iam-015-to-admin-{resource-type}
# All resources use provider = aws.prod

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-iam-015-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-iam-015-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-attachuserpolicy+iam-createaccesskey"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user granting AttachUserPolicy and CreateAccessKey on target user
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-iam-015-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationAttachUserPolicyAndCreateAccessKey"
        Effect = "Allow"
        Action = [
          "iam:AttachUserPolicy",
          "iam:CreateAccessKey"
        ]
        Resource = aws_iam_user.target_user.arn
      },
      {
        Sid    = "HelpfulForExploitation"
        Effect = "Allow"
        Action = [
          "iam:ListUsers",
          "iam:GetUser",
          "iam:ListAttachedUserPolicies",
          "iam:ListPolicies",
          "iam:ListAccessKeys",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# Target user that will be escalated to admin
resource "aws_iam_user" "target_user" {
  provider = aws.prod
  name     = "pl-prod-iam-015-to-admin-target-user"

  tags = {
    Name        = "pl-prod-iam-015-to-admin-target-user"
    Environment = var.environment
    Scenario    = "iam-attachuserpolicy+iam-createaccesskey"
    Purpose     = "target-user"
  }
}

# CTF flag stored in SSM Parameter Store. The attacker retrieves this after reaching
# administrator-equivalent permissions in the account. The flag lives in the victim
# (prod) account and is readable by any principal with ssm:GetParameter on the
# parameter ARN — in practice this means any admin-equivalent principal, since
# AdministratorAccess grants the required permission implicitly.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/iam-015-to-admin"
  description = "CTF flag for the iam-015 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-iam-015-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-attachuserpolicy+iam-createaccesskey"
    Purpose     = "ctf-flag"
  }
}

# Minimal initial policy for target user (no admin access yet)
resource "aws_iam_user_policy" "target_user_initial_policy" {
  provider = aws.prod
  name     = "pl-prod-iam-015-to-admin-target-user-initial-policy"
  user     = aws_iam_user.target_user.name

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
      }
    ]
  })
}
