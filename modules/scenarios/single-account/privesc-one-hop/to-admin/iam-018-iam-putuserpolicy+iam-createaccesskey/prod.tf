terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# PutUserPolicy + CreateAccessKey privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PutUserPolicy and iam:CreateAccessKey
# permissions on another user can escalate privileges by adding an admin policy to that
# user and then creating access keys to authenticate as them.

# Resource naming convention: pl-prod-iam-018-to-admin-{resource-type}

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-prod-iam-018-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-iam-018-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-putuserpolicy+iam-createaccesskey"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user granting the exploitable permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-iam-018-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationPutUserPolicyAndCreateAccessKey"
        Effect = "Allow"
        Action = [
          "iam:PutUserPolicy",
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
          "iam:ListUserPolicies",
          "iam:GetUserPolicy",
          "iam:ListAccessKeys",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# Target user (victim user that will be escalated)
resource "aws_iam_user" "target_user" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-prod-iam-018-to-admin-target-user"

  tags = {
    Name        = "pl-prod-iam-018-to-admin-target-user"
    Environment = var.environment
    Scenario    = "iam-putuserpolicy+iam-createaccesskey"
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
  name        = "/pathfinding-labs/flags/iam-018-to-admin"
  description = "CTF flag for the iam-018 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-iam-018-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-putuserpolicy+iam-createaccesskey"
    Purpose     = "ctf-flag"
  }
}

# Initial minimal policy for target user (before escalation)
resource "aws_iam_user_policy" "target_user_initial_policy" {
  provider = aws.prod
  name     = "pl-prod-iam-018-to-admin-target-user-initial-policy"
  user     = aws_iam_user.target_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BaselineIdentityPermissions"
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
