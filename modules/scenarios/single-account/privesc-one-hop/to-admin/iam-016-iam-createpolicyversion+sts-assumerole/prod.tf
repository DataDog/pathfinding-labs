terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# CreatePolicyVersion + AssumeRole privilege escalation scenario
#
# This scenario demonstrates how a user with iam:CreatePolicyVersion on a customer-managed policy
# attached to a role can create a new policy version with admin permissions, then assume that role
# to gain administrative access.

# Resource naming convention: pl-prod-iam-016-to-admin-{resource-type}
# Pathfinding.cloud ID: iam-016 (CreatePolicyVersion+AssumeRole)

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-prod-iam-016-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-iam-016-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-createpolicyversion+sts-assumerole"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Customer-managed policy with minimal permissions (will be modified by attack)
resource "aws_iam_policy" "target_policy" {
  provider    = aws.prod
  name        = "pl-prod-iam-016-to-admin-target-policy"
  description = "Customer-managed policy attached to target role (initial version has minimal permissions)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
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

  tags = {
    Name        = "pl-prod-iam-016-to-admin-target-policy"
    Environment = var.environment
    Scenario    = "iam-createpolicyversion+sts-assumerole"
    Purpose     = "target-policy"
  }
}

# Target role that will gain admin permissions via policy version update
resource "aws_iam_role" "target_role" {
  force_detach_policies = true
  provider              = aws.prod
  name                  = "pl-prod-iam-016-to-admin-target-role"

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
    Name        = "pl-prod-iam-016-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-createpolicyversion+sts-assumerole"
    Purpose     = "target-role"
  }
}

# Attach customer-managed policy to target role
resource "aws_iam_role_policy_attachment" "target_role_policy" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = aws_iam_policy.target_policy.arn
}

# CTF flag stored in SSM Parameter Store. The attacker retrieves this after reaching
# administrator-equivalent permissions in the account. The flag lives in the victim
# (prod) account and is readable by any principal with ssm:GetParameter on the
# parameter ARN — in practice this means any admin-equivalent principal, since
# AdministratorAccess grants the required permission implicitly.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/iam-016-to-admin"
  description = "CTF flag for the iam-016 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-iam-016-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-createpolicyversion+sts-assumerole"
    Purpose     = "ctf-flag"
  }
}

# Starting user policy granting exploitable permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-iam-016-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationCreatePolicyVersion"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicyVersion"
        ]
        Resource = aws_iam_policy.target_policy.arn
      },
      {
        Sid    = "RequiredForExploitationAssumeRole"
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = aws_iam_role.target_role.arn
      },
      {
        Sid    = "HelpfulForExploitation"
        Effect = "Allow"
        Action = [
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:ListRoles",
          "iam:GetRole",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}
