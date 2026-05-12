terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Scenario-specific starting user with AttachUserPolicy permission on itself
# This user can attach any managed policy to itself, including AdministratorAccess
resource "aws_iam_user" "starting_user" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-prod-iam-008-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-iam-008-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-attachuserpolicy"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Inline policy allowing the user to attach managed policies to itself
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-iam-008-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationAttachUserPolicy"
        Effect = "Allow"
        Action = [
          "iam:AttachUserPolicy"
        ]
        Resource = aws_iam_user.starting_user.arn
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "iam:ListAttachedUserPolicies",
          "iam:ListPolicies"
        ]
        Resource = "*"
      }
    ]
  })
}

# CTF flag stored in SSM Parameter Store. The attacker retrieves this after reaching
# administrator-equivalent permissions in the account. The flag lives in the victim
# (prod) account and is readable by any principal with ssm:GetParameter on the
# parameter ARN — in practice this means any admin-equivalent principal, since
# an inline policy granting Action:* on Resource:* provides the required permission.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/iam-008-to-admin"
  description = "CTF flag for the iam-008 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-iam-008-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-attachuserpolicy"
    Purpose     = "ctf-flag"
  }
}
