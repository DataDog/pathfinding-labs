terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# PutRolePolicy + AssumeRole privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PutRolePolicy and sts:AssumeRole
# permissions on a target role can escalate privileges by adding an inline admin
# policy to that role, then assuming it to gain administrative access.

# Resource naming convention: pl-prod-iam-017-to-admin-{resource-type}
# iam-017 = pathfinding.cloud ID for this scenario

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-prod-iam-017-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-iam-017-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-putrolepolicy+sts-assumerole"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user with exploit permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-iam-017-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationPutRolePolicyAndAssumeRole"
        Effect = "Allow"
        Action = [
          "iam:PutRolePolicy",
          "sts:AssumeRole"
        ]
        Resource = aws_iam_role.target_role.arn
      },
      {
        Sid    = "HelpfulForExploitation"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "iam:ListRoles",
          "iam:GetRole",
          "iam:ListRolePolicies",
          "iam:GetRolePolicy"
        ]
        Resource = "*"
      }
    ]
  })
}

# Target role (initially has minimal permissions)
resource "aws_iam_role" "target_role" {
  force_detach_policies = true
  provider              = aws.prod
  name                  = "pl-prod-iam-017-to-admin-target-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = aws_iam_user.starting_user.arn
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-iam-017-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-putrolepolicy+sts-assumerole"
    Purpose     = "target-role"
  }
}

# CTF flag stored in SSM Parameter Store. The flag is readable by any principal
# with ssm:GetParameter on the parameter ARN — in practice this means any
# admin-equivalent principal, since AdministratorAccess grants the required
# permission implicitly. The starting user escalates to admin via iam:PutRolePolicy
# + sts:AssumeRole, then retrieves the flag.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/iam-017-to-admin"
  description = "CTF flag for the iam-017 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-iam-017-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-putrolepolicy+sts-assumerole"
    Purpose     = "ctf-flag"
  }
}

# Minimal read-only policy for the target role (initially no admin access)
resource "aws_iam_role_policy" "target_role_initial_policy" {
  provider = aws.prod
  name     = "pl-prod-iam-017-to-admin-target-role-initial-policy"
  role     = aws_iam_role.target_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "MinimalReadAccess"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "iam:GetUser",
          "iam:GetRole"
        ]
        Resource = "*"
      }
    ]
  })
}
